import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bell B-1 — domain, state and event routing.
//
// The race result is ChangeTurn, the same field WDYK's turn already drives —
// so "who is answering" is GameSessionState.isMyTurn / isOpponentTurn, not a
// second identity field. The only new field is bellArmed: whether the Bell
// button may be tapped right now, which nothing existing represents.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
    return true;
  }

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) =>
      () {};

  @override
  void reattachEventHandlers() {}
}

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast();

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  void emit(String name, Map<String, dynamic>? data) {
    _events.add(GameHubEvent(name: name, data: data));
  }

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

Map<String, dynamic> _bellGame({
  String currentTurn = '',
  bool? isTimerStarted,
  double? currentTimerValue,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 3,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      if (isTimerStarted != null) 'isTimerStarted': isTimerStarted,
      if (currentTimerValue != null) 'currentTimerValue': currentTimerValue,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;
  late _FakeSignalRService signalR;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    bindings = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  Future<void> enterBell({String currentTurn = ''}) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _bellGame(currentTurn: currentTurn),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emit(String name, Map<String, dynamic>? data) async {
    bindings.emit(name, data);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> armBell() async {
    await enterBell();
    await emit(PlayGameHubEvents.timeStarted, null);
  }

  group('NextRoundStarted(3)', () {
    test('starts a clean Bell idle state', () async {
      // Bell state is dirtied first (armed, racing) so the reset is actually
      // exercised, not just trivially true from a fresh container.
      await armBell();
      expect(current().bellArmed, isTrue);

      await emit(PlayGameHubEvents.nextRoundStarted, {'arg0': 3, 'arg1': 'g1'});

      expect(current().phase, GamePhase.bell);
      expect(current().bellArmed, isFalse);
      expect(current().game?.currentTurn, isEmpty);
      expect(notifier().bellPhase, BellPhase.idle);
      expect(notifier().isBellVisible, isFalse);
    });
  });

  group('TimeStarted arms the Bell', () {
    test('no turn yet → Racing, Bell visible and armed', () async {
      await enterBell();

      await emit(PlayGameHubEvents.timeStarted, null);

      expect(notifier().bellPhase, BellPhase.racing);
      expect(notifier().isBellVisible, isTrue);
      expect(current().bellArmed, isTrue);
    });

    test('a turn already exists → no Bell', () async {
      await enterBell(currentTurn: _localId);

      await emit(PlayGameHubEvents.timeStarted, null);

      expect(notifier().bellPhase, BellPhase.answering);
      expect(notifier().isBellVisible, isFalse);
      expect(current().bellArmed, isFalse);
    });
  });

  group('ChangeTurn is the race result', () {
    test('names me while racing → answering/me, Bell hidden', () async {
      await armBell();

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );

      expect(current().game?.currentTurn, _localId);
      expect(current().isMyTurn, isTrue);
      expect(current().isOpponentTurn, isFalse);
      expect(notifier().bellPhase, BellPhase.answering);
      expect(notifier().isBellVisible, isFalse);
      expect(current().bellArmed, isFalse);
    });

    test('names the opponent while racing → answering/opponent, Bell hidden',
        () async {
      await armBell();

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );

      expect(current().game?.currentTurn, _opponentId);
      expect(current().isOpponentTurn, isTrue);
      expect(current().isMyTurn, isFalse);
      expect(notifier().bellPhase, BellPhase.answering);
      expect(notifier().isBellVisible, isFalse);
      expect(current().bellArmed, isFalse);
    });

    test('an explicitly empty playerId resets the race', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      expect(notifier().bellPhase, BellPhase.answering);

      await emit(PlayGameHubEvents.changeTurn, {'arg0': '', 'arg1': 'g1'});

      expect(current().game?.currentTurn, isEmpty);
      expect(notifier().bellPhase, BellPhase.idle,
          reason: 'hidden until the next TimeStarted, not re-armed');
      expect(notifier().isBellVisible, isFalse);
      expect(current().bellArmed, isFalse);
    });

    test('without a race, the normal-turn field still updates', () async {
      // Bell reference §I: a turn assigned without a buzz is not "fastest" —
      // this only asserts the shared field still updates the normal way;
      // the "fastest" vs "normal turn" overlay choice is a B-2 dialog concern.
      await enterBell();

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );

      expect(current().game?.currentTurn, _localId);
      expect(current().isMyTurn, isTrue);
      expect(current().bellArmed, isFalse,
          reason: 'never armed in the first place');
    });
  });

  group('RingBell', () {
    test('sends the request without locally declaring a winner', () async {
      await armBell();
      expect(notifier().canRingBell, isTrue);

      final sent = await notifier().ringBell();

      expect(sent, isTrue);
      expect(signalR.invocations, hasLength(1));
      expect(signalR.invocations.single.method, PlayGameHubEvents.ringBell);
      expect(signalR.invocations.single.args, ['g1']);
      // Nothing local changed — still racing, no turn assigned, not armed by
      // this call, only by the TimeStarted that already happened.
      expect(notifier().bellPhase, BellPhase.racing);
      expect(current().game?.currentTurn ?? '', isEmpty);
      expect(current().bellArmed, isTrue);
    });

    test('is ignored before the Bell is armed', () async {
      await enterBell();
      expect(notifier().canRingBell, isFalse);

      final sent = await notifier().ringBell();

      expect(sent, isFalse);
      expect(signalR.invocations, isEmpty);
    });

    test('is ignored once a turn is already assigned', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      expect(notifier().canRingBell, isFalse);

      final sent = await notifier().ringBell();

      expect(sent, isFalse);
      expect(signalR.invocations, isEmpty);
    });
  });

  group('Penalty', () {
    test('type 2 (wrong) disarms Bell without any WDYK strike state',
        () async {
      await armBell();

      await emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );

      expect(current().bellArmed, isFalse);
      expect(current().game?.isTimerStarted, isFalse);
      expect(notifier().bellPhase, BellPhase.idle);
    });

    test('type 1 (timeout) clears/locks Bell — it must not remain active',
        () async {
      await armBell();

      await emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 1},
      );

      expect(current().bellArmed, isFalse);
      expect(current().game?.isTimerStarted, isFalse);
      expect(notifier().isBellVisible, isFalse);
    });
  });

  group('NextQuestion', () {
    test('clears the current Bell answer/turn UI state', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      expect(notifier().bellPhase, BellPhase.answering);

      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 2,
        'text': 'q2',
        'textEn': 'q2',
        'type': 1,
        'answers': [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ],
      });

      expect(current().bellArmed, isFalse);
      expect(current().game?.currentQuestion?.id, 2);
      expect(current().game?.isTimerStarted, isFalse,
          reason: 'B-10 — the race countdown froze when ChangeTurn named a '
              'winner, and the new question keeps it locked until its own '
              'TimerUpdatedSeconds');
    });

    // B-8: repeated NextQuestion for the same question (progressive text
    // reveal) must not stop an already-running countdown.
    test('a same-question repeat does not reset the timer or answering',
        () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().answersUnlocked, isTrue);

      // Same id + questionNumber as the initial question (both id:1, no
      // questionNumber) — a progressive reveal of the same question's text.
      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 1,
        'text': 'q — more text revealed',
        'textEn': 'q — more text revealed',
        'type': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      });

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'same question — must not stop the running countdown');
      expect(current().answersUnlocked, isTrue,
          reason: 'same question — must not re-lock an already-open answer');
      expect(current().game?.currentQuestion?.text, 'q — more text revealed',
          reason: 'the question content itself still updates');
    });

    // B-9: the real device showed TimerUpdatedSeconds for a NEW question
    // arriving 5ms before that question's own NextQuestion. A running timer
    // is authoritative — the new question's content lands without killing it.
    test('a new question while the timer is running preserves it', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().answersUnlocked, isTrue);
      expect(current().bellArmed, isTrue);

      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 2,
        'text': 'q2',
        'textEn': 'q2',
        'type': 1,
        'answers': [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ],
      });

      expect(current().game?.currentQuestion?.id, 2,
          reason: 'the new question content is applied');
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'the already-running timer is authoritative');
      expect(current().answersUnlocked, isTrue);
      expect(current().bellArmed, isTrue, reason: 'unchanged');
    });

    test('a new question with no running timer still arrives locked',
        () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      // An authoritative resolution stops the timer first — the normal
      // ordering every round already follows.
      await emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 1},
      );
      expect(current().game?.isTimerStarted, isFalse);

      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 2,
        'text': 'q2',
        'textEn': 'q2',
        'type': 1,
        'answers': [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ],
      });

      expect(current().game?.isTimerStarted, isFalse,
          reason: 'a new question locks answering until its own TimeStarted');
      expect(current().answersUnlocked, isFalse);
    });
  });

  group('B-10 — ChangeTurn ends the race countdown', () {
    test('racing + ChangeTurn(me) freezes the race timer', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().game?.isTimerStarted, isTrue);

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );

      expect(current().game?.isTimerStarted, isFalse,
          reason: 'the race is over — the answering countdown starts from '
              'the next TimerUpdatedSeconds');
      expect(current().bellArmed, isFalse);
      expect(notifier().bellPhase, BellPhase.answering);
      expect(notifier().isBellVisible, isFalse);
    });

    test('racing + ChangeTurn(opponent) freezes it the same way', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );

      expect(current().game?.isTimerStarted, isFalse);
      expect(current().bellArmed, isFalse);
      expect(notifier().isBellVisible, isFalse);
    });

    test('an answering-phase ChangeTurn is a normal transition — no stop',
        () async {
      // The race already ended; a turn handoff mid-answering must not touch
      // whatever the timer state is.
      await armBell();
      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      // The answering countdown arrives from the server after the race.
      await emit(
        PlayGameHubEvents.timeStarted,
        null,
      );
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().bellArmed, isFalse,
          reason: 'a turn exists — TimeStarted does not re-arm');

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'not racing — the handoff leaves the timer alone');
    });
  });

  group('Restore', () {
    test('no turn → idle, no Bell', () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, GamePhase.bell);
      expect(notifier().bellPhase, BellPhase.idle);
      expect(notifier().isBellVisible, isFalse);
      expect(current().bellArmed, isFalse,
          reason: 'no running countdown in the snapshot — waits for '
              'TimeStarted');
    });

    test('an existing turn → answering, no Bell', () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(currentTurn: _opponentId),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, GamePhase.bell);
      expect(current().isOpponentTurn, isTrue);
      expect(notifier().bellPhase, BellPhase.answering);
      expect(notifier().isBellVisible, isFalse);
    });

    test('a routine GameUpdated mid-race does not disarm the Bell',
        () async {
      // Unlike GameRestore, GameUpdated is not a reconnect — it must not
      // reset a race already in progress.
      await armBell();
      expect(current().bellArmed, isTrue);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _bellGame(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().bellArmed, isTrue);
      expect(notifier().bellPhase, BellPhase.racing);
    });

    // B-10: the backend snapshot can restore straight into a live race —
    // no turn, running countdown — and the Bell must come back armed
    // without waiting for a TimeStarted the backend will not resend.
    test('no turn + running countdown → the race is restored armed',
        () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(isTimerStarted: true, currentTimerValue: 9.4628567),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, GamePhase.bell);
      expect(current().bellArmed, isTrue);
      expect(notifier().bellPhase, BellPhase.racing);
      expect(notifier().isBellVisible, isTrue);
      expect(notifier().canRingBell, isTrue);
    });

    test('a turn + running countdown → answering, Bell stays hidden',
        () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(
          currentTurn: _opponentId,
          isTimerStarted: true,
          currentTimerValue: 5,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().bellArmed, isFalse);
      expect(notifier().bellPhase, BellPhase.answering);
      expect(notifier().isBellVisible, isFalse);
    });

    test('no turn but the countdown is not running → still idle', () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(isTimerStarted: false, currentTimerValue: 9),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().bellArmed, isFalse);
      expect(notifier().bellPhase, BellPhase.idle);
      expect(notifier().isBellVisible, isFalse);
    });

    // B-11: an explicit currentTurn "" in a snapshot means "no player has
    // the turn" — it must CLEAR a turn held before the reconnect, not let
    // the stale one survive the merge and fake an answering phase.
    test('restore with an explicit empty turn clears a held turn → racing',
        () async {
      await enterBell(currentTurn: _opponentId);
      expect(notifier().bellPhase, BellPhase.answering);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(isTimerStarted: true, currentTimerValue: 9.4628567),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().isMyTurn, isFalse);
      expect(current().isOpponentTurn, isFalse);
      expect(current().bellArmed, isTrue);
      expect(notifier().bellPhase, BellPhase.racing);
      expect(notifier().isBellVisible, isTrue);
    });

    test('GameUpdated with an explicit empty turn ends answering', () async {
      await enterBell(currentTurn: _opponentId);
      expect(notifier().bellPhase, BellPhase.answering);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _bellGame(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().isMyTurn, isFalse);
      expect(current().isOpponentTurn, isFalse);
      expect(notifier().bellPhase, BellPhase.idle);
    });
  });

  group('unrelated events', () {
    test('an irrelevant shared-round event does not change Bell state',
        () async {
      await armBell();

      await emit(PlayGameHubEvents.questionOver, {'arg0': 'g1'});

      expect(current().bellArmed, isTrue,
          reason: 'QuestionOver is not one of the events Bell reacts to');
      expect(notifier().bellPhase, BellPhase.racing);
    });

    test('a completely unknown event name is ignored', () async {
      await armBell();

      await emit('SomeUnknownEvent', {'anything': true});

      expect(current().bellArmed, isTrue);
      expect(notifier().bellPhase, BellPhase.racing);
    });
  });

  // Bell runs two countdowns inside one question: the buzz race, then the
  // winner's answering phase. Both are driven by TimerUpdatedSeconds, and
  // answersUnlocked is one shared flag — so the race's own countdown opened
  // answering, and the ChangeTurn that ended the race carried that open lock
  // into the answering phase. It is harmless while racing (no turn, so
  // isMyTurn is false), and becomes visible the instant a winner is named.
  group('ending the race also closes answering', () {
    test('the race countdown opens answering but nobody may act yet',
        () async {
      await armBell();

      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );

      expect(current().answersUnlocked, isTrue,
          reason: 'TimerUpdatedSeconds is TimerUpdatedSeconds — unchanged');
      expect(current().isMyTurn, isFalse,
          reason: 'no turn while racing, so the open lock reaches nobody');
      expect(notifier().bellPhase, BellPhase.racing);
    });

    test('racing + ChangeTurn(me) closes answering', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().answersUnlocked, isTrue, reason: 'sanity');

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );

      expect(current().answersUnlocked, isFalse,
          reason: 'the winner waits for the answering countdown, not the '
              'race countdown that just ended');
      expect(current().isMyTurn, isTrue);
      expect(current().game?.isTimerStarted, isFalse,
          reason: 'the existing freeze is unchanged');
      expect(notifier().bellPhase, BellPhase.answering);
    });

    test('racing + ChangeTurn(opponent) closes it the same way', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );

      expect(current().answersUnlocked, isFalse);
      expect(current().game?.isTimerStarted, isFalse);
    });

    test('the answering countdown then opens it', () async {
      await armBell();
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      expect(current().answersUnlocked, isFalse);

      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([30, 'g1']),
      );

      expect(current().answersUnlocked, isTrue);
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().game?.currentTimerValue, 30);
    });

    test('a ChangeTurn with no race running leaves answering alone', () async {
      // Not racing: the turn already exists, so endsBellRace is false and
      // this branch must not touch the flag.
      await enterBell(currentTurn: _localId);
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().answersUnlocked, isTrue);

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );

      expect(current().answersUnlocked, isTrue,
          reason: 'a mid-answering handoff is a normal transition — it '
              'stops nothing and closes nothing');
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'and the existing no-stop behaviour is unchanged');
    });

    test('an armed race with no countdown yet still closes on ChangeTurn',
        () async {
      // The pre-existing ordering every other Bell test uses: ChangeTurn
      // before any TimerUpdatedSeconds. Already closed, and it stays closed.
      await armBell();

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );

      expect(current().answersUnlocked, isFalse);
      expect(current().game?.isTimerStarted, isFalse);
    });

    test('a non-Bell round is untouched by this', () async {
      // WDYK: endsBellRace is false by phase, so ChangeTurn keeps its
      // existing "leave answering as it is" behaviour.
      notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
        'id': 'g1',
        'status': 3,
        'type': 1,
        'groupId': 'grp',
        'currentTurn': '',
        'players': [
          {'id': _localId, 'playerName': 'me'},
          {'id': _opponentId, 'playerName': 'them'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().answersUnlocked, isTrue);

      await emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );

      expect(current().phase, GamePhase.wdyk);
      expect(current().answersUnlocked, isTrue,
          reason: 'WDYK is not in scope — ChangeTurn still leaves it alone');
    });
  });
}

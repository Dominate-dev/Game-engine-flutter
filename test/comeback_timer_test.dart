import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Comeback C-4.1 — startup/question/timer lifecycle.
//
// Real-device evidence: GameUpdated already carries the question/answers
// (currentTurn: ALLOW_ALL, isTimerStarted: false, currentTimerValue
// negative) before TimeStarted, and TimeStarted itself arrives before the
// first TimerUpdatedSeconds. NextQuestion then repeats for the same
// question with progressively more text. The timer must stay
// server-authoritative throughout: TimerUpdatedSeconds is the only thing
// that ever opens answering / starts the display; NextQuestion never owns
// it, matching the reference and the B-9 precedent already established for
// Bell — now extended to Comeback (game_controller.dart's
// _applyNextQuestion `timerAlreadyRunning` check).

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

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

Map<String, dynamic> _question({
  required int id,
  required String text,
  int questionNumber = 1,
  List<Map<String, dynamic>>? answers,
}) =>
    {
      'id': id,
      'questionNumber': questionNumber,
      'text': text,
      'textEn': text,
      'type': 1,
      'answers': answers ??
          [
            {'id': id * 10, 'text': 'a1', 'textEn': 'a1'},
          ],
    };

/// Matches the real-device GameUpdated: question already present,
/// isTimerStarted explicitly false, a negative currentTimerValue (the
/// server's "not applicable yet" sentinel), currentTurn ALLOW_ALL.
Map<String, dynamic> _comebackGameUpdated({
  int myTryCount = 0,
  int myMaxTryCount = 3,
  Map<String, dynamic>? question,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 4,
      'groupId': 'grp',
      'currentTurn': CreatedGame.allowAllTurn,
      'isTimerStarted': false,
      'currentTimerValue': -13.850,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': myTryCount,
          'maxMakeupTryCount': myMaxTryCount,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': myTryCount,
          'maxMakeupTryCount': myMaxTryCount,
        },
      ],
      'currentQuestion': question ?? _question(id: 1, text: 'q1'),
    };

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
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

  /// Comeback is round 4 — by the time it starts, a match is already in
  /// progress and `state.game` is already populated from an earlier round.
  /// Seeding this first is what makes the merge's negative-timer-value
  /// guard apply realistically to the GameUpdated that follows.
  Future<void> seedPriorRound() async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      {
        'id': 'g1',
        'status': 3,
        'type': 3,
        'groupId': 'grp',
        'currentTimerValue': 0,
      },
    );
    await Future<void>.delayed(Duration.zero);
  }

  /// `NextRoundStarted` is a sharedRoundEvent, not a sessionEvent — this is
  /// the actual dispatch path a live NextRoundStarted(4) takes.
  Future<void> nextRoundStarted() async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.nextRoundStarted,
      HubEventPayload.mapFromArgs([4, 'g1']),
    );
    await Future<void>.delayed(Duration.zero);
  }

  /// The real-device GameUpdated — routed through applySessionEvent, the
  /// same path a live GameUpdated actually takes (a sessionEvent, not a
  /// sharedRoundEvent).
  Future<void> gameUpdated({
    int myTryCount = 0,
    int myMaxTryCount = 3,
    Map<String, dynamic>? question,
  }) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameUpdated,
      _comebackGameUpdated(
        myTryCount: myTryCount,
        myMaxTryCount: myMaxTryCount,
        question: question,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> timeStarted() async {
    bindings.emit(PlayGameHubEvents.timeStarted, null);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> timerUpdatedSeconds(num seconds) async {
    bindings.emit(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([seconds, 'g1']),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> nextQuestion(Map<String, dynamic> question) async {
    bindings.emit(PlayGameHubEvents.nextQuestion, question);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> penalty(String playerId, int type) async {
    bindings.emit(
      PlayGameHubEvents.penalty,
      {'playerId': playerId, 'type': type},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> correctAnswer(String playerId) async {
    bindings.emit(
      PlayGameHubEvents.correctAnswer,
      {'arg0': 'answer', 'arg1': 'answer en', 'arg2': playerId},
    );
    await Future<void>.delayed(Duration.zero);
  }

  group('NextRoundStarted(4)', () {
    test('does not expose an answerable question before startup completes',
        () async {
      await seedPriorRound();
      await nextRoundStarted();

      expect(current().phase, GamePhase.comeBack);
      expect(current().game?.currentQuestion, isNull);
      expect(notifier().canSubmitComebackAnswer, isFalse,
          reason: 'no question, no roster yet — nothing to answer');
    });
  });

  group('GameUpdated carrying a question before TimeStarted', () {
    test('does not incorrectly start the timer', () async {
      await seedPriorRound();
      await nextRoundStarted();

      await gameUpdated();

      expect(current().game?.currentQuestion?.id, 1,
          reason: 'the question/answer area may appear this early — the '
              'reference places it before the start-time flow');
      expect(current().game?.isTimerStarted, isFalse,
          reason: 'GameUpdated reported isTimerStarted: false, honoured');
      expect(current().answersUnlocked, isFalse,
          reason: 'only TimerUpdatedSeconds may open this, for every round');
    });

    test('a negative currentTimerValue does not overwrite the display value',
        () async {
      await seedPriorRound();
      await nextRoundStarted();

      await gameUpdated();

      expect(current().game?.currentTimerValue, isNot(lessThan(0)),
          reason: 'the merge already ignores a negative sentinel — the '
              'previous (default) value survives, never a negative one');
    });
  });

  group('TimeStarted', () {
    test('does not fabricate or reset a timer value', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();

      await timeStarted();

      expect(current().game?.isTimerStarted, isTrue);
      expect(current().answersUnlocked, isFalse,
          reason: 'TimeStarted alone never opens answering — only '
              'TimerUpdatedSeconds does, for every round');
    });
  });

  group('the first TimerUpdatedSeconds', () {
    test('starts the authoritative countdown', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();

      await timerUpdatedSeconds(5.989);

      expect(current().game?.currentTimerValue, 5.989);
      expect(current().answersUnlocked, isTrue);
    });
  });

  group('repeated same-question NextQuestion', () {
    test('does not restart or reset the running timer', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();
      await timerUpdatedSeconds(5.989);
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().answersUnlocked, isTrue);

      await nextQuestion(_question(id: 1, text: 'q1 full text'));

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'a same-question NextQuestion must not stop the '
              'already-running countdown');
      expect(current().answersUnlocked, isTrue);
    });

    test(
        'progressive same-question repeats update the content without '
        'breaking the active timer', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();
      await timerUpdatedSeconds(10);

      for (final text in ['q', 'q1', 'q1 fu', 'q1 full text']) {
        await nextQuestion(_question(id: 1, text: text));
      }

      expect(current().game?.currentQuestion?.displayText(isArabic: false),
          'q1 full text',
          reason: 'content still updates on every repeat');
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'none of the repeats touched the running timer');
      expect(current().answersUnlocked, isTrue);
    });

    test(
        'a NextQuestion for a genuinely new question does not kill an '
        'already-running timer (B-9\'s scenario, now for Comeback)',
        () async {
      // TimerUpdatedSeconds can beat NextQuestion to the client for a
      // question that has not been announced by name yet — the running
      // timer is authoritative regardless, per the reference (NextQuestion
      // only (re)binds chips, it never owns the countdown).
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated(question: _question(id: 1, text: 'q1'));
      await timeStarted();
      await timerUpdatedSeconds(9);
      expect(current().game?.isTimerStarted, isTrue);

      await nextQuestion(_question(id: 2, text: 'q2'));

      expect(current().game?.currentQuestion?.id, 2);
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'the timer was already running — a new question arriving '
              'must not force it off');
      expect(current().answersUnlocked, isTrue);
    });
  });

  group('a genuine new question', () {
    test('reopens answering when attempts remain', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated(myTryCount: 3, myMaxTryCount: 3);
      await timeStarted();
      expect(notifier().canSubmitComebackAnswer, isFalse,
          reason: 'out of tries on the first question');

      await nextQuestion(_question(id: 2, text: 'q2'));
      // The server would send a fresh roster with reset tries alongside the
      // new question; simulate that with a GameUpdated.
      await gameUpdated(
        myTryCount: 0,
        myMaxTryCount: 3,
        question: _question(id: 2, text: 'q2'),
      );

      expect(notifier().canSubmitComebackAnswer, isTrue);
    });
  });

  // Confirmed contract: unlike every other round, neither CorrectAnswer nor
  // Penalty freeze Comeback's shared timer — the countdown keeps running
  // through both. The separate comebackAnswerLocked timeout-lock is
  // untouched by this: it still gates *answering*, just not the timer.
  group('CorrectAnswer/Penalty do not freeze the Comeback timer', () {
    test('TimerUpdatedSeconds(10) → Penalty → timer remains running',
        () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();
      await timerUpdatedSeconds(10);
      expect(current().game?.isTimerStarted, isTrue);

      await penalty(_localId, 2);

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'Penalty must not freeze the Comeback timer');
      expect(current().game?.currentTimerValue, 10,
          reason: 'Penalty must not reset the current timer value');
      expect(current().answersUnlocked, isTrue);
    });

    test('TimerUpdatedSeconds(10) → CorrectAnswer → timer remains running',
        () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();
      await timerUpdatedSeconds(10);
      expect(current().game?.isTimerStarted, isTrue);

      await correctAnswer(_localId);

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'CorrectAnswer must not freeze the Comeback timer');
      expect(current().game?.currentTimerValue, 10,
          reason: 'CorrectAnswer must not reset the current timer value');
      expect(current().answersUnlocked, isTrue);
    });

    test(
        'a later TimerUpdatedSeconds after Penalty continues the countdown '
        'normally', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();
      await timerUpdatedSeconds(10);
      await penalty(_localId, 2);

      await timerUpdatedSeconds(9);

      expect(current().game?.currentTimerValue, 9);
      expect(current().game?.isTimerStarted, isTrue);
    });

    test('a Penalty(type: 1) timeout also leaves the timer running',
        () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timeStarted();
      await timerUpdatedSeconds(10);

      await penalty(_localId, 1);

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'the timer stop and the answering lock are independent');
      expect(current().game?.currentTimerValue, 10);
    });

    test(
        'existing Comeback timeout (answer-lock) behavior is unchanged: '
        'Penalty(type: 1) still locks answering even though the timer '
        'keeps running', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated(myTryCount: 0, myMaxTryCount: 3);
      await timeStarted();
      await timerUpdatedSeconds(10);
      expect(notifier().canSubmitComebackAnswer, isTrue);

      await penalty(_localId, 1);

      expect(current().comebackAnswerLocked, isTrue,
          reason: 'the answer-attempt lock is untouched by this change');
      expect(notifier().canSubmitComebackAnswer, isFalse);
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'while the shared timer itself keeps running');
    });
  });

  group('both players regardless of currentTurn', () {
    test('ALLOW_ALL from GameUpdated never blocks my eligibility', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated(myTryCount: 0, myMaxTryCount: 3);

      expect(current().game?.currentTurn, CreatedGame.allowAllTurn);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });
  });

  // The same sequence with no TimeStarted in it — the shape the WDYK fix
  // targets. Comeback's own rule is the opposite of WDYK's: neither
  // CorrectAnswer nor Penalty freezes its shared countdown, and that is
  // decided by _eventStopsTimer, which did not change. These pin that the
  // flag TimerUpdatedSeconds now reports does not turn either event into a
  // freeze here. Breaker is confirmed identical and shares the same branch.
  group('no TimeStarted in the sequence changes nothing for Comeback', () {
    test('TimerUpdatedSeconds alone reports the countdown running', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();

      await timerUpdatedSeconds(10);

      expect(current().game?.isTimerStarted, isTrue);
      expect(current().game?.currentTimerValue, 10);
      expect(current().answersUnlocked, isTrue);
    });

    test('CorrectAnswer still does not freeze it', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timerUpdatedSeconds(10);

      await correctAnswer(_localId);

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'Comeback resolutions are not terminal — unchanged');
      expect(current().game?.currentTimerValue, 10);
      expect(current().answersUnlocked, isTrue);
    });

    test('Penalty(type: 2) still does not freeze it', () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timerUpdatedSeconds(10);

      await penalty(_localId, 2);

      expect(current().game?.isTimerStarted, isTrue);
      expect(current().game?.currentTimerValue, 10);
    });

    test('Penalty(type: 1) still locks answering and leaves it running',
        () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated(myTryCount: 0, myMaxTryCount: 3);
      await timerUpdatedSeconds(10);

      await penalty(_localId, 1);

      expect(current().comebackAnswerLocked, isTrue);
      expect(current().game?.isTimerStarted, isTrue);
    });

    test('a running countdown still survives the next NextQuestion',
        () async {
      await seedPriorRound();
      await nextRoundStarted();
      await gameUpdated();
      await timerUpdatedSeconds(10);

      await nextQuestion(_question(id: 2, text: 'q2'));

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'a running timer is authoritative on this round — the '
              'preserveTimer rule in _applyNextQuestion is unchanged');
      expect(current().game?.currentTimerValue, 10);
    });
  });
}

import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-6 — GameRestore.
//
// The metadata carries phase, currentBid, currentScore, wrongScore and
// latestBidder. It carries no goal, so that is not reconstructed:
// AuctionAnswerPhaseScoreUpdate stays its only source and remains
// authoritative for the scores. A restore never starts or resets the
// countdown (A-5).

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

Map<String, dynamic> _restorePayload({
  int type = 2,
  int? phase,
  int currentBid = 0,
  int currentScore = 0,
  String? latestBidder,
  String currentTurn = _localId,
  bool? isTimerStarted,
  double? currentTimerValue,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      if (isTimerStarted != null) 'isTimerStarted': isTimerStarted,
      if (currentTimerValue != null) 'currentTimerValue': currentTimerValue,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 1,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
      'currentQuestion': {
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'maxCorrectAnswersCount': 23,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
      if (phase != null)
        'auctionGameMetadata': {
          'phase': phase,
          'currentScore': currentScore,
          'currentBid': currentBid,
          'latestBidder': latestBidder,
          'answerTimeout': 8,
        },
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

  Future<void> restore(Map<String, dynamic> payload) async {
    notifier().applySessionEvent(PlayGameHubEvents.gameRestore, payload);
    await Future<void>.delayed(Duration.zero);
  }

  group('BIDDING restore', () {
    test('phase 1 lands on the auction screen in the bidding phase', () async {
      await restore(_restorePayload(phase: 1));

      expect(current().phase, GamePhase.auction);
      expect(current().auctionPhase, AuctionPhase.bidding);
    });

    test('the standing bid comes back', () async {
      await restore(_restorePayload(phase: 1, currentBid: 6));

      expect(current().currentBid, 6);
      expect(notifier().auctionMinBid, 7, reason: 'the picker floor follows');
    });

    test('no bid yet restores as no bid', () async {
      await restore(_restorePayload(phase: 1, currentBid: 0));

      expect(current().currentBid, isNull);
      expect(notifier().auctionMinBid, 1);
      expect(notifier().canTakeTurn, isFalse,
          reason: 'Take Turn needs a standing bid');
    });

    test('my own standing bid leaves me unable to raise', () async {
      await restore(
        _restorePayload(phase: 1, currentBid: 4, latestBidder: _localId),
      );

      expect(current().isBiding, isFalse);
      expect(notifier().canBid, isFalse);
      expect(notifier().canTakeTurn, isTrue, reason: 'a bid stands');
    });

    test('the opponent standing bid leaves me able to raise', () async {
      await restore(
        _restorePayload(phase: 1, currentBid: 4, latestBidder: _opponentId),
      );

      expect(current().isBiding, isTrue);
      expect(notifier().canBid, isTrue);
    });

    test('an unseated latestBidder changes nothing', () async {
      await restore(
        _restorePayload(phase: 1, currentBid: 4, latestBidder: '999'),
      );

      expect(current().isBiding, isTrue, reason: 'left at its default');
      expect(current().currentBid, 4, reason: 'the bid still restores');
    });

    test('a missing latestBidder changes nothing', () async {
      await restore(_restorePayload(phase: 1, currentBid: 4));

      expect(current().isBiding, isTrue);
      expect(current().currentBid, 4);
    });

    test('the turn still comes from currentTurn', () async {
      await restore(
        _restorePayload(phase: 1, currentBid: 4, currentTurn: _opponentId),
      );

      expect(current().isMyTurn, isFalse);
      expect(notifier().canBid, isFalse, reason: 'not my turn');
      expect(notifier().canTakeTurn, isFalse);
    });
  });

  group('ANSWERING restore', () {
    test('phase 2 restores the answering phase and the score', () async {
      await restore(
        _restorePayload(phase: 2, currentBid: 5, currentScore: 3),
      );

      expect(current().phase, GamePhase.auction);
      expect(current().auctionPhase, AuctionPhase.answering);
      expect(current().currentScore, 3);
    });

    test('the last bidder comes back as the answering player', () async {
      await restore(
        _restorePayload(phase: 2, currentBid: 5, latestBidder: _localId),
      );

      expect(current().answeringPlayerId, _localId);
      expect(notifier().isAuctionAnswerer, isTrue);
    });

    test('an opponent answering restore leaves me watching', () async {
      await restore(
        _restorePayload(phase: 2, currentBid: 5, latestBidder: _opponentId),
      );

      expect(current().answeringPlayerId, _opponentId);
      expect(notifier().isAuctionAnswerer, isFalse);
      expect(await notifier().submitAuctionAnswer(10), isFalse);
    });

    test('an unseated latestBidder restores no answering player', () async {
      await restore(
        _restorePayload(phase: 2, currentBid: 5, latestBidder: '999'),
      );

      expect(current().answeringPlayerId, isNull);
      expect(notifier().isAuctionAnswerer, isFalse,
          reason: 'no side may be guessed');
    });

    test('a live answering player is never overwritten by a restore',
        () async {
      await restore(_restorePayload(phase: 2, currentBid: 5));
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _opponentId, 'bidValue': 5},
      );
      await Future<void>.delayed(Duration.zero);
      expect(current().answeringPlayerId, _opponentId);

      // A later restore names a different last bidder.
      await restore(
        _restorePayload(phase: 2, currentBid: 7, latestBidder: _localId),
      );

      expect(current().answeringPlayerId, _opponentId,
          reason: 'AuctionAnswerPhaseStarted stays authoritative');
    });

    test('the A-3 attempt guard survives a restore', () async {
      await restore(
        _restorePayload(phase: 2, currentBid: 5, latestBidder: _localId),
      );
      expect(notifier().canSubmitAuctionAnswer, isTrue);

      // The roster now says the allowance is spent.
      notifier().applySessionEvent(PlayGameHubEvents.gameUpdated, {
        ..._restorePayload(phase: 2, currentBid: 5, latestBidder: _localId),
        'players': [
          {
            'id': _localId,
            'playerName': 'me',
            'makeupTryCount': 3,
            'maxMakeupTryCount': 3,
          },
          {'id': _opponentId, 'playerName': 'them'},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifier().canSubmitAuctionAnswer, isFalse);
    });

    test('a metadata wrongScore is parsed and kept', () async {
      // The shape the runtime log shows in the answer phase.
      await restore({
        ..._restorePayload(phase: 2, currentBid: 2, latestBidder: _localId),
        'auctionGameMetadata': {
          'phase': 2,
          'currentBid': 2,
          'currentScore': 0,
          'wrongScore': 1,
          'latestBidder': _localId,
          'answerTimeout': 8,
        },
      });

      expect(
        current().game?.auctionGameMetadata?.wrongScore,
        1,
        reason: 'parsed off the metadata',
      );
      expect(current().wrongScore, 1, reason: 'and applied to the session');
    });

    test('metadata without wrongScore keeps the score-update value', () async {
      await restore(_restorePayload(phase: 2, currentBid: 2));
      bindings.emit(PlayGameHubEvents.auctionAnswerPhaseScoreUpdate, {
        'playerId': _localId,
        'wrongScore': 2,
      });
      await Future<void>.delayed(Duration.zero);
      expect(current().wrongScore, 2);

      // A later payload that omits it must not reset the count to zero.
      await restore(_restorePayload(phase: 2, currentBid: 2));

      expect(current().game?.auctionGameMetadata?.wrongScore, isNull);
      expect(current().wrongScore, 2, reason: 'absent means unchanged');
    });

    test('a later score update still overrides the metadata value', () async {
      await restore({
        ..._restorePayload(phase: 2, currentBid: 2),
        'auctionGameMetadata': {
          'phase': 2,
          'currentBid': 2,
          'currentScore': 0,
          'wrongScore': 1,
          'answerTimeout': 8,
        },
      });
      expect(current().wrongScore, 1);

      bindings.emit(PlayGameHubEvents.auctionAnswerPhaseScoreUpdate, {
        'playerId': _localId,
        'wrongScore': 3,
      });
      await Future<void>.delayed(Duration.zero);

      expect(current().wrongScore, 3,
          reason: 'AuctionAnswerPhaseScoreUpdate stays authoritative');
    });

    test('the goal is not reconstructed', () async {
      await restore(
        _restorePayload(phase: 2, currentBid: 5, latestBidder: _localId),
      );

      expect(current().goalScore, isNull,
          reason: 'the metadata carries no goal');
      expect(current().wrongScore, isNull,
          reason: 'this payload carries no wrong count');

      // The server supplies both on the next score update.
      bindings.emit(PlayGameHubEvents.auctionAnswerPhaseScoreUpdate, {
        'playerId': _localId,
        'currentScore': 3,
        'goalScore': 5,
        'wrongScore': 1,
      });
      await Future<void>.delayed(Duration.zero);

      expect(current().goalScore, 5);
      expect(current().wrongScore, 1);
    });
  });

  group('the restore never touches the countdown', () {
    test('it does not start the timer', () async {
      await restore(_restorePayload(phase: 2, currentBid: 5));

      expect(current().game?.isTimerStarted, isNull);
      expect(current().lastEventName, PlayGameHubEvents.gameRestore);
    });

    test('a running timer keeps its value and is not restarted', () async {
      // A session already in the round, mid-countdown, that then restores.
      await restore(_restorePayload(phase: 2, currentBid: 5));
      bindings.emit(
        PlayGameHubEvents.timeStarted,
        {'arg0': '', 'arg1': 'g1'},
      );
      bindings.emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        {'arg0': 12, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(current().game?.currentTimerValue, 12);

      await restore(_restorePayload(phase: 2, currentBid: 5));

      expect(current().game?.currentTimerValue, 12,
          reason: 'the restore carried no seconds of its own');
      expect(current().lastEventName, isNot(
        PlayGameHubEvents.timerUpdatedSeconds,
      ));
    });

    test('a restored isTimerStarted does not make the display run', () async {
      await restore(
        _restorePayload(
          phase: 2,
          currentBid: 5,
          isTimerStarted: true,
          currentTimerValue: 9,
        ),
      );

      // The flag is merged, but TimerUpdatedSeconds is still the only start
      // signal the display listens to.
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().lastEventName, PlayGameHubEvents.gameRestore);
    });
  });

  group('unsupported and missing values', () {
    test('an unknown phase leaves the recorded phase alone', () async {
      await restore(_restorePayload(phase: 1));
      expect(current().auctionPhase, AuctionPhase.bidding);

      await restore(_restorePayload(phase: 99, currentBid: 4));

      expect(current().auctionPhase, AuctionPhase.bidding,
          reason: 'an unrecognised phase is not guessed');
      expect(current().currentBid, 4, reason: 'the rest still restores');
    });

    test('a phase of 0 is treated as unknown', () async {
      await restore(_restorePayload(phase: 0));

      expect(current().auctionPhase, isNull);
    });

    test('a payload with no auction metadata leaves auction state alone',
        () async {
      await restore(_restorePayload(phase: 2, currentBid: 5));
      final before = current();

      await restore(_restorePayload());

      expect(current().auctionPhase, before.auctionPhase);
      expect(current().currentBid, before.currentBid);
      expect(current().currentScore, before.currentScore);
    });
  });

  group('non-auction restore is unchanged', () {
    test('a WDYK restore routes by type and touches no auction field',
        () async {
      await restore(_restorePayload(type: 1));

      expect(current().phase, GamePhase.wdyk);
      expect(current().auctionPhase, isNull);
      expect(current().currentBid, isNull);
      expect(current().answeringPlayerId, isNull);
      expect(current().auctionResult, AuctionResult.none);
    });

    test('a WDYK restore still seats both players', () async {
      await restore(_restorePayload(type: 1));

      expect(current().me?.id, _localId);
      expect(current().opponent?.id, _opponentId);
    });

    test('an ended game still ends', () async {
      await restore({..._restorePayload(phase: 2), 'status': 4});

      expect(current().result, isNotNull);
    });
  });
}

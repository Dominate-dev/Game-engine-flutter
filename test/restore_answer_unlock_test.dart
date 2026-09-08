import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// BUG-03 + BUG-04 (final audit) regression tests.
//
// Confirmed runtime contract: a GameRestore carrying isTimerStarted == true
// and currentTimerValue > 0 means the server already has an active
// answering countdown — an eligible player must be able to answer
// immediately, without waiting for a fresh TimerUpdatedSeconds.
//
// GameSessionState.answersUnlocked is the shared "is a countdown open"
// flag every round screen reads alongside its OWN eligibility check:
//   WDYK / Bell:  session.isMyTurn && session.answersUnlocked
//     (wdyk_round_screen.dart:53, bell_round_screen.dart:51)
//   Auction:      notifier.isAuctionAnswerer && session.answersUnlocked
//     (auction_round_screen.dart:275)
// This file proves answersUnlocked is now correctly re-derived from the
// restore snapshot for WDYK/Auction/Bell, while eligibility (isMyTurn /
// isAuctionAnswerer / the wrong-limit gate) is entirely untouched — so an
// eligible player can answer immediately, but an ineligible one still
// cannot, purely because their own eligibility check still fails.
//
// Comeback/Breaker are deliberately out of scope: canSubmitComebackAnswer
// never reads answersUnlocked at all (confirmed by inspection — it checks
// only phase, comebackAnswerLocked and the tries count), so this fix does
// not touch their behavior; one test below pins that down explicitly.

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

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

Map<String, dynamic> _gameJson({
  required int type,
  String? currentTurn,
  bool? isTimerStarted,
  double? currentTimerValue,
  Map<String, dynamic>? auctionGameMetadata,
  List<Map<String, dynamic>>? players,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      if (currentTurn != null) 'currentTurn': currentTurn,
      if (isTimerStarted != null) 'isTimerStarted': isTimerStarted,
      if (currentTimerValue != null) 'currentTimerValue': currentTimerValue,
      'players': players ??
          [
            {
              'id': _localId,
              'playerName': 'me',
              'makeupTryCount': 0,
              'maxMakeupTryCount': 3,
            },
            {
              'id': _opponentId,
              'playerName': 'them',
              'makeupTryCount': 0,
              'maxMakeupTryCount': 3,
            },
          ],
      if (auctionGameMetadata != null)
        'auctionGameMetadata': auctionGameMetadata,
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late _FakeHubBindings bindings;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
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

  Future<void> restore(Map<String, dynamic> payload) async {
    notifier().applySessionEvent(PlayGameHubEvents.gameRestore, payload);
    await Future<void>.delayed(Duration.zero);
  }

  for (final round in [
    (name: 'WDYK', type: 1, phase: GamePhase.wdyk),
    (name: 'Bell', type: 3, phase: GamePhase.bell),
  ]) {
    group('${round.name} restore-mid-answering (BUG-03/BUG-04)', () {
      test(
        'an active countdown (isTimerStarted + currentTimerValue>0) '
        'restores answering as open',
        () async {
          await restore(_gameJson(
            type: round.type,
            currentTurn: _localId,
            isTimerStarted: true,
            currentTimerValue: 4.2326147,
          ));

          expect(current().phase, round.phase);
          expect(current().game?.isTimerStarted, isTrue);
          expect(
            current().answersUnlocked,
            isTrue,
            reason: 'the confirmed runtime contract — answering was already '
                'open on the server',
          );
        },
      );

      test('an eligible player (my turn) can answer immediately after '
          'restore — no TimerUpdatedSeconds required', () async {
        await restore(_gameJson(
          type: round.type,
          currentTurn: _localId,
          isTimerStarted: true,
          currentTimerValue: 4.2326147,
        ));

        // The exact gate the round screen reads.
        expect(current().isMyTurn, isTrue);
        expect(current().answersUnlocked, isTrue);
        expect(
          current().lastEventName,
          PlayGameHubEvents.gameRestore,
          reason: 'unlocked by the restore itself, not a follow-up event',
        );
      });

      test(
        'an ineligible player (not my turn) remains unable to answer, even '
        'though the countdown is genuinely active',
        () async {
          await restore(_gameJson(
            type: round.type,
            currentTurn: _opponentId,
            isTimerStarted: true,
            currentTimerValue: 4.2326147,
          ));

          expect(
            current().answersUnlocked,
            isTrue,
            reason: 'the countdown itself is active for both players',
          );
          expect(
            current().isMyTurn,
            isFalse,
            reason: 'eligibility is a separate check, untouched by this fix',
          );
        },
      );

      test('a non-running restore (isTimerStarted=false) does not unlock '
          'answering', () async {
        await restore(_gameJson(
          type: round.type,
          currentTurn: _localId,
          isTimerStarted: false,
          currentTimerValue: 9,
        ));

        expect(current().answersUnlocked, isFalse);
      });

      test('an expired restore (currentTimerValue<=0) does not unlock '
          'answering', () async {
        await restore(_gameJson(
          type: round.type,
          currentTurn: _localId,
          isTimerStarted: true,
          currentTimerValue: 0,
        ));

        expect(current().answersUnlocked, isFalse);
      });

      test(
        'the next TimerUpdatedSeconds still updates the countdown normally',
        () async {
          await restore(_gameJson(
            type: round.type,
            currentTurn: _localId,
            isTimerStarted: true,
            currentTimerValue: 4.2326147,
          ));
          expect(current().answersUnlocked, isTrue, reason: 'sanity');

          bindings.emit(
            PlayGameHubEvents.timerUpdatedSeconds,
            {'arg0': 12.0, 'arg1': 'g1'},
          );
          await Future<void>.delayed(Duration.zero);

          expect(current().game?.currentTimerValue, 12);
          expect(current().answersUnlocked, isTrue,
              reason: 'a live event with time left keeps it open');

          bindings.emit(
            PlayGameHubEvents.timerUpdatedSeconds,
            {'arg0': 0.0, 'arg1': 'g1'},
          );
          await Future<void>.delayed(Duration.zero);

          expect(current().answersUnlocked, isFalse,
              reason: 'a live event reaching zero still closes it, as before');
        },
      );

      test('existing restore behavior remains intact — roster and phase '
          'still restore normally', () async {
        await restore(_gameJson(
          type: round.type,
          currentTurn: _localId,
          isTimerStarted: true,
          currentTimerValue: 4.2326147,
        ));

        expect(current().me?.id, _localId);
        expect(current().opponent?.id, _opponentId);
      });
    });
  }

  group('Auction restore-mid-answering (BUG-03/BUG-04)', () {
    Map<String, dynamic> auctionRestore({
      required String? latestBidder,
      bool? isTimerStarted,
      double? currentTimerValue,
      int makeupTryCount = 0,
    }) =>
        _gameJson(
          type: 2,
          isTimerStarted: isTimerStarted,
          currentTimerValue: currentTimerValue,
          players: [
            {
              'id': _localId,
              'playerName': 'me',
              'makeupTryCount': makeupTryCount,
              'maxMakeupTryCount': 3,
            },
            {
              'id': _opponentId,
              'playerName': 'them',
              'makeupTryCount': 0,
              'maxMakeupTryCount': 3,
            },
          ],
          auctionGameMetadata: {
            'phase': 2,
            'currentBid': 5,
            'currentScore': 0,
            'latestBidder': latestBidder,
            'answerTimeout': 8,
          },
        );

    test(
      'an active countdown unlocks answering immediately for the answerer',
      () async {
        await restore(auctionRestore(
          latestBidder: _localId,
          isTimerStarted: true,
          currentTimerValue: 4.2326147,
        ));

        expect(current().phase, GamePhase.auction);
        expect(current().answersUnlocked, isTrue);
        expect(notifier().isAuctionAnswerer, isTrue);
        expect(
          notifier().canSubmitAuctionAnswer,
          isTrue,
          reason: 'the existing answerer/attempt-limit gate still applies '
              'and passes here',
        );
      },
    );

    test('the watching (non-answerer) opponent remains unable to answer',
        () async {
      await restore(auctionRestore(
        latestBidder: _opponentId,
        isTimerStarted: true,
        currentTimerValue: 4.2326147,
      ));

      expect(current().answersUnlocked, isTrue,
          reason: 'the countdown is genuinely active');
      expect(
        notifier().isAuctionAnswerer,
        isFalse,
        reason: 'answerer identity is untouched by this fix',
      );
    });

    test(
      'the existing attempt/wrong-limit gate still blocks an exhausted '
      'answerer even though answersUnlocked is true',
      () async {
        await restore(auctionRestore(
          latestBidder: _localId,
          isTimerStarted: true,
          currentTimerValue: 4.2326147,
          makeupTryCount: 3, // == maxMakeupTryCount
        ));

        expect(current().answersUnlocked, isTrue);
        expect(notifier().isAuctionAnswerer, isTrue);
        expect(
          notifier().canSubmitAuctionAnswer,
          isFalse,
          reason: 'answersUnlocked alone must not bypass the attempt-limit '
              'gate',
        );
      },
    );

    test('a non-running restore does not unlock Auction answering',
        () async {
      await restore(auctionRestore(
        latestBidder: _localId,
        isTimerStarted: false,
        currentTimerValue: 9,
      ));

      expect(current().answersUnlocked, isFalse);
    });

    test('the next TimerUpdatedSeconds still updates the countdown normally',
        () async {
      await restore(auctionRestore(
        latestBidder: _localId,
        isTimerStarted: true,
        currentTimerValue: 4.2326147,
      ));

      bindings.emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        {'arg0': 6.0, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().game?.currentTimerValue, 6);
      expect(current().answersUnlocked, isTrue);
    });

    test(
      'existing restore behavior remains intact — a bidding-phase restore '
      'with no timer fields is unaffected',
      () async {
        await restore(_gameJson(
          type: 2,
          currentTurn: _localId,
          auctionGameMetadata: {
            'phase': 1,
            'currentBid': 4,
            'answerTimeout': 8,
          },
        ));

        expect(current().auctionPhase, AuctionPhase.bidding);
        expect(
          current().answersUnlocked,
          isFalse,
          reason: 'no timer fields on this payload — nothing to unlock',
        );
      },
    );
  });

  group(
    'Comeback/Breaker are left out of this fix — their own restore/'
    'eligibility handling is untouched',
    () {
      test(
        'a restore with an active countdown does not set answersUnlocked '
        'for Comeback',
        () async {
          await restore(_gameJson(
            type: 4,
            currentTurn: '',
            isTimerStarted: true,
            currentTimerValue: 4.2326147,
          ));

          expect(current().phase, GamePhase.comeBack);
          expect(
            current().answersUnlocked,
            isFalse,
            reason: 'Comeback/Breaker use canSubmitComebackAnswer, which '
                'never reads answersUnlocked — nothing here should change '
                'for them',
          );
        },
      );

      test(
        'a restore with an active countdown does not set answersUnlocked '
        'for Breaker',
        () async {
          await restore(_gameJson(
            type: 5,
            currentTurn: '',
            isTimerStarted: true,
            currentTimerValue: 4.2326147,
          ));

          expect(current().phase, GamePhase.breaker);
          expect(current().answersUnlocked, isFalse);
        },
      );
    },
  );
}

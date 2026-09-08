import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FinishRoundScreen reads no Auction/Comeback/Bell state (only
// playGameStringsProvider), and round-dialog handlers are phase-gated, so
// stale round fields can't reach the UI during finishRound. The one gap
// found: showPhase's trailing _applyAuctionMetadata could reapply stale
// auctionGameMetadata on RoundFinished/ShowResults — fixed by clearing it,
// mirroring NextRoundStarted's existing reset.

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

class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(const StickerPage(items: [], pageIndex: 0, pageSize: 20));

  @override
  Future<Result<bool>> payStickerGroup(int id) async => Result.success(true);
}

class _FakeNetworkInfo implements NetworkInfo {
  @override
  bool get isOnline => true;
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();
  @override
  void dispose() {}
}

class _FakeAudioService extends AudioService {
  @override
  Future<void> start(
    String asset, {
    AudioSourceType type = AudioSourceType.sfx,
    String? package,
    bool? loop,
    double? volume,
  }) async {}

  @override
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {}

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

Map<String, dynamic> _comebackGame({
  int type = 4,
  bool isTimerStarted = true,
  double currentTimerValue = 30,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': '',
      'isTimerStarted': isTimerStarted,
      'currentTimerValue': currentTimerValue,
      'players': [
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
      'currentQuestion': {
        'id': 1,
        'text': 'q1',
        'textEn': 'q1',
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  group('R-09 — controller-level lifecycle (Comeback)', () {
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

    test(
      'comebackAnswerLocked survives RoundFinished into GamePhase.'
      'finishRound unchanged, then resets once NextRoundStarted fires',
      () async {
        notifier().applySessionEvent(
          PlayGameHubEvents.gameStarted,
          _comebackGame(),
        );
        await Future<void>.delayed(Duration.zero);
        expect(current().phase, GamePhase.comeBack, reason: 'sanity');

        bindings.emit(
          PlayGameHubEvents.penalty,
          {'playerId': _localId, 'type': 1},
        );
        await Future<void>.delayed(Duration.zero);
        expect(current().comebackAnswerLocked, isTrue, reason: 'sanity');

        bindings.emit(PlayGameHubEvents.roundFinished, null);
        await Future<void>.delayed(Duration.zero);

        final duringFinishRound = current();
        expect(duringFinishRound.phase, GamePhase.finishRound);
        expect(
          duringFinishRound.comebackAnswerLocked,
          isTrue,
          reason: 'intentionally retained — nothing resets it on the '
              'finishRound transition itself',
        );

        bindings.emit(
          PlayGameHubEvents.nextRoundStarted,
          HubEventPayload.mapFromArgs([5, 'g1']), // Breaker
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          current().comebackAnswerLocked,
          isFalse,
          reason: 'NextRoundStarted is the reset boundary',
        );
      },
    );
  });

  group('R-09 — real widget/event flow: FinishRoundScreen', () {
    Future<ProviderContainer> pumpFinishRound(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      final bindings = _FakeHubBindings(signalR);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(signalR),
          playGameHubBindingsProvider.overrideWithValue(bindings),
          stickersRepositoryProvider
              .overrideWithValue(_FakeStickersRepository()),
          audioServiceProvider.overrideWithValue(_FakeAudioService()),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
          hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
          signalRStatusProvider.overrideWith(
            (ref) => Stream<SignalRStatus>.value(SignalRStatus.connected),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      await tester.pump();

      final notifier = container.read(gameControllerProvider.notifier);
      // Dirty Comeback state, exactly as the controller-level test above.
      notifier.applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _comebackGame(),
      );
      await tester.pump();
      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 1},
      );
      await tester.pump();
      expect(
        container.read(gameControllerProvider).comebackAnswerLocked,
        isTrue,
        reason: 'sanity',
      );
      // This same Penalty also reaches GameControllerScreen's own direct
      // listener (onEventReceived -> onPenalty -> onComebackPenalty), which
      // shows a timeout RoundLottieDialog while phase was still comeBack.
      // Let its own dismiss timer (_comebackShortDialogMs, round_lottie_
      // dialog.dart's internal Timer) run out before continuing, or it
      // would still be open — unrelated to anything RoundFinished/
      // finishRound does — and confuse the "no dialog" assertions below. A
      // plain pump() first lets the dialog actually build and start its
      // Timer before the clock is advanced past it.
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      bindings.emit(PlayGameHubEvents.roundFinished, null);
      await tester.pump();
      await tester.pump();

      return container;
    }

    testWidgets(
      'renders normally with dirtied Auction/Comeback state, consuming '
      'none of it — FinishRoundScreen reads only playGameStringsProvider',
      (tester) async {
        final container = await pumpFinishRound(tester);
        final strings = container.read(playGameStringsProvider);

        expect(find.byType(FinishRoundScreen), findsOneWidget);
        expect(find.text(strings.readyGameTitle), findsOneWidget);
        expect(
          container.read(gameControllerProvider).comebackAnswerLocked,
          isTrue,
          reason: 'still there, unread by anything — sanity that this test '
              'is actually exercising the dirtied state, not a reset one',
        );
      },
    );

    testWidgets(
      'a stray CorrectAnswer/Penalty arriving while phase == finishRound '
      'resurrects no dialog — every round-specific dialog handler is '
      'explicitly phase-gated and finishRound matches none of them',
      (tester) async {
        final container = await pumpFinishRound(tester);
        final bindings =
            container.read(playGameHubBindingsProvider) as _FakeHubBindings;

        bindings.emit(
          PlayGameHubEvents.correctAnswer,
          {'arg2': _opponentId},
        );
        await tester.pump();
        bindings.emit(
          PlayGameHubEvents.penalty,
          {'playerId': _localId, 'type': 2},
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byType(RoundLottieDialog),
          findsNothing,
          reason: 'onCorrectAnswer/onPenalty both return immediately for a '
              'phase that is none of wdyk/auction/bell/comeBack/breaker',
        );
        expect(find.byType(FinishRoundScreen), findsOneWidget,
            reason: 'still on the same screen — no stray navigation either');
      },
    );
  });
}

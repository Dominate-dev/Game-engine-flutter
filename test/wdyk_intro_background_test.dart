import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The WDYK round intro is scheduled from a post-frame callback, and a
// backgrounded app produces no frames. Checking the lifecycle inside that
// callback would therefore let the intro play on resume; these pin the check
// to the moment the phase change is observed.

const _localId = '47';

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

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

/// The screen loads the sticker catalog on first frame; this keeps that off
/// the network without touching the code under test.
class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(
        const StickerPage(items: [], pageIndex: 0, pageSize: 20),
      );

  @override
  Future<Result<bool>> payStickerGroup(int id) async => Result.success(true);
}

/// The real NetworkInfo subscribes to connectivity plugins in its constructor,
/// leaving timers pending after the tree is torn down. Implemented, not
/// extended, so that constructor never runs.
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

/// Silences playback: the intro dialog starts a sound, and startRunningMusic
/// runs right after it.
class _FakeAudioService extends AudioService {
  /// showRoundIntro starts the looping music straight after the overlay, so
  /// this records whether that method ran at all — the difference between the
  /// intro being skipped and merely being suppressed once it had started.
  final musicStarted = <String>[];

  /// Only the loop showRoundIntro starts — the waiting screen plays its own.
  List<String> get introMusic =>
      musicStarted.where((a) => a == AppSounds.musicRunning).toList();

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
  }) async {
    musicStarted.add(asset);
  }

  @override
  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {}
}

Map<String, dynamic> _gameJson({required int type}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': '211403', 'playerName': 'them'},
      ],
    };

void main() {
  late ProviderContainer container;
  late _FakeAudioService audio;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> pumpHost(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
    audio = _FakeAudioService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
        stickersRepositoryProvider
            .overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(audio),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        // BaseState listens to both; the real ones start plugin timers that
        // outlive the widget tree. Neither is under test here.
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
  }

  Future<void> setLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> enterWdyk(WidgetTester tester) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _gameJson(type: 1),
    );
    await tester.pump();
    await tester.pump();
  }

  group('the WDYK round intro respects the lifecycle', () {
    testWidgets('it appears when the round is entered in the foreground',
        (tester) async {
      await pumpHost(tester);
      await enterWdyk(tester);

      expect(container.read(gameControllerProvider).phase, GamePhase.wdyk);
      expect(find.byType(RoundLottieDialog), findsOneWidget);

      // Let the dialog retire; the music starts once it closes.
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();

      expect(audio.introMusic, hasLength(1),
          reason: 'showRoundIntro ran to completion');
    });

    testWidgets('it is suppressed when the round is entered while paused',
        (tester) async {
      await pumpHost(tester);
      await setLifecycle(tester, AppLifecycleState.paused);

      await enterWdyk(tester);
      // Long enough that a scheduled intro would have run and started its
      // music by now.
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();

      expect(container.read(gameControllerProvider).phase, GamePhase.wdyk,
          reason: 'the round still starts — only the overlay is skipped');
      expect(find.byType(RoundLottieDialog), findsNothing);
      // The dialog alone cannot tell the two designs apart: showRoundIntro
      // suppresses it internally too. Music only starts if that method ran,
      // so an empty list is what proves it was never scheduled.
      expect(audio.introMusic, isEmpty,
          reason: 'the intro was not scheduled at all');
    });

    testWidgets('it is not replayed when the app returns to the foreground',
        (tester) async {
      await pumpHost(tester);
      await setLifecycle(tester, AppLifecycleState.paused);
      await enterWdyk(tester);
      expect(find.byType(RoundLottieDialog), findsNothing);

      await setLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2000));

      expect(find.byType(RoundLottieDialog), findsNothing,
          reason: 'the deferred frame must not resurrect the intro');
      expect(audio.introMusic, isEmpty,
          reason: 'nothing was pending to replay');
    });

    testWidgets('an inactive app suppresses it too', (tester) async {
      await pumpHost(tester);
      await setLifecycle(tester, AppLifecycleState.inactive);

      await enterWdyk(tester);

      expect(find.byType(RoundLottieDialog), findsNothing);
      expect(audio.introMusic, isEmpty);
    });

    testWidgets('a later round entered in the foreground still shows it',
        (tester) async {
      await pumpHost(tester);
      await setLifecycle(tester, AppLifecycleState.paused);
      await enterWdyk(tester);
      expect(find.byType(RoundLottieDialog), findsNothing);

      await setLifecycle(tester, AppLifecycleState.resumed);
      // A fresh transition into the round, now that the app is back.
      notifier().showPhase(GamePhase.lobbyPlay);
      await tester.pump();
      await enterWdyk(tester);

      expect(find.byType(RoundLottieDialog), findsOneWidget,
          reason: 'suppression applies to that transition, not to the screen');

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
    });

    testWidgets('a lifecycle change does not disturb gameplay state',
        (tester) async {
      await pumpHost(tester);
      await setLifecycle(tester, AppLifecycleState.paused);
      await enterWdyk(tester);

      final before = container.read(gameControllerProvider);
      await setLifecycle(tester, AppLifecycleState.resumed);
      final after = container.read(gameControllerProvider);

      expect(after.phase, before.phase);
      expect(after.game?.currentTurn, before.game?.currentTurn);
      expect(after.game?.id, before.game?.id);
      expect(after.me?.id, before.me?.id);
    });
  });
}

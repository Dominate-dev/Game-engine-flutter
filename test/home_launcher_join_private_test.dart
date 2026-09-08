import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/features/home/presentation/pages/home_launcher_page.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The debug launcher's join-by-code entry.
//
// It goes through PlayGame.openPrivateGameByCode — the same call
// PlayGameEngineHost.joinPrivateGame makes, which is what a native host
// reaches through GameEngine.joinPrivateGame. The launcher has no engine
// instance of its own, so this is the same flow one layer down, exactly as
// its Play / PvP / Profile buttons already work.

const _gameCode = '4821';

class _FakeSignalRService extends SignalRService {
  @override
  bool get isConnected => true;

  @override
  bool get hasLiveConnection => true;

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
  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {}
}

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
}

void main() {
  late ProviderContainer container;

  Future<void> newContainer() async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
        stickersRepositoryProvider
            .overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(_FakeAudioService()),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        signalRStatusProvider.overrideWith(
          (ref) => Stream<SignalRStatus>.value(SignalRStatus.connected),
        ),
        gameRepositoryProvider.overrideWithValue(_FakeGameRepository()),
      ],
    );
    addTearDown(container.dispose);
    AppStrings.setLanguage(AppLanguage.english);
  }

  Future<void> mountLauncher(WidgetTester tester) async {
    // The launcher is one long column; at the default 800x600 surface the
    // join button sits below the fold and a tap would never reach it.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeLauncherPage()),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Finder joinButton() => find.text('Join private game');

  setUp(() async => newContainer());

  testWidgets('the field and the button are on the page', (tester) async {
    await mountLauncher(tester);

    expect(joinButton(), findsOneWidget);
    expect(
      find.widgetWithText(AppTextField, 'Game code'),
      findsOneWidget,
      reason: 'the hint labels the code field',
    );

    await unmount(tester);
  });

  testWidgets('an empty code opens nothing', (tester) async {
    await mountLauncher(tester);

    await tester.tap(joinButton());
    await tester.pump();

    expect(
      find.byType(GameControllerScreen),
      findsNothing,
      reason: 'validation refuses before any navigation happens',
    );
    expect(find.byType(HomeLauncherPage), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a whitespace-only code is empty too', (tester) async {
    await mountLauncher(tester);

    await tester.enterText(find.byType(AppTextField).first, '   ');
    await tester.pump();
    await tester.tap(joinButton());
    await tester.pump();

    expect(find.byType(GameControllerScreen), findsNothing);

    await unmount(tester);
  });

  testWidgets('a code opens the private game with exactly that code',
      (tester) async {
    await mountLauncher(tester);

    await tester.enterText(find.byType(AppTextField).first, _gameCode);
    await tester.pump();
    await tester.tap(joinButton());
    await tester.pump();
    await tester.pump();

    final screen = tester.widget<GameControllerScreen>(
      find.byType(GameControllerScreen),
    );
    expect(screen.privateGameCode, _gameCode);
    expect(
      screen.privateInterestIds,
      isNull,
      reason: 'joining is not creating — the two entries stay separate',
    );

    await unmount(tester);
  });

  testWidgets('a padded code is trimmed before it is sent', (tester) async {
    await mountLauncher(tester);

    await tester.enterText(find.byType(AppTextField).first, '  $_gameCode  ');
    await tester.pump();
    await tester.tap(joinButton());
    await tester.pump();
    await tester.pump();

    final screen = tester.widget<GameControllerScreen>(
      find.byType(GameControllerScreen),
    );
    expect(screen.privateGameCode, _gameCode);

    await unmount(tester);
  });
}

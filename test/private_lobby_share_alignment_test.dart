import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The private lobby's share icon is anchored to the PHYSICAL right edge in
// both languages. It must not mirror with the screen's Directionality, which
// the lobby sets from the app language (rtl for Arabic, ltr for English) and
// which every other element in the lobby still follows.
//
// Position is asserted from the painted geometry — the icon's own rect
// against the screen's centre — not from the alignment constant, so the test
// fails if any future layout change moves it regardless of how.

const _localId = '47';
const _gameCode = '4821';
const _serverUrl = 'https://example.test/g/4821';

class _FakeSignalRService extends SignalRService {
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
      Result.success(_serverUrl);
}

Map<String, dynamic> _privateGame() => {
      'id': 'private-1',
      'status': 1,
      'mode': 4,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'gameCode': _gameCode,
      'currentTimerValue': 0,
      'players': [
        {
          'id': _localId,
          'playerName': 'host',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
    };

void main() {
  late ProviderContainer container;

  Future<void> pumpLobby(WidgetTester tester, String language) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': language,
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GameControllerScreen(privateInterestIds: [4]),
        ),
      ),
    );
    await tester.pump();
    container
        .read(gameControllerProvider.notifier)
        .applySessionEvent(PlayGameHubEvents.gameCreated, _privateGame());
    await tester.pump();
    await tester.pump();
  }

  /// The share icon — the only replay-icon image in the lobby.
  Finder shareIcon() => find.byWidgetPredicate(
        (widget) =>
            widget is AppImageView &&
            widget.assetPath == AppAssets.replayIcon,
      );

  void expectAnchoredRight(WidgetTester tester) {
    expect(shareIcon(), findsOneWidget);
    final icon = tester.getRect(shareIcon());
    final screen = tester.getRect(find.byType(MaterialApp));

    expect(
      icon.center.dx,
      greaterThan(screen.center.dx),
      reason: 'the share icon must sit in the right half of the screen',
    );
    // And specifically hugging that edge, not merely right of centre.
    expect(
      screen.right - icon.right,
      lessThan(icon.width),
      reason: 'anchored to the right edge',
    );
  }

  group('the share icon is anchored to the physical right edge', () {
    testWidgets('in Arabic (RTL)', (tester) async {
      await pumpLobby(tester, AppLanguage.arabic);

      expectAnchoredRight(tester);
    });

    testWidgets('in English (LTR)', (tester) async {
      await pumpLobby(tester, AppLanguage.english);

      expectAnchoredRight(tester);
    });

    // Relational, within a single pump: the icon sits to the right of the
    // code in BOTH languages. A directional alignment would put it left of
    // the code in one of them — that is exactly the mirroring being ruled
    // out, and it is caught without pumping two trees in one test.
    testWidgets('it sits to the right of the code in Arabic', (tester) async {
      await pumpLobby(tester, AppLanguage.arabic);

      expect(
        tester.getRect(shareIcon()).left,
        greaterThan(tester.getRect(find.text('1')).right),
      );
    });

    testWidgets('it sits to the right of the code in English', (tester) async {
      await pumpLobby(tester, AppLanguage.english);

      expect(
        tester.getRect(shareIcon()).left,
        greaterThan(tester.getRect(find.text('1')).right),
      );
    });
  });

  group('the surrounding content keeps its own direction', () {
    testWidgets('Arabic content is still laid out RTL', (tester) async {
      await pumpLobby(tester, AppLanguage.arabic);

      final strings = PlayGameStrings.forLanguage(AppLanguage.arabic);
      expect(
        Directionality.of(tester.element(find.text(strings.iAmReady))),
        TextDirection.rtl,
      );
    });

    testWidgets('English content is still laid out LTR', (tester) async {
      await pumpLobby(tester, AppLanguage.english);

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(
        Directionality.of(tester.element(find.text(strings.iAmReady))),
        TextDirection.ltr,
      );
    });

    testWidgets('the code digits keep their own LTR run in Arabic',
        (tester) async {
      await pumpLobby(tester, AppLanguage.arabic);

      // '4821' must read left-to-right in both languages, unchanged by this
      // fix: the first digit stays left of the last.
      final first = tester.getRect(find.text('4'));
      final last = tester.getRect(find.text('1'));
      expect(first.center.dx, lessThan(last.center.dx));
    });

    testWidgets('the code digits read the same way in English',
        (tester) async {
      await pumpLobby(tester, AppLanguage.english);

      final first = tester.getRect(find.text('4'));
      final last = tester.getRect(find.text('1'));
      expect(first.center.dx, lessThan(last.center.dx));
    });
  });
}

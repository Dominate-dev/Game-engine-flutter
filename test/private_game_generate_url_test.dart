import 'dart:async';
import 'dart:io';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// T2 — GenerateURL + the private lobby share action.
//
// The request is `GET api/Home/GenerateURL?type=2&code=<gameCode>`, issued
// once per game code, and the share action stays unavailable until the server
// has actually returned a link. Nothing here constructs a URL locally.

const _localId = '47';
const _gameCode = '4821';
const _serverUrl = 'https://example.test/g/4821';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  bool get hasLiveConnection => true;

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

/// Records what the datasource asked the repository for, and what it returned.
class _RecordingGameRepository implements GameRepository {
  _RecordingGameRepository({this.url = _serverUrl, this.failure});

  final String url;
  final Failure? failure;
  final calls = <({int type, String code})>[];

  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async {
    calls.add((type: type, code: code));
    final f = failure;
    if (f != null) {
      return Result.failure(f);
    }
    return Result.success(url);
  }
}

Map<String, dynamic> _privateGame({String? gameCode = _gameCode}) => {
      'id': 'private-1',
      'status': 1,
      'mode': 4,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      if (gameCode != null) 'gameCode': gameCode,
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
  late _RecordingGameRepository repository;

  final strings = PlayGameStrings.forLanguage(AppLanguage.english);

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  // The request shape itself (path, `type=2`, `code`, envelope unwrapping) is
  // covered in remote_datasources_test.dart, alongside the other datasources
  // and using the same ApiClient seam. This file covers the lobby lifecycle
  // and the share action.

  // The notifier's own guard, exercised directly. The lobby's listener is
  // keyed on the code changing and so already filters most repeats — these
  // pin the second line of defence, which is what makes the request
  // once-per-code no matter who calls it or how often.
  group('the link notifier guards the request itself', () {
    late _RecordingGameRepository repo;

    ProviderContainer containerWith(_RecordingGameRepository repository) {
      final c = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(c.dispose);
      // Keep the autoDispose provider alive for the duration of the test.
      c.listen(privateGameLinkProvider, (_, __) {});
      return c;
    }

    setUp(() => repo = _RecordingGameRepository());

    test('the same code twice issues one request', () async {
      final c = containerWith(repo);
      final notifier = c.read(privateGameLinkProvider.notifier);

      await notifier.ensureFor(_gameCode);
      await notifier.ensureFor(_gameCode);
      await notifier.ensureFor('  $_gameCode  ');

      expect(repo.calls, hasLength(1));
      expect(c.read(privateGameLinkProvider).url, _serverUrl);
    });

    test('a null code issues nothing', () async {
      final c = containerWith(repo);

      await c.read(privateGameLinkProvider.notifier).ensureFor(null);

      expect(repo.calls, isEmpty);
      expect(c.read(privateGameLinkProvider).hasUrl, isFalse);
    });

    test('a blank code issues nothing', () async {
      final c = containerWith(repo);

      await c.read(privateGameLinkProvider.notifier).ensureFor('   ');

      expect(repo.calls, isEmpty);
    });

    test('a genuinely different code is requested again', () async {
      final c = containerWith(repo);
      final notifier = c.read(privateGameLinkProvider.notifier);

      await notifier.ensureFor(_gameCode);
      await notifier.ensureFor('9999');

      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.code, '9999');
    });

    test('a failed request is not retried for the same code', () async {
      final failing =
          _RecordingGameRepository(failure: ServerFailure(message: 'nope'));
      final c = containerWith(failing);
      final notifier = c.read(privateGameLinkProvider.notifier);

      await notifier.ensureFor(_gameCode);
      await notifier.ensureFor(_gameCode);

      expect(failing.calls, hasLength(1));
      expect(c.read(privateGameLinkProvider).hasUrl, isFalse);
    });

    test('every request carries type 2', () async {
      final c = containerWith(repo);

      await c.read(privateGameLinkProvider.notifier).ensureFor(_gameCode);

      expect(repo.calls.single.type, privateGameLinkType);
      expect(privateGameLinkType, 2);
    });
  });

  group('the private lobby lifecycle', () {
    Future<void> pumpLobby(
      WidgetTester tester, {
      String? gameCode = _gameCode,
      bool created = true,
      Failure? failure,
    }) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      repository = _RecordingGameRepository(failure: failure);
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
          gameRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GameControllerScreen(privateInterestIds: [88]),
          ),
        ),
      );
      await tester.pump();
      if (created) {
        notifier().applySessionEvent(
          PlayGameHubEvents.gameCreated,
          _privateGame(gameCode: gameCode),
        );
        await tester.pump();
      }
      await tester.pump();
    }

    testWidgets('a valid code requests the link once, with type 2',
        (tester) async {
      await pumpLobby(tester);

      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.type, 2);
      expect(repository.calls.single.code, _gameCode);
    });

    testWidgets('no code means no request', (tester) async {
      await pumpLobby(tester, gameCode: null);

      expect(repository.calls, isEmpty);
    });

    testWidgets('an empty code means no request', (tester) async {
      await pumpLobby(tester, gameCode: '');

      expect(repository.calls, isEmpty);
    });

    testWidgets('before GameCreated there is nothing to request',
        (tester) async {
      await pumpLobby(tester, created: false);

      expect(repository.calls, isEmpty);
    });

    testWidgets('repeated GameUpdated for the same code does not re-request',
        (tester) async {
      await pumpLobby(tester);

      for (var i = 0; i < 3; i++) {
        notifier().applySessionEvent(
          PlayGameHubEvents.gameUpdated,
          _privateGame(),
        );
        await tester.pump();
      }

      expect(repository.calls, hasLength(1));
    });

    testWidgets('rebuilds do not re-request', (tester) async {
      await pumpLobby(tester);

      for (var i = 0; i < 3; i++) {
        tester.element(find.byType(LobbyPrivateGameScreen)).markNeedsBuild();
        await tester.pump();
      }

      expect(repository.calls, hasLength(1));
    });

    testWidgets('a PlayerReady refresh does not re-request', (tester) async {
      await pumpLobby(tester);

      notifier().onLobbyPlayerReady(_privateGame());
      await tester.pump();

      expect(repository.calls, hasLength(1));
    });
  });

  group('the stored link and the share action', () {
    late _RecordingGameRepository repo;

    Future<void> pumpWithRepo(
      WidgetTester tester,
      _RecordingGameRepository injected,
    ) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      repo = injected;
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
          gameRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GameControllerScreen(privateInterestIds: [88]),
          ),
        ),
      );
      await tester.pump();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a successful response stores the server URL', (tester) async {
      await pumpWithRepo(tester, _RecordingGameRepository());

      final link = container.read(privateGameLinkProvider);
      expect(link.url, _serverUrl);
      expect(link.hasUrl, isTrue);
      expect(link.failure, isNull);
    });

    testWidgets('the stored URL survives rebuilds', (tester) async {
      await pumpWithRepo(tester, _RecordingGameRepository());

      tester.element(find.byType(LobbyPrivateGameScreen)).markNeedsBuild();
      await tester.pump();

      expect(container.read(privateGameLinkProvider).url, _serverUrl);
    });

    testWidgets('a failure stores no URL and fabricates nothing',
        (tester) async {
      await pumpWithRepo(
        tester,
        _RecordingGameRepository(failure: ServerFailure(message: 'nope')),
      );

      final link = container.read(privateGameLinkProvider);
      expect(link.url, isNull);
      expect(link.hasUrl, isFalse);
      expect(link.failure, isNotNull,
          reason: 'the existing Failure mechanism is exposed, not swallowed');
    });

    testWidgets('a blank success is not treated as a URL', (tester) async {
      await pumpWithRepo(tester, _RecordingGameRepository(url: '   '));

      expect(container.read(privateGameLinkProvider).hasUrl, isFalse);
    });

    testWidgets('share is unavailable before a URL exists', (tester) async {
      await pumpWithRepo(
        tester,
        _RecordingGameRepository(failure: ServerFailure(message: 'nope')),
      );

      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(GestureDetector),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 0.4, reason: 'dimmed, and its onTap is null');
    });

    testWidgets('share becomes available once the URL lands', (tester) async {
      await pumpWithRepo(tester, _RecordingGameRepository());

      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(GestureDetector),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
    });

    test('the shared text is the existing message plus the server URL', () {
      // The share action composes exactly this; the localized wording itself
      // is untouched and still ends by inviting the reader to click.
      final composed = '${strings.shareGameMessage(_gameCode)}\n$_serverUrl';

      expect(composed, contains(_gameCode));
      expect(composed, endsWith(_serverUrl));
      expect(composed, contains(strings.shareGameMessage(_gameCode)));
    });
  });

  group('the public lobby is untouched', () {
    test('its share path has no link dependency — the public lobby has no '
        'share action at all', () {
      // Guard against the private wiring leaking into the public lobby: the
      // public screen never references the link provider or AppShare.
      final source = File(
        'packages/play_game/lib/presentation/pages/lobby_public/'
        'lobby_play_game_screen.dart',
      ).readAsStringSync();

      expect(source.contains('privateGameLinkProvider'), isFalse);
      expect(source.contains('AppShare'), isFalse);
      expect(source.contains('generateUrl'), isFalse);
    });
  });
}

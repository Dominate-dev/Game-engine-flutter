import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:play_game/presentation/widgets/lobby/lobby_player_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The private lobby shows no player data until its own game exists.
//
// The failure this pins is stale session state, not the old mock: the lobby
// reads session.me / session.opponent, and those stay populated from whatever
// game came before until GameCreated replaces them. Entering the private
// lobby on a controller that still holds a previous game rendered that game's
// players — names AND profile images — in the new lobby.

const _localId = '47';
const _opponentId = '211403';
const _gameCode = '4821';

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
      Result.success('https://example.test/g/$code');
}

/// The game a previous session left behind — seated players, with names and
/// profile images, exactly what leaked into the new lobby.
Map<String, dynamic> _previousGame() => {
      'id': 'old-public',
      'status': 2,
      'mode': 1,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': [
        {
          'id': _localId,
          'playerName': 'StaleMe',
          'profileImageUrl': 'http://example.test/me.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'StaleFoe',
          'profileImageUrl': 'http://example.test/foe.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
    };

Map<String, dynamic> _privateGame({bool withOpponent = false}) => {
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
          'playerName': 'RealHost',
          'profileImageUrl': 'http://example.test/host.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        if (withOpponent)
          {
            'id': _opponentId,
            'playerName': 'RealGuest',
            'makeupTryCount': 0,
            'maxMakeupTryCount': 3,
          },
      ],
    };

void main() {
  late ProviderContainer container;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> newContainer(String language) async {
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
  }

  Future<void> mountPrivateEntry(
    WidgetTester tester, {
    String language = AppLanguage.english,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GameControllerScreen(privateInterestIds: [88]),
        ),
      ),
    );
  }

  /// Seeds the session with a previous game, as a controller that was not
  /// disposed between entries would still hold.
  void seedPreviousGame() {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameUpdated,
      _previousGame(),
    );
  }

  /// Unmounts and drains, so a controller created before the tree (to seed
  /// a previous session) leaves no pending work at the end of the test.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  List<LobbyPlayerCard> cards(WidgetTester tester) =>
      tester.widgetList<LobbyPlayerCard>(find.byType(LobbyPlayerCard)).toList();

  void expectNoPlayerDataRendered(WidgetTester tester) {
    final rendered = cards(tester);
    expect(rendered, hasLength(2), reason: 'both seats still lay out');

    for (final card in rendered) {
      expect(card.showAvatar, isFalse, reason: 'no avatar is shown');
      expect(card.imageUrl, isNull, reason: 'no profile image is supplied');
      expect(card.emoteUrl, isNull);
    }
    // The local seat carries no name at all; the opponent seat keeps the
    // established waiting copy.
    expect(rendered.first.name, isEmpty);

    // Nothing from the previous game reached the screen.
    expect(find.text('StaleMe'), findsNothing);
    expect(find.text('StaleFoe'), findsNothing);
    // Nor the long-deleted mock.
    expect(find.text('Hassan Hasanat'), findsNothing);
    expect(find.text('Mahmoud Salih'), findsNothing);
  }

  group('before CreatedGame — a fresh session', () {
    testWidgets('renders no avatar and no name', (tester) async {
      await newContainer(AppLanguage.english);
      await mountPrivateEntry(tester);
      await tester.pump();

      expectNoPlayerDataRendered(tester);
      await drain(tester);
    });

    testWidgets('keeps the waiting-for-player seat', (tester) async {
      await newContainer(AppLanguage.english);
      await mountPrivateEntry(tester);
      await tester.pump();

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(find.text(strings.waitingForPlayer), findsOneWidget);
    });
  });

  group('before CreatedGame — a stale session from a previous game', () {
    testWidgets('does not render the previous game\'s players on the very '
        'first frame', (tester) async {
      await newContainer(AppLanguage.english);
      seedPreviousGame();
      await mountPrivateEntry(tester);
      // No pump() past the first build: this is the frame that used to show
      // the previous game's avatars.

      expectNoPlayerDataRendered(tester);
      await drain(tester);
    });

    testWidgets('still renders nothing once the entry has run', (tester) async {
      await newContainer(AppLanguage.english);
      seedPreviousGame();
      await mountPrivateEntry(tester);
      await tester.pump();
      await tester.pump();

      expectNoPlayerDataRendered(tester);
      await drain(tester);
    });

    testWidgets('the stale game itself is dropped from the session',
        (tester) async {
      await newContainer(AppLanguage.english);
      seedPreviousGame();
      await mountPrivateEntry(tester);
      await tester.pump();

      final session = container.read(gameControllerProvider);
      expect(session.game, isNull);
      expect(session.me, isNull);
      expect(session.opponent, isNull);
      expect(session.phase, GamePhase.lobbyPrivate);
      await drain(tester);
    });

    testWidgets('creation still happens after a previous private entry',
        (tester) async {
      await newContainer(AppLanguage.english);
      // Simulate a controller that already created a private game once.
      await notifier().createPrivateGame(const [88]);
      await mountPrivateEntry(tester);
      await tester.pump();

      final session = container.read(gameControllerProvider);
      expect(session.phase, GamePhase.lobbyPrivate);
      expect(session.game, isNull, reason: 'the entry reset the session');
      await drain(tester);
    });
  });

  group('after CreatedGame', () {
    testWidgets('the real host is rendered with their own data',
        (tester) async {
      await newContainer(AppLanguage.english);
      seedPreviousGame();
      await mountPrivateEntry(tester);
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(),
      );
      await tester.pump();

      expect(find.text('RealHost'), findsOneWidget);
      expect(cards(tester).first.showAvatar, isTrue);
      expect(cards(tester).first.imageUrl, 'http://example.test/host.png');
      expect(find.text('StaleMe'), findsNothing);
      await drain(tester);
    });

    testWidgets('the opponent seat stays empty until an opponent exists',
        (tester) async {
      await newContainer(AppLanguage.english);
      await mountPrivateEntry(tester);
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(),
      );
      await tester.pump();

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(cards(tester).last.showAvatar, isFalse);
      expect(cards(tester).last.imageUrl, isNull);
      expect(find.text(strings.waitingForPlayer), findsOneWidget);
    });

    testWidgets('the opponent appears once they join', (tester) async {
      await newContainer(AppLanguage.english);
      await mountPrivateEntry(tester);
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(withOpponent: true),
      );
      await tester.pump();

      expect(find.text('RealGuest'), findsOneWidget);
      expect(cards(tester).last.showAvatar, isTrue);
    });
  });

  group('the approved share-icon placement still holds', () {
    Finder shareIcon() => find.byWidgetPredicate(
          (widget) =>
              widget is AppImageView &&
              widget.assetPath == AppAssets.replayIcon,
        );

    Future<void> pumpCreated(WidgetTester tester, String language) async {
      await newContainer(language);
      await mountPrivateEntry(tester, language: language);
      await tester.pump();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('right edge in Arabic', (tester) async {
      await pumpCreated(tester, AppLanguage.arabic);

      final icon = tester.getRect(shareIcon());
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(icon.center.dx, greaterThan(screen.center.dx));
      expect(screen.right - icon.right, lessThan(icon.width));
    });

    testWidgets('right edge in English', (tester) async {
      await pumpCreated(tester, AppLanguage.english);

      final icon = tester.getRect(shareIcon());
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(icon.center.dx, greaterThan(screen.center.dx));
      expect(screen.right - icon.right, lessThan(icon.width));
    });
  });

  group('the public lobby is unaffected', () {
    testWidgets('a public game still seats its players normally',
        (tester) async {
      await newContainer(AppLanguage.english);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _previousGame(),
      );
      await tester.pump();

      expect(container.read(gameControllerProvider).phase, GamePhase.lobbyPlay);
      expect(find.text('StaleMe'), findsOneWidget);
      expect(find.text('StaleFoe'), findsOneWidget);
      expect(cards(tester).first.showAvatar, isTrue,
          reason: 'the public lobby has no empty-state gate');
    });
  });
}

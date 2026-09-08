import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/domain/game_mode.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:play_game/presentation/widgets/lobby/lobby_player_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The private lobby carries no fallback avatar before its game exists.
//
// Inspected, not assumed. The default avatar comes from exactly one place on
// this screen's render path:
//   LobbyPrivateGameScreen -> LobbyPlayersRow -> LobbyPlayerCard, whose avatar
//   slot is AppImageView(assetPath: AppAssets.defaultAvatar) — the asset
//   'assets/images/ic_avatars_default.png' in coreapp.
//
// The screen already gates player data correctly: `started` (phase ==
// lobbyPrivate) nulls out user/opponent until the entry has replaced the
// session, and it passes showUserAvatar/showOpponentAvatar as `player !=
// null`. What that gate could not reach was the card itself: the avatar sat
// under Visibility(maintainSize: true), which suppresses *painting* only. The
// AppImageView and its AssetImage were still constructed and decoded for a
// seat with no player — verified directly, the hidden card built one
// Image(AssetImage("packages/coreapp/assets/images/ic_avatars_default.png")).
//
// The card now builds the avatar only when there is a player, and reserves
// the same avatarSize box otherwise, so the layout the Visibility used to
// hold is unchanged.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  bool get hasLiveConnection => true;

  @override
  bool get isConnected => true;

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

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
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

Map<String, dynamic> _privateGame({bool withOpponent = false}) => {
      'id': 'private-1',
      'status': 1,
      'mode': GameMode.privatePvp,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'gameCode': '4821',
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
            'profileImageUrl': 'http://example.test/guest.png',
            'makeupTryCount': 0,
            'maxMakeupTryCount': 3,
          },
      ],
    };

/// A previous, unrelated game left seated on a reused controller.
Map<String, dynamic> _previousGame() => {
      'id': 'stale-1',
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
          'profileImageUrl': 'http://example.test/stale-me.png',
        },
        {
          'id': _opponentId,
          'playerName': 'StaleFoe',
          'profileImageUrl': 'http://example.test/stale-foe.png',
        },
      ],
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> newContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
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

  Future<void> mountPrivateEntry(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GameControllerScreen(privateInterestIds: [88]),
        ),
      ),
    );
  }

  Future<void> mountPublicEntry(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameControllerScreen()),
      ),
    );
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  /// Every avatar slot currently falling back to the default asset, painted
  /// or not.
  ///
  /// The `imageUrl` half matters: every avatar slot passes
  /// `assetPath: AppAssets.defaultAvatar` as its backup, so a seated player
  /// with a real profile image builds one too. Only a slot with no usable
  /// URL actually *renders* the default avatar, and that is what must not
  /// exist for an empty seat.
  ///
  /// `skipOffstage: false` on purpose: the point of this file is that the
  /// asset must not be *built*, so a finder that quietly ignored hidden
  /// widgets would pass either way.
  Finder fallbackAvatars() => find.byWidgetPredicate(
        (w) =>
            w is AppImageView &&
            w.assetPath == AppAssets.defaultAvatar &&
            AppUrl.httpOrNull(w.imageUrl) == null,
        skipOffstage: false,
      );

  /// The decoded asset itself, one level below AppImageView.
  Finder fallbackAvatarImages() => find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage)
                .assetName
                .contains('ic_avatars_default'),
        skipOffstage: false,
      );

  List<LobbyPlayerCard> cards(WidgetTester tester) =>
      tester.widgetList<LobbyPlayerCard>(find.byType(LobbyPlayerCard)).toList();

  Finder shareIcon() => find.byWidgetPredicate(
        (w) => w is AppImageView && w.assetPath == AppAssets.replayIcon,
      );

  double shareOpacity(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.ancestor(of: shareIcon(), matching: find.byType(Opacity)),
      )
      .first
      .opacity;

  VoidCallback? shareTap(WidgetTester tester) => tester
      .widgetList<GestureDetector>(
        find.ancestor(of: shareIcon(), matching: find.byType(GestureDetector)),
      )
      .first
      .onTap;

  group('1. the initial private lobby holds no player data at all', () {
    testWidgets('no fallback avatar is built for either empty seat',
        (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      expect(
        fallbackAvatars(),
        findsNothing,
        reason: 'the default-avatar AppImageView must not exist for a seat '
            'with no player — Visibility only stopped it painting',
      );
      expect(
        fallbackAvatarImages(),
        findsNothing,
        reason: 'and no AssetImage for it is decoded either',
      );
      await drain(tester);
    });

    testWidgets('not even on the very first frame, before the entry runs',
        (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      // No pump() past the first build.

      expect(fallbackAvatars(), findsNothing);
      expect(fallbackAvatarImages(), findsNothing);
      await drain(tester);
    });

    testWidgets('no player name is rendered', (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      expect(cards(tester), hasLength(2), reason: 'both seats still lay out');
      expect(cards(tester).first.name, isEmpty);
      expect(cards(tester).first.imageUrl, isNull);
      expect(cards(tester).first.emoteUrl, isNull);
      await drain(tester);
    });

    testWidgets('no stale player data from a previous game', (tester) async {
      await newContainer();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _previousGame(),
      );
      await mountPrivateEntry(tester);
      await tester.pump();

      expect(find.text('StaleMe'), findsNothing);
      expect(find.text('StaleFoe'), findsNothing);
      expect(fallbackAvatars(), findsNothing);
      for (final card in cards(tester)) {
        expect(card.imageUrl, isNull);
      }
      await drain(tester);
    });

    testWidgets('no mock or placeholder player data', (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      expect(find.text('Hassan Hasanat'), findsNothing);
      expect(find.text('Mahmoud Salih'), findsNothing);
      expect(find.text('2580'), findsNothing);
      await drain(tester);
    });

    testWidgets('the layout still holds both seats and the reserved avatar '
        'space, so nothing collapses', (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      expect(cards(tester), hasLength(2));
      final reserved = find.descendant(
        of: find.byType(LobbyPlayerCard),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SizedBox &&
              w.width == LobbyPlayerCard.avatarSize &&
              w.height == LobbyPlayerCard.avatarSize,
        ),
      );
      expect(
        reserved,
        findsNWidgets(2),
        reason: 'each empty seat reserves exactly the avatar box the hidden '
            'Visibility used to hold',
      );
      await drain(tester);
    });

    testWidgets('share stays disabled until the code and link both exist',
        (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      expect(shareOpacity(tester), 0.4,
          reason: 'dimmed — nothing to share yet');
      expect(shareTap(tester), isNull, reason: 'and inert');
      await drain(tester);
    });
  });

  group('2. real host data appears after GameCreated', () {
    testWidgets('the host name and their own profile image render',
        (tester) async {
      await newContainer();
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
      await drain(tester);
    });

    testWidgets('the host seat now builds a real avatar view', (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(),
      );
      await tester.pump();

      final hostAvatar = find.byWidgetPredicate(
        (w) =>
            w is AppImageView && w.imageUrl == 'http://example.test/host.png',
      );
      expect(hostAvatar, findsOneWidget);
      await drain(tester);
    });

    testWidgets('the real game code renders and share becomes available',
        (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(),
      );
      await tester.pumpAndSettle();

      for (final digit in ['4', '8', '2', '1']) {
        expect(find.text(digit), findsOneWidget);
      }
      expect(shareOpacity(tester), 1,
          reason: 'code and link have both arrived');
      expect(shareTap(tester), isNotNull);
      await drain(tester);
    });
  });

  group('3. no opponent is shown until one actually exists', () {
    testWidgets('after GameCreated with only the host, the opponent seat '
        'stays empty and builds no fallback avatar', (tester) async {
      await newContainer();
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
      expect(
        fallbackAvatars(),
        findsNothing,
        reason: 'the host has a real image and the empty seat builds none',
      );
      expect(find.text('RealGuest'), findsNothing);
      await drain(tester);
    });

    testWidgets('the opponent renders once they actually join',
        (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameCreated,
        _privateGame(withOpponent: true),
      );
      await tester.pump();

      expect(find.text('RealGuest'), findsOneWidget);
      expect(cards(tester).last.showAvatar, isTrue);
      expect(cards(tester).last.imageUrl, 'http://example.test/guest.png');
      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(find.text(strings.waitingForPlayer), findsNothing);
      await drain(tester);
    });
  });

  group('4. the public lobby is unchanged', () {
    Future<void> joinPublicLobby({bool withOpponent = true}) async {
      notifier().applySessionEvent(PlayGameHubEvents.gameJoined, {
        'id': 'public-1',
        'status': 2,
        'mode': 1,
        'type': 0,
        'groupId': 'grp',
        'isPrivate': false,
        'currentTimerValue': 0,
        'players': [
          {
            'id': _localId,
            'playerName': 'PublicMe',
            'profileImageUrl': 'http://example.test/public-me.png',
          },
          if (withOpponent)
            {
              'id': _opponentId,
              'playerName': 'PublicFoe',
              'profileImageUrl': 'http://example.test/public-foe.png',
            },
        ],
      });
    }

    testWidgets('a public game still seats both players with their own '
        'images', (tester) async {
      await newContainer();
      await mountPublicEntry(tester);
      await tester.pump();
      await joinPublicLobby();
      await tester.pump();

      expect(find.byType(LobbyPlayGameScreen), findsOneWidget);
      expect(find.text('PublicMe'), findsOneWidget);
      expect(find.text('PublicFoe'), findsOneWidget);
      final rendered = cards(tester);
      expect(rendered, hasLength(2));
      expect(rendered.first.showAvatar, isTrue);
      expect(rendered.last.showAvatar, isTrue);
      expect(rendered.first.imageUrl, 'http://example.test/public-me.png');
      expect(rendered.last.imageUrl, 'http://example.test/public-foe.png');
      await drain(tester);
    });

    testWidgets('a public lobby with no opponent yet keeps the same empty '
        'seat it always had', (tester) async {
      await newContainer();
      await mountPublicEntry(tester);
      await tester.pump();
      await joinPublicLobby(withOpponent: false);
      await tester.pump();

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(find.byType(LobbyPlayGameScreen), findsOneWidget);
      expect(cards(tester).last.showAvatar, isFalse);
      expect(cards(tester).last.imageUrl, isNull);
      // The public lobby puts the waiting copy in the seat's *hint*, not its
      // name — unlike the private lobby, which uses the name. That asymmetry
      // is pre-existing and deliberately left alone.
      expect(cards(tester).last.name, isEmpty);
      expect(cards(tester).last.hint, strings.waitingForPlayer);
      expect(
        fallbackAvatars(),
        findsNothing,
        reason: 'the empty public seat never painted one either — it just '
            'no longer builds it',
      );
      await drain(tester);
    });

    testWidgets('the public entry still dispatches JoinRandomGame',
        (tester) async {
      await newContainer();
      await mountPublicEntry(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(
        signalR.invocations
            .where((i) => i.method == PlayGameHubEvents.joinRandomGame)
            .length,
        1,
      );
      await drain(tester);
    });
  });

  group('the fallback itself still works for a seated player', () {
    testWidgets('a host who has no profile image still gets the default '
        'avatar — the fallback is dropped only for an empty seat',
        (tester) async {
      await newContainer();
      await mountPrivateEntry(tester);
      await tester.pump();

      final game = _privateGame();
      // Same payload, minus the host's own image.
      ((game['players'] as List).first as Map<String, dynamic>)
          .remove('profileImageUrl');
      notifier().applySessionEvent(PlayGameHubEvents.gameCreated, game);
      await tester.pump();

      expect(find.text('RealHost'), findsOneWidget);
      expect(cards(tester).first.showAvatar, isTrue);
      expect(cards(tester).first.imageUrl, isNull);
      expect(
        fallbackAvatars(),
        findsOneWidget,
        reason: 'a real, seated player with no image must still fall back '
            'to the default avatar — only the empty opponent seat builds '
            'nothing at all',
      );
      await drain(tester);
    });
  });
}

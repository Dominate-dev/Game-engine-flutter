import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The account identity the host supplies through GameEngineConfig.
//
// `GameController._findPlayers` seats the local player by matching the
// persisted `user_id` against the roster, and the roster carries numeric
// account ids. Before `userId` existed on the config the engine wrote only
// the token and the socialMediaId, so `user_id` stayed unset, `_getMyUserId`
// fell through to the socialMediaId, and nothing in the roster matched it —
// no seat, no name, no avatar. These tests pin the whole path from the
// public config down to the seated player.

const _accountId = 91;
const _socialMediaId = '118257441539724769068';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  @override
  bool get isConnected => true;

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

/// A roster shaped like the hub's, holding the local account id and one
/// opponent.
Map<String, dynamic> _gameWithRoster({required String localPlayerId}) => {
      'id': 'game-1',
      'status': 2,
      'mode': 1,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': [
        {
          'id': localPlayerId,
          'playerName': 'Me',
          'profileImageUrl': 'http://example.test/me.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'Foe',
          'profileImageUrl': 'http://example.test/foe.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late SharedPrefsService prefs;
  late GameEngine engine;

  Future<void> newEngine({Map<String, Object> seed = const {}}) async {
    SharedPreferences.setMockInitialValues(seed);
    prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
      ],
    );
    addTearDown(container.dispose);
    engine = GameEngine(container: container);
    addTearDown(engine.dispose);
  }

  setUp(() async => newEngine());

  const config = GameEngineConfig(
    token: 'token-abc',
    userId: _accountId,
    socialMediaId: _socialMediaId,
    language: AppLanguage.arabic,
    musicEnabled: false,
    soundEnabled: false,
  );

  GameController notifier() {
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(gameControllerProvider.notifier);
  }

  group('1. GameEngineConfig carries the account id', () {
    test('it is a field of the config, alongside socialMediaId', () {
      expect(config.userId, _accountId);
      expect(config.socialMediaId, _socialMediaId);
    });

    test('copyWith preserves it, and can replace it on its own', () {
      expect(config.copyWith(token: 't2').userId, _accountId);
      expect(config.copyWith(userId: 5).userId, 5);
      expect(
        config.copyWith(userId: 5).socialMediaId,
        _socialMediaId,
        reason: 'replacing one identity must not disturb the other',
      );
    });

    test(
        'it participates in equality, so a changed account is a changed '
        'config', () {
      expect(config.copyWith(userId: 5), isNot(config));
      expect(config.copyWith(userId: _accountId), config);
    });

    test('toMap carries it under `userId`, and fromMap reads it back', () {
      expect(config.toMap()['userId'], _accountId);
      expect(
        GameEngineConfig.fromMap(config.toMap()),
        config,
        reason: 'the bridge round-trips the whole contract, id included',
      );
    });
  });

  group('2. the wire shape native actually sends', () {
    test('an int id — what a Kotlin Int/Long arrives as', () {
      expect(
        GameEngineConfig.fromMap({'token': 't', 'userId': 91}).userId,
        91,
      );
    });

    test('a stringified id — a host that formats it first is just as valid',
        () {
      expect(
        GameEngineConfig.fromMap({'token': 't', 'userId': '91'}).userId,
        91,
      );
    });

    test('an omitted id is 0 — an absence, not an account', () {
      expect(GameEngineConfig.fromMap({'token': 't'}).userId, 0);
    });

    test('a non-numeric id is no id, and never becomes one', () {
      expect(
        GameEngineConfig.fromMap({'token': 't', 'userId': 'abc'}).userId,
        0,
      );
      expect(
        GameEngineConfig.fromMap({'token': 't', 'userId': null}).userId,
        0,
      );
    });
  });

  group('3. the engine persists it through the existing storage API', () {
    test('initialize writes the supplied id to the existing user_id key',
        () async {
      await engine.initialize(config);

      expect(prefs.getUserId(), _accountId);
      expect(
        prefs.getString(PrefsKeys.userId),
        '$_accountId',
        reason: 'the existing key, written through the existing setter — '
            'no second storage key was introduced',
      );
    });

    test('updateConfig outside a game writes a changed id too', () async {
      await engine.initialize(config);

      await engine.updateConfig(config.copyWith(userId: 4242));

      expect(prefs.getUserId(), 4242);
    });

    test('the other config values still land exactly as they did', () async {
      await engine.initialize(config);

      expect(prefs.getToken(), 'token-abc');
      expect(prefs.getSocialMediaId(), _socialMediaId);
      expect(container.read(appLanguageProvider), AppLanguage.arabic);
      final audio = container.read(audioServiceProvider);
      expect(audio.isMusicEnabled, isFalse);
      expect(audio.isSfxEnabled, isFalse);
      expect(engine.activeConfig, config);
    });
  });

  group('4. no default, no mock, no derived id', () {
    test('the config defaults to 0 rather than to any account', () {
      expect(const GameEngineConfig(token: 't').userId, 0);
    });

    test('a config with no id leaves storage with no id', () async {
      await engine.initialize(
        const GameEngineConfig(token: 't', socialMediaId: _socialMediaId),
      );

      expect(prefs.getUserId(), 0);
      expect(
        prefs.getString(PrefsKeys.userId),
        isNull,
        reason: 'nothing is invented, and no placeholder is written',
      );
    });

    test('the socialMediaId is never copied into the account id', () async {
      await engine.initialize(
        const GameEngineConfig(token: 't', socialMediaId: _socialMediaId),
      );

      expect(prefs.getUserId(), 0);
      expect(prefs.getSocialMediaId(), _socialMediaId);
    });

    test('a config that omits the id leaves a stored one intact', () async {
      await newEngine(seed: {PrefsKeys.userId: '$_accountId'});

      await engine.initialize(const GameEngineConfig(token: 't'));

      expect(
        prefs.getUserId(),
        _accountId,
        reason: 'an absent field clears nothing — the same guard '
            'AuthNotifier._persist already applies to its own write',
      );
    });
  });

  group('5. the controller resolves the seat from that id', () {
    test('_getMyUserId, read through the seat it decides, is the account id',
        () async {
      await engine.initialize(config);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _gameWithRoster(localPlayerId: '$_accountId'),
      );

      final session = container.read(gameControllerProvider);
      expect(session.me?.id, '$_accountId');
      expect(session.me?.playerName, 'Me');
      expect(session.opponent?.id, _opponentId);
    });

    test('the seated player carries the name and image the avatar reads',
        () async {
      await engine.initialize(config);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _gameWithRoster(localPlayerId: '$_accountId'),
      );

      final me = container.read(gameControllerProvider).me;
      expect(me?.playerName, 'Me');
      expect(me?.profileImageUrl, 'http://example.test/me.png');
    });

    test('the socialMediaId seats nobody — it is not a substitute', () async {
      await engine.initialize(
        const GameEngineConfig(token: 't', socialMediaId: _socialMediaId),
      );

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _gameWithRoster(localPlayerId: '$_accountId'),
      );

      expect(
        container.read(gameControllerProvider).me,
        isNull,
        reason: 'this is the bug being fixed: with no account id the '
            'controller has only the socialMediaId, which matches no '
            'roster player, and seating the wrong one would be worse',
      );
    });

    test('with both present the account id wins the match', () async {
      // The socialMediaId is in the roster as the *opponent*, so a fallback
      // to it would seat the wrong player rather than merely fail.
      await engine.initialize(
        config.copyWith(socialMediaId: _opponentId),
      );

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _gameWithRoster(localPlayerId: '$_accountId'),
      );

      final session = container.read(gameControllerProvider);
      expect(session.me?.id, '$_accountId');
      expect(session.opponent?.id, _opponentId);
    });
  });
}

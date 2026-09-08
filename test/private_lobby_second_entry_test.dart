import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The second Private Game entry on a cached FlutterEngine.
//
// `_leftGame` was documented as one-shot and never cleared, on the reasoning
// that a controller is per-entry (autoDispose) so a fresh entry gets a fresh
// `false`. A native host that keeps one warmed FlutterEngine across entries
// breaks that: the second private entry reaches the same controller with
// `_leftGame` still true from the first game's exit, and
// `createPrivateGame`'s guard silently suppresses the dispatch — a lobby
// shell with no room code and empty seats, until the app is force-stopped.
//
// enterPrivateLobby now clears it, and only it. Everything else `_leftGame`
// protects is exercised below so the guard is not weakened in the process.

const _localId = '47';
const _interestIds = [2];

class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];

  /// The entry connect is not what is under test; the hub is up throughout,
  /// because `createPrivateGame` refuses to dispatch on anything less.
  @override
  bool get isConnected => true;

  int countOf(String method) =>
      invocations.where((m) => m == method).length;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add(methodName);
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

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  GameController notifier() => container.read(gameControllerProvider.notifier);

  int creates() => signalR.countOf(PlayGameHubEvents.createPrivateGame);
  int leaves() => signalR.countOf(PlayGameHubEvents.leaveGame);

  setUp(() async => setUpContainer());

  group('1. the second entry, on the controller the first one left', () {
    test('enter, create, leave, enter again — the second create still goes '
        'out', () async {
      notifier().enterPrivateLobby();
      expect(await notifier().createPrivateGame(_interestIds), isTrue);
      expect(creates(), 1);

      await notifier().leaveGame();
      expect(
        notifier().hasLeftGame,
        isTrue,
        reason: 'the exit is what used to poison every later entry',
      );

      notifier().enterPrivateLobby();
      expect(
        notifier().hasLeftGame,
        isFalse,
        reason: 'a new private lobby is a new session, not the left one',
      );

      expect(await notifier().createPrivateGame(_interestIds), isTrue);
      expect(
        creates(),
        2,
        reason: 'this is the dispatch the device never saw',
      );
    });

    test('a third entry is no different from the second', () async {
      for (var entry = 1; entry <= 3; entry++) {
        notifier().enterPrivateLobby();
        expect(await notifier().createPrivateGame(_interestIds), isTrue);
        expect(creates(), entry);
        await notifier().leaveGame();
      }
    });

    test('joining by code recovers across an exit the same way', () async {
      notifier().enterPrivateLobby();
      expect(await notifier().joinPrivateGame('4821'), isTrue);

      await notifier().leaveGame();

      notifier().enterPrivateLobby();
      expect(
        await notifier().joinPrivateGame('4821'),
        isTrue,
        reason: 'the same guard field gates both private dispatches',
      );
      expect(signalR.countOf(PlayGameHubEvents.joinPrivateGame), 2);
    });

    test('an exit recorded without a LeaveGame — a concluded game, a refused '
        'join — is cleared too', () async {
      notifier().enterPrivateLobby();
      expect(await notifier().createPrivateGame(_interestIds), isTrue);

      notifier().markLeftGame();
      expect(notifier().hasLeftGame, isTrue);
      expect(leaves(), 0, reason: 'markLeftGame dispatches nothing');

      notifier().enterPrivateLobby();
      expect(await notifier().createPrivateGame(_interestIds), isTrue);
      expect(creates(), 2);
    });
  });

  group('2. the guard itself is unweakened', () {
    test('leaving without re-entering still suppresses a create', () async {
      notifier().enterPrivateLobby();
      await notifier().leaveGame();

      expect(await notifier().createPrivateGame(_interestIds), isFalse);
      expect(
        creates(),
        0,
        reason: 'only a new lobby entry reopens it — nothing else does',
      );
    });

    test('leaving without re-entering still suppresses a join', () async {
      notifier().enterPrivateLobby();
      await notifier().leaveGame();

      expect(await notifier().joinPrivateGame('4821'), isFalse);
      expect(signalR.countOf(PlayGameHubEvents.joinPrivateGame), 0);
    });

    test('the per-entry create guard is untouched: one create per entry',
        () async {
      notifier().enterPrivateLobby();

      expect(await notifier().createPrivateGame(_interestIds), isTrue);
      expect(await notifier().createPrivateGame(_interestIds), isFalse);

      expect(creates(), 1);
    });
  });

  group('3. leaving keeps its own semantics', () {
    test('still one LeaveGame per session, however often it is called',
        () async {
      notifier().enterPrivateLobby();
      await notifier().leaveGame();
      await notifier().leaveGame();

      expect(leaves(), 1);
    });

    test('a new session may leave on its own account', () async {
      notifier().enterPrivateLobby();
      await notifier().leaveGame();

      notifier().enterPrivateLobby();
      await notifier().leaveGame();

      expect(
        leaves(),
        2,
        reason: 'two sessions, two exits — not one session leaving twice',
      );
    });
  });

  group('4. onRecovered keeps its left-session semantics', () {
    test('a left session still owns nothing on the hub', () async {
      notifier().enterPrivateLobby();
      await notifier().leaveGame();

      await notifier().onRecovered();

      expect(
        signalR.countOf(PlayGameHubEvents.checkPlayerGame),
        0,
        reason: 'the reset must not make a left session recoverable',
      );
    });

    test('a new private lobby is recoverable again, and re-issues the create '
        'it is owed', () async {
      notifier().enterPrivateLobby();
      await notifier().leaveGame();

      notifier().enterPrivateLobby();
      await notifier().onRecovered();

      expect(signalR.countOf(PlayGameHubEvents.checkPlayerGame), 1);
      expect(
        creates(),
        0,
        reason: 'nothing is owed until a create has actually been attempted',
      );
    });
  });
}

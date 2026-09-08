import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// N4 — onWaitingShown()'s guard used to be claimed only after awaiting
// invoke(), so two calls landing in the same tick (WaitingScreen's own
// mount and onRecovered's retry both firing while still `waiting`) could
// both pass the `_didJoinRandom` check before either's await resolved,
// dispatching JoinRandomGame twice. The guard is now claimed synchronously
// before the await, closing that window; a skipped dispatch still reopens
// it exactly as before (unchanged, covered by waiting_join_retry_test.dart).

const _localId = '47';

class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];

  /// The race under test is the join guard, not the connection, so the
  /// socket reports connected throughout.
  @override
  bool get isConnected => true;

  List<String> get joins =>
      invocations.where((m) => m == PlayGameHubEvents.joinRandomGame).toList();

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

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  setUp(() async => setUpContainer());

  test(
    'two onWaitingShown() calls landing in the same tick dispatch '
    'JoinRandomGame only once',
    () async {
      final first = notifier().onWaitingShown();
      final second = notifier().onWaitingShown();

      await Future.wait([first, second]);

      expect(
        signalR.joins,
        hasLength(1),
        reason: 'the guard must be claimed before the first await, not '
            'after, or a same-tick second caller can still pass the check',
      );
    },
  );

  test(
    'the same race through onRecovered — mount and recovery landing '
    'together still join only once',
    () async {
      final mount = notifier().onWaitingShown();
      final recovered = notifier().onRecovered();

      await Future.wait([mount, recovered]);

      expect(signalR.joins, hasLength(1));
    },
  );
}

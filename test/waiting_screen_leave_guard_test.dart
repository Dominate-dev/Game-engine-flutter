import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// BUG-05 (final audit) regression tests.
//
// WaitingScreen.onEventReceived routes both `GameFinished` and `Error` to
// _leaveToPreviousScreen(), which used to have no re-entrancy guard — unlike
// LobbyPlayGameScreen._leaveToHome(), which already used a `_leaving` flag
// for the identical class of problem. Two leave-triggering events arriving
// close together (or the same event delivered twice) could call
// Navigator.of(context).pop() more than once.
//
// This drives the real WaitingScreen widget through its actual HubEventMixin
// pipeline (a fake SignalRService that stores and fires registered
// listeners, same convention used elsewhere this session for
// GameControllerScreen), with a NavigatorObserver counting real pops — not a
// synthetic call to a private method, so this proves the production
// pipeline (SignalR event -> onEventReceived -> _leaveToPreviousScreen ->
// Navigator.pop) is guarded, not just the guard's own logic in isolation.

const _localId = '47';

/// One hub event listener, named so the map and its iteration share a type.
typedef HubHandler = void Function(List<Object?>?);

class _FiringSignalRService extends SignalRService {
  final _handlers = <String, List<HubHandler>>{};

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    final list = _handlers.putIfAbsent(eventName, () => []);
    list.add(handler);
    return () => list.remove(handler);
  }

  @override
  void reattachEventHandlers() {}

  void fire(String eventName, [List<Object?>? args]) {
    for (final handler
        in List.of(_handlers[eventName] ?? const <HubHandler>[])) {
      handler(args);
    }
  }
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
  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {}
}

/// Counts real Navigator pops — the observable effect a duplicate
/// Navigator.pop() call would double, if the re-entrancy guard were absent.
class _PopRecorder extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late ProviderContainer container;
  late _FiringSignalRService signalR;
  late _PopRecorder popRecorder;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpWaitingScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FiringSignalRService();
    popRecorder = _PopRecorder();
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [popRecorder],
          home: const _HomePlaceholder(),
        ),
      ),
    );
    await tester.pump();

    // Pushed as a real second route (matching how the app actually
    // navigates into WaitingScreen), so Navigator.pop() has something to
    // pop and popRecorder can count it.
    unawaited(
      navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const WaitingScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(WaitingScreen), findsOneWidget, reason: 'sanity');
  }

  group('WaitingScreen — leave re-entrancy guard (BUG-05)', () {
    // UPDATED: this previously asserted that GameFinished tore Waiting down.
    // That is the behaviour this change intentionally corrects — GameFinished
    // is an active-game lifecycle event and the waiting lifecycle now ignores
    // it. The Error cases below are unchanged and still assert the guard.
    testWidgets(
      'GameFinished fired twice is ignored — no pop, still on Waiting',
      (tester) async {
        await pumpWaitingScreen(tester);

        signalR.fire(PlayGameHubEvents.gameFinished);
        signalR.fire(PlayGameHubEvents.gameFinished);

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(popRecorder.popCount, 0);
        expect(find.byType(WaitingScreen), findsOneWidget);
      },
    );

    testWidgets(
      'GameFinished is ignored but a following Error still pops exactly once',
      (tester) async {
        await pumpWaitingScreen(tester);

        signalR.fire(PlayGameHubEvents.gameFinished);
        signalR.fire(PlayGameHubEvents.error);

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(popRecorder.popCount, 1);
        expect(find.byType(WaitingScreen), findsNothing);
      },
    );

    testWidgets(
      'Error fired twice, back-to-back, pops exactly once',
      (tester) async {
        await pumpWaitingScreen(tester);

        signalR.fire(PlayGameHubEvents.error);
        signalR.fire(PlayGameHubEvents.error);

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(popRecorder.popCount, 1);
      },
    );

    // UPDATED for the same reason as the first case above.
    testWidgets(
      'a single GameFinished is ignored and leaves the user on Waiting',
      (tester) async {
        await pumpWaitingScreen(tester);

        signalR.fire(PlayGameHubEvents.gameFinished);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(popRecorder.popCount, 0);
        expect(find.byType(WaitingScreen), findsOneWidget,
            reason: 'the search continues — a stale terminal event must not '
                'end it');
        expect(find.byType(_HomePlaceholder), findsNothing);
      },
    );

    testWidgets(
      'a single Error still leaves normally (existing behavior preserved)',
      (tester) async {
        await pumpWaitingScreen(tester);

        signalR.fire(PlayGameHubEvents.error);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(popRecorder.popCount, 1);
        expect(find.byType(WaitingScreen), findsNothing);
      },
    );
  });
}

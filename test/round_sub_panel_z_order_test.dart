import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The round overlays (RoundLottieDialog, PlayerAnsweredDialog) no longer get
// a DialogRoute of their own. They render in a RoundSubPanelLayer inside
// GameControllerScreen's own subtree, so a regular dialog — which is a route
// pushed on top of that screen's page route — is above them by construction.
//
// Nothing about the queue changed: the presenter still hands back a Future
// that completes when the overlay leaves, so _enqueueRoundDialog /
// _roundDialogChain cannot tell the difference. The tests below check the
// three things that did change: where the overlay lands, that it still
// auto-dismisses on its own timing, and that its dismissal reaches only
// itself.

const _localId = '47';
const _opponentId = '211403';

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

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

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
      Result.success(const StickerPage(items: [], pageIndex: 0, pageSize: 20));

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
    bool? loop = true,
    double? volume,
  }) async {}

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A stand-in for every regular dialog in the app — one that is pushed as a
/// route, exactly as `showAppDialog` does. Deliberately plain: what is being
/// tested is where it sits relative to a round overlay, not its content.
class _RegularDialog extends StatelessWidget {
  const _RegularDialog();

  @override
  Widget build(BuildContext context) => const Dialog(
        child: SizedBox(height: 100, child: Text('regular-dialog')),
      );
}

Map<String, dynamic> _game({required int type}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'passes': 1,
          'penalty': 0,
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'passes': 1,
          'penalty': 0,
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q1',
        'textEn': 'q1',
        'questionNumber': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _FiringSignalRService signalR;
  late GlobalKey<NavigatorState> navigatorKey;

  /// Pushes a real [GameControllerScreen] onto a real Navigator, so the
  /// route hierarchy under test is the production one.
  Future<void> enterRound(WidgetTester tester, {int type = 1}) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FiringSignalRService();
    final bindings = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
        stickersRepositoryProvider.overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(_FakeAudioService()),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        signalRStatusProvider.overrideWith(
          (ref) => Stream<SignalRStatus>.value(SignalRStatus.connected),
        ),
      ],
    );
    addTearDown(container.dispose);

    navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const _HomePlaceholder(),
        ),
      ),
    );
    await tester.pump();

    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    bindings.emit(PlayGameHubEvents.gameStarted, _game(type: type));
    await tester.pump();
    // Drain the round intro, which is itself a RoundLottieDialog.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  }

  /// Opens a regular dialog the way every non-round dialog in the app is
  /// opened: a route on the same Navigator.
  Future<void> openRegularDialog(WidgetTester tester) async {
    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const _RegularDialog(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Fires the hub event that raises a [RoundLottieDialog] (TimeStarted →
  /// the Start Timer overlay).
  Future<void> fireLottieOverlay(WidgetTester tester) async {
    signalR.fire(PlayGameHubEvents.timeStarted);
    await tester.pump();
    await tester.pump();
  }

  /// Fires the hub event that raises a [PlayerAnsweredDialog].
  Future<void> firePlayerAnswered(WidgetTester tester) async {
    signalR.fire(PlayGameHubEvents.playerAnswered, ['an answer', '', 'g1']);
    await tester.pump();
    await tester.pump();
    // Its entrance slide.
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Depth-first element order. The Navigator's Overlay lays its entries out
  /// bottom-to-top, so a later index is painted above an earlier one — this
  /// is the z-order the viewer actually sees.
  int paintIndexOf(WidgetTester tester, Type type) {
    final elements = tester.allElements.toList();
    return elements.indexWhere((e) => e.widget.runtimeType == type);
  }

  group('1-2. a round overlay opens with no regular dialog present', () {
    testWidgets('RoundLottieDialog opens', (tester) async {
      await enterRound(tester);

      await fireLottieOverlay(tester);

      expect(find.byType(RoundLottieDialog), findsOneWidget);
    });

    testWidgets('PlayerAnsweredDialog opens', (tester) async {
      await enterRound(tester);

      await firePlayerAnswered(tester);

      expect(find.byType(PlayerAnsweredDialog), findsOneWidget);
      expect(find.text('an answer'), findsOneWidget);
    });
  });

  group('3. a round overlay opens while a regular dialog is already open', () {
    testWidgets('RoundLottieDialog opens anyway', (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      expect(find.text('regular-dialog'), findsOneWidget, reason: 'sanity');

      await fireLottieOverlay(tester);

      expect(find.byType(RoundLottieDialog), findsOneWidget,
          reason: 'not blocked, not queued behind the regular dialog');
      expect(find.text('regular-dialog'), findsOneWidget,
          reason: 'and the regular dialog was not replaced');
    });

    testWidgets('PlayerAnsweredDialog opens anyway', (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);

      await firePlayerAnswered(tester);

      expect(find.byType(PlayerAnsweredDialog), findsOneWidget);
      expect(find.text('regular-dialog'), findsOneWidget);
    });
  });

  group('4. the regular dialog stays above the round overlay', () {
    testWidgets('RoundLottieDialog is painted below it', (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      await fireLottieOverlay(tester);

      expect(
        paintIndexOf(tester, _RegularDialog),
        greaterThan(paintIndexOf(tester, RoundLottieDialog)),
        reason: 'the regular dialog is a route above the page route that '
            'hosts the overlay layer',
      );
    });

    testWidgets('PlayerAnsweredDialog is painted below it', (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      await firePlayerAnswered(tester);

      expect(
        paintIndexOf(tester, _RegularDialog),
        greaterThan(paintIndexOf(tester, PlayerAnsweredDialog)),
      );
    });

    testWidgets('order does not depend on which opened first', (tester) async {
      // The overlay first, the regular dialog second — the regular dialog
      // still ends up above, because its route is above the page route
      // whatever the timing was.
      await enterRound(tester);
      await fireLottieOverlay(tester);
      await openRegularDialog(tester);

      expect(
        paintIndexOf(tester, _RegularDialog),
        greaterThan(paintIndexOf(tester, RoundLottieDialog)),
      );
    });

    testWidgets('the overlay renders inside the sub-panel layer, not on a '
        'route of its own', (tester) async {
      await enterRound(tester);
      await fireLottieOverlay(tester);

      expect(
        find.ancestor(
          of: find.byType(RoundLottieDialog),
          matching: find.byType(RoundSubPanelScope),
        ),
        findsOneWidget,
      );
    });
  });

  group('5. auto-dismiss timing is unchanged', () {
    testWidgets('RoundLottieDialog clears on its own timer', (tester) async {
      await enterRound(tester);
      await fireLottieOverlay(tester);
      expect(find.byType(RoundLottieDialog), findsOneWidget);

      // TimeStarted's overlay is the 2000ms one; still up just before.
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byType(RoundLottieDialog), findsOneWidget,
          reason: 'not dismissed early');

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsNothing);
    });

    testWidgets('PlayerAnsweredDialog clears on its own timer',
        (tester) async {
      await enterRound(tester);
      await firePlayerAnswered(tester);
      expect(find.byType(PlayerAnsweredDialog), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      // Its slide-out runs before it clears — unchanged.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(PlayerAnsweredDialog), findsNothing);
    });

    testWidgets('the timer runs the same with a regular dialog above it',
        (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      await fireLottieOverlay(tester);

      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byType(RoundLottieDialog), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsNothing,
          reason: 'the overlay is not held open by the dialog above it');
    });
  });

  group('6. dismissal reaches only the overlay itself', () {
    testWidgets('a RoundLottieDialog timeout leaves the regular dialog up',
        (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      await fireLottieOverlay(tester);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byType(RoundLottieDialog), findsNothing);
      expect(find.text('regular-dialog'), findsOneWidget,
          reason: 'the overlay used to pop the topmost route, which is this '
              'dialog — it must now close only itself');
    });

    testWidgets('a PlayerAnsweredDialog timeout leaves it up too',
        (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      await firePlayerAnswered(tester);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      // Its slide-out has to run before it clears — the same frames the
      // timing test above pumps.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(PlayerAnsweredDialog), findsNothing);
      expect(find.text('regular-dialog'), findsOneWidget);
    });

    testWidgets('a whole queue draining under a regular dialog never pops it',
        (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);

      // Three overlays back to back — the queue shows them one at a time,
      // and every one of them dismisses itself.
      signalR.fire(PlayGameHubEvents.timeStarted);
      signalR.fire(PlayGameHubEvents.playerAnswered, ['x', '', 'g1']);
      signalR.fire(
        PlayGameHubEvents.correctAnswer,
        ['text', 'textEn', _localId, 'g1'],
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      }

      expect(find.text('regular-dialog'), findsOneWidget,
          reason: 'the dialog above outlives the entire round queue');
    });

    testWidgets('the regular dialog is still the one that pops', (tester) async {
      await enterRound(tester);
      await openRegularDialog(tester);
      await fireLottieOverlay(tester);

      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('regular-dialog'), findsNothing);
      expect(find.byType(GameControllerScreen), findsOneWidget,
          reason: 'the page route underneath is untouched');
    });
  });

  group('7-8. every round overlay goes through the presenter', () {
    /// Each of these hub events raises one of the two round overlays through
    /// a handler. Landing inside a [RoundSubPanelScope] is the proof it went
    /// via the sub-panel presenter rather than `showAppDialog`.
    testWidgets('TimeStarted (RoundLottieDialog)', (tester) async {
      await enterRound(tester);
      signalR.fire(PlayGameHubEvents.timeStarted);
      await tester.pump();
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(RoundLottieDialog),
          matching: find.byType(RoundSubPanelScope),
        ),
        findsOneWidget,
      );
    });

    testWidgets('CorrectAnswer (RoundLottieDialog)', (tester) async {
      await enterRound(tester);
      signalR.fire(
        PlayGameHubEvents.correctAnswer,
        ['text', 'textEn', _localId, 'g1'],
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(RoundLottieDialog),
          matching: find.byType(RoundSubPanelScope),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ChangeTurn (RoundLottieDialog)', (tester) async {
      await enterRound(tester);
      signalR.fire(PlayGameHubEvents.changeTurn, [_localId, 'g1']);
      await tester.pump();
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(RoundLottieDialog),
          matching: find.byType(RoundSubPanelScope),
        ),
        findsOneWidget,
      );
    });

    testWidgets('PlayerAnswered (PlayerAnsweredDialog)', (tester) async {
      await enterRound(tester);
      signalR.fire(PlayGameHubEvents.playerAnswered, ['an answer', '', 'g1']);
      await tester.pump();
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(PlayerAnsweredDialog),
          matching: find.byType(RoundSubPanelScope),
        ),
        findsOneWidget,
      );
    });

    testWidgets('PlayerPassed — both branches of the same call site',
        (tester) async {
      // onPlayerPassed builds a RoundLottieDialog for me and a
      // PlayerAnsweredDialog for the opponent, from one _enqueueRoundDialog
      // call. Routing by widget type is what makes both land correctly.
      await enterRound(tester);
      signalR.fire(PlayGameHubEvents.playerPassed, [_opponentId, 'g1']);
      await tester.pump();
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(PlayerAnsweredDialog),
          matching: find.byType(RoundSubPanelScope),
        ),
        findsOneWidget,
      );
    });
  });

  group('10. unrelated dialogs keep their route', () {
    late bool fallbackCalled;
    late Widget? fallbackChild;

    Future<void> present(WidgetRef ref, Widget child) {
      fallbackCalled = false;
      fallbackChild = null;
      final presenter = roundDialogPresenter(
        ref,
        canPresent: () => true,
        fallback: ({required Widget child, bool barrierDismissible = true}) {
          fallbackCalled = true;
          fallbackChild = child;
          return Future<void>.value();
        },
      );
      return presenter(child: child, barrierDismissible: false);
    }

    testWidgets('a non-round dialog goes to the fallback, untouched',
        (tester) async {
      await enterRound(tester);
      final element = tester.element(find.byType(GameControllerScreen));
      final ref = ProviderScope.containerOf(element);
      // A WidgetRef is not needed for the fallback branch; drive the same
      // decision through a real container-backed ref.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ref,
          child: Consumer(
            builder: (context, widgetRef, _) {
              unawaited(present(widgetRef, const _RegularDialog()));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(fallbackCalled, isTrue);
      expect(fallbackChild, isA<_RegularDialog>());
    });
  });
}

import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/round_attempts_info.dart';
import 'package:play_game/presentation/widgets/rounds/round_actions_row.dart';
import 'package:play_game/presentation/widgets/rounds/round_report_button.dart';
import 'package:play_game/presentation/widgets/rounds/round_info_card.dart';
import 'package:play_game/presentation/widgets/rounds/round_header_bar.dart';
import 'package:play_game/presentation/widgets/rounds/round_touch_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

// P0 responsive regression cover for the Comeback / Breaker round.
//
// These run at real device geometry — physicalSize, devicePixelRatio, safe
// area insets and textScaler — because the rest of the suite runs at the
// harness default 800x600 @ scale 1.0, where none of these failures appear.
//
// What they pin, both found by rendering the screens across device classes:
//   P0-1 RoundAttemptsInfo (round_attempts_info.dart) laid its label and its
//        count in a Row with mainAxisSize.min and no flex, so the pair could
//        not shrink. It overflowed horizontally on every phone class in both
//        languages at the DEFAULT text scale — 168px on an iPhone SE, still
//        58px on an iPhone 15 Pro Max. English overflowed further than Arabic
//        only because 'Number of attempts: ' is the longer string.
//   P0-2 The same screens overflowed vertically once safe-area insets and a
//        raised text scale were applied together: the header block above the
//        scrollable region (header bar, title bar, score row and their fixed
//        spacers) grows with text scale, and the Expanded below it was left
//        with less than zero height.
//
// Both are asserted the same way: render, and require the rendering library
// to report no overflow at all.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  @override
  bool get hasLiveConnection => true;
  @override
  Future<bool> invoke(String m, {List<Object?>? args}) async => true;
  @override
  void Function() addEventListener(String e, void Function(List<Object?>?) h) =>
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
  void bindEvents(Iterable<String> e) {}
  @override
  void dispose() => _events.close();
}

/// A real device class: logical size, pixel ratio and safe-area insets.
class Device {
  const Device(this.name, this.size, this.dpr, this.padding);
  final String name;
  final Size size;
  final double dpr;
  final EdgeInsets padding;
  @override
  String toString() => name;
}

// Published logical-pixel geometry for each class.
const smallPhone = // iPhone SE 2/3 — smallest supported target
    Device('iPhoneSE(320x568)', Size(320, 568), 2.0, EdgeInsets.only(top: 20));
const normalPhone = // Pixel 5
    Device('Pixel5(393x851)', Size(393, 851), 2.75,
        EdgeInsets.only(top: 24, bottom: 24));
const largePhone = // iPhone 15 Pro Max
    Device('iPhone15ProMax(430x932)', Size(430, 932), 3.0,
        EdgeInsets.only(top: 59, bottom: 34));
const tallNarrow = // 20:9 Android with a 3-button navigation bar
    Device('Android20by9(360x800)', Size(360, 800), 3.0,
        EdgeInsets.only(top: 24, bottom: 48));
const notchPhone = // iPhone 13
    Device('iPhone13(390x844)', Size(390, 844), 3.0,
        EdgeInsets.only(top: 47, bottom: 34));

const allDevices = [
  smallPhone,
  normalPhone,
  largePhone,
  tallNarrow,
  notchPhone,
];

/// Default plus the accessibility steps the OS font sliders produce.
const textScales = [1.0, 1.3, 1.6, 2.0];

Map<String, dynamic> _roundGame({
  required int type,
  String name = 'me',
  String opponent = 'them',
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'currentTimerValue': 30,
      'players': [
        {
          'id': _localId,
          'playerName': name,
          'score': 12,
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': opponent,
          'score': 8,
          'makeupTryCount': 1,
          'maxMakeupTryCount': 3,
        },
      ],
      'currentQuestion': {
        'id': 5,
        'questionNumber': 1,
        'text': 'سؤال الجولة؟',
        'textEn': 'The round question?',
        'answers': [
          {'id': 10, 'text': 'إجابة أولى', 'textEn': 'First answer'},
          {'id': 11, 'text': 'إجابة ثانية', 'textEn': 'Second answer'},
          {'id': 12, 'text': 'إجابة ثالثة', 'textEn': 'Third answer'},
          {'id': 13, 'text': 'إجابة رابعة', 'textEn': 'Fourth answer'},
        ],
      },
    };

void main() {
  late ProviderContainer container;

  Future<void> setUpContainer(String language) async {
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
      ],
    );
    addTearDown(container.dispose);
  }

  /// Renders [child] at [device]/[scale] and returns every overflow the
  /// rendering library reported.
  Future<List<String>> renderAndCollect(
    WidgetTester tester,
    Device device,
    double scale,
    Widget child, {
    void Function()? seed,
  }) async {
    tester.view.physicalSize = device.size * device.dpr;
    tester.view.devicePixelRatio = device.dpr;
    tester.view.padding = FakeViewPadding(
      top: device.padding.top * device.dpr,
      bottom: device.padding.bottom * device.dpr,
      left: device.padding.left * device.dpr,
      right: device.padding.right * device.dpr,
    );
    addTearDown(tester.view.reset);

    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        overflows.add(message.split('\n').first);
      }
    };

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(
            size: device.size,
            devicePixelRatio: device.dpr,
            padding: device.padding,
            textScaler: TextScaler.linear(scale),
          ),
          child: MaterialApp(home: child),
        ),
      ),
    );
    seed?.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    FlutterError.onError = previous;
    return overflows;
  }

  Future<List<String>> renderRound(
    WidgetTester tester,
    Widget screen,
    int type,
    Device device,
    double scale, {
    String name = 'me',
  }) =>
      renderAndCollect(
        tester,
        device,
        scale,
        screen,
        seed: () => container.read(gameControllerProvider.notifier)
            .applySessionEvent(
              PlayGameHubEvents.gameStarted,
              _roundGame(type: type, name: name, opponent: name),
            ),
      );

  group('P0-1 — RoundAttemptsInfo never overflows horizontally', () {
    for (final device in allDevices) {
      for (final language in [AppLanguage.english, AppLanguage.arabic]) {
        testWidgets('$device / $language / scale 1.0', (tester) async {
          await setUpContainer(language);
          final overflows = await renderRound(
            tester,
            const ComeBackRoundScreen(),
            4,
            device,
            1.0,
          );

          expect(
            find.byType(RoundAttemptsInfo),
            findsOneWidget,
            reason: 'the component under test must actually be on screen',
          );
          expect(
            overflows,
            isEmpty,
            reason: 'before the fix this row overflowed on every phone at '
                'the default text scale',
          );
        });
      }
    }

    for (final scale in textScales) {
      testWidgets('smallest phone at accessibility scale $scale',
          (tester) async {
        await setUpContainer(AppLanguage.english);
        final overflows = await renderRound(
          tester,
          const ComeBackRoundScreen(),
          4,
          smallPhone,
          scale,
        );

        expect(find.byType(RoundAttemptsInfo), findsOneWidget);
        expect(overflows, isEmpty);
      });
    }

    for (final device in [normalPhone, largePhone, tallNarrow, notchPhone]) {
      testWidgets('$device at the maximum accessibility scale 2.0',
          (tester) async {
        await setUpContainer(AppLanguage.english);
        final overflows = await renderRound(
          tester,
          const ComeBackRoundScreen(),
          4,
          device,
          2.0,
        );

        expect(overflows, isEmpty);
      });
    }

    testWidgets('the attempts value itself is preserved, not shrunk away',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(
        tester,
        const ComeBackRoundScreen(),
        4,
        smallPhone,
        1.6,
      );

      final info = tester.widget<RoundAttemptsInfo>(
        find.byType(RoundAttemptsInfo),
      );
      expect(info.tryCount, 0);
      expect(info.maxTryCount, 3);
      expect(
        find.text('0/3'),
        findsOneWidget,
        reason: 'the count keeps its natural width — the label is what gives '
            'way, never the value',
      );
    });
  });

  // The 320dp x 2.0 corner that used to overflow by 27px. RoundActionsRow
  // lays the report button out with an unbounded main axis, so it took its
  // full intrinsic width (227 of 292, 78%) and left RoundAttemptsInfo 57 —
  // less than the 84 the bare count needs. The button is now capped at half
  // the row and its own label can ellipsize.
  group('RoundReportButton no longer starves the row', () {
    for (final language in [AppLanguage.english, AppLanguage.arabic]) {
      testWidgets('320x568 at scale 2.0 / $language', (tester) async {
        await setUpContainer(language);
        final overflows = await renderRound(
          tester,
          const ComeBackRoundScreen(),
          4,
          smallPhone,
          2.0,
        );

        final actionsRow = tester.getSize(find.byType(RoundActionsRow).first);
        final reportButton =
            tester.getSize(find.byType(RoundReportButton).first);
        final attempts = tester.getSize(find.byType(RoundAttemptsInfo).first);

        expect(
          reportButton.width / actionsRow.width,
          lessThanOrEqualTo(0.5 + 0.001),
          reason: 'capped at half the row — it took 78% before',
        );
        expect(
          attempts.width,
          greaterThan(84),
          reason: 'the leading now clears the width the bare count needs',
        );
        expect(overflows, isEmpty);
      });
    }

    testWidgets('the cap does not bite at normal text scale', (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(
        tester,
        const ComeBackRoundScreen(),
        4,
        smallPhone,
        1.0,
      );

      // Measured before and after the change on 320/393/430dp: 143px either
      // way. The cap sits just above the natural width, so the normal-scale
      // layout is untouched.
      expect(
        tester.getSize(find.byType(RoundReportButton).first).width,
        143.0,
        reason: 'natural width, unchanged by the cap',
      );
    });

    testWidgets('the button keeps its icon and stays tappable when capped',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(
        tester,
        const ComeBackRoundScreen(),
        4,
        smallPhone,
        2.0,
      );

      expect(find.byType(RoundReportButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RoundReportButton),
          matching: find.byType(GestureDetector),
        ),
        findsWidgets,
        reason: 'interaction is preserved — only the label may ellipsize',
      );
    });
  });

  // Every other round that renders the two shared components.
  group('other rounds using the shared components', () {
    // WDYK and Auction each carry their own, separate P1/P2 overflow
    // (the Pass button; Auction's vertical growth) that this task must not
    // touch, so they are asserted at the default scale, where they were
    // clean before this change and must stay clean after it.
    for (final device in allDevices) {
      testWidgets('WDYK (RoundActionsRow) clean at $device / scale 1.0',
          (tester) async {
        await setUpContainer(AppLanguage.english);
        final overflows =
            await renderRound(tester, const WdykRoundScreen(), 1, device, 1.0);
        expect(overflows, isEmpty);
      });

      testWidgets('Auction (RoundActionsRow + standalone button) clean at '
          '$device / scale 1.0', (tester) async {
        await setUpContainer(AppLanguage.english);
        final overflows = await renderRound(
            tester, const AuctionRoundScreen(), 2, device, 1.0);
        expect(overflows, isEmpty);
      });
    }

    // Bell uses the button standalone inside an Align, where it is never
    // given a bounded width — the change cannot reach it.
    for (final device in allDevices) {
      for (final scale in textScales) {
        testWidgets('Bell (standalone button) clean at $device / $scale',
            (tester) async {
          await setUpContainer(AppLanguage.english);
          final overflows = await renderRound(
              tester, const BellRoundScreen(), 3, device, scale);
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('WDYK still renders its actions row', (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(tester, const WdykRoundScreen(), 1, normalPhone, 1.0);
      expect(find.byType(RoundActionsRow), findsOneWidget);
      expect(find.byType(RoundReportButton), findsOneWidget);
    });
  });

  group('P0-2 — Comeback does not overflow vertically', () {
    for (final device in allDevices) {
      for (final scale in textScales) {
        testWidgets('$device / scale $scale', (tester) async {
          await setUpContainer(AppLanguage.english);
          final overflows = await renderRound(
            tester,
            const ComeBackRoundScreen(),
            4,
            device,
            scale,
          );

          expect(
            overflows,
            isEmpty,
            reason: 'the shared content already scrolls its lower region, '
                'and nothing above it exceeds the viewport',
          );
        });
      }
    }

    testWidgets('short screen, largest scale, Arabic', (tester) async {
      await setUpContainer(AppLanguage.arabic);
      final overflows = await renderRound(
        tester,
        const ComeBackRoundScreen(),
        4,
        smallPhone,
        2.0,
      );
      expect(overflows, isEmpty);
    });

    testWidgets('long player names do not break it either', (tester) async {
      await setUpContainer(AppLanguage.english);
      final overflows = await renderRound(
        tester,
        const ComeBackRoundScreen(),
        4,
        smallPhone,
        1.6,
        name: 'Abdulrahman Muhammad Al-Hassan Al-Sharif Abdullah',
      );
      expect(overflows, isEmpty);
    });
  });

  group('P0-2 — Breaker does not overflow vertically', () {
    for (final device in allDevices) {
      for (final scale in textScales) {
        testWidgets('$device / scale $scale', (tester) async {
          await setUpContainer(AppLanguage.english);
          final overflows = await renderRound(
            tester,
            const BreakerRoundScreen(),
            5,
            device,
            scale,
          );

          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('short screen, largest scale, Arabic', (tester) async {
      await setUpContainer(AppLanguage.arabic);
      final overflows = await renderRound(
        tester,
        const BreakerRoundScreen(),
        5,
        smallPhone,
        2.0,
      );
      expect(overflows, isEmpty);
    });
  });

  group('the rounds still render their content', () {
    testWidgets('Comeback shows question, answers and attempts at scale 2.0',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(
        tester,
        const ComeBackRoundScreen(),
        4,
        smallPhone,
        2.0,
      );

      // The question body itself is gated behind the round's own reveal
      // (`_questionVisible`), so the card — not its text — is what proves the
      // content region survived the scale.
      expect(find.byType(RoundInfoCard), findsOneWidget);
      expect(find.byType(RoundAttemptsInfo), findsOneWidget);
      expect(find.byType(RoundActionsRow), findsOneWidget);
    });

    testWidgets('Breaker renders the same shared content', (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(
        tester,
        const BreakerRoundScreen(),
        5,
        normalPhone,
        1.0,
      );

      expect(find.byType(RoundInfoCard), findsOneWidget);
      expect(find.byType(RoundAttemptsInfo), findsOneWidget);
    });
  });

  // ---- P1: WDYK Pass button, P1: touch targets, P2: Auction vertical ----

  /// The Pass pill itself — the rounded, filled Container inside the touch
  /// target, told apart from the header bar's own boxes by its decoration.
  Finder passPill() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final decoration = w.decoration;
        return decoration is BoxDecoration &&
            decoration.color == AppColors.button &&
            decoration.borderRadius == BorderRadius.circular(50);
      });

  group('P1 — WDYK Pass button is responsive to text scale', () {
    for (final device in allDevices) {
      for (final scale in textScales) {
        for (final language in [AppLanguage.english, AppLanguage.arabic]) {
          testWidgets('$device / scale $scale / $language', (tester) async {
            await setUpContainer(language);
            final overflows = await renderRound(
              tester,
              const WdykRoundScreen(),
              1,
              device,
              scale,
            );

            expect(
              overflows,
              isEmpty,
              reason: 'the Pass pill overflowed here before: 320dp at 1.3, '
                  '1.6 and 2.0, and Pixel 5 / iPhone 13 at 2.0',
            );
          });
        }
      }
    }

    testWidgets('the pill keeps its 30px design height at normal scale',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(tester, const WdykRoundScreen(), 1, normalPhone, 1.0);

      final pill = tester.getSize(passPill());
      expect(pill.height, 30.0, reason: 'unchanged from the original design');
    });

    testWidgets('the pill grows instead of clipping at scale 2.0',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(tester, const WdykRoundScreen(), 1, normalPhone, 2.0);

      final pill = tester.getSize(passPill());
      expect(
        pill.height,
        greaterThanOrEqualTo(30.0),
        reason: 'minHeight, not a fixed height — the label is not clipped',
      );
    });
  });

  group('P1 — touch targets meet the platform minimum', () {
    testWidgets('WDYK Pass hit area is at least 48dp tall', (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(tester, const WdykRoundScreen(), 1, normalPhone, 1.0);

      final target = tester.getSize(find.byType(RoundTouchTarget).last);
      expect(
        target.height,
        greaterThanOrEqualTo(kMinTouchTarget),
        reason: '48dp Android / 44pt iOS — was 30',
      );
    });

    testWidgets('RoundHeaderBar settings and emoji hit areas are 48dp',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(tester, const WdykRoundScreen(), 1, normalPhone, 1.0);

      final targets = tester
          .widgetList<RoundTouchTarget>(find.byType(RoundTouchTarget))
          .toList();
      expect(targets.length, greaterThanOrEqualTo(2));

      for (final finder in find.byType(RoundTouchTarget).evaluate()) {
        final size = finder.size!;
        expect(size.height, greaterThanOrEqualTo(kMinTouchTarget));
        expect(size.width, greaterThanOrEqualTo(kMinTouchTarget));
      }
    });

    testWidgets('the icons themselves are NOT enlarged', (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(tester, const BellRoundScreen(), 3, normalPhone, 1.0);

      final settings = tester.widget<AppImageView>(
        find
            .byWidgetPredicate(
              (w) => w is AppImageView && w.assetPath == AppAssets.settingsIcon,
            )
            .first,
      );
      expect(settings.size, 20.0,
          reason: 'hit area grew, the drawn icon did not');
    });

    // RoundHeaderBar is shared by every round — check each still lays out.
    for (final entry in {
      'WDYK': (const WdykRoundScreen(), 1),
      'Auction': (const AuctionRoundScreen(), 2),
      'Bell': (const BellRoundScreen(), 3),
      'Comeback': (const ComeBackRoundScreen(), 4),
      'Breaker': (const BreakerRoundScreen(), 5),
    }.entries) {
      testWidgets('${entry.key} header bar renders with enlarged targets',
          (tester) async {
        await setUpContainer(AppLanguage.english);
        final overflows = await renderRound(
          tester,
          entry.value.$1,
          entry.value.$2,
          normalPhone,
          1.0,
        );
        expect(find.byType(RoundHeaderBar), findsOneWidget);
        expect(overflows, isEmpty);
      });
    }
  });

  group('P2 — Auction no longer overflows vertically', () {
    for (final device in allDevices) {
      for (final scale in textScales) {
        testWidgets('$device / scale $scale', (tester) async {
          await setUpContainer(AppLanguage.english);
          final overflows = await renderRound(
            tester,
            const AuctionRoundScreen(),
            2,
            device,
            scale,
          );
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('Arabic at the worst case: 320x568 scale 2.0', (tester) async {
      await setUpContainer(AppLanguage.arabic);
      final overflows = await renderRound(
        tester,
        const AuctionRoundScreen(),
        2,
        smallPhone,
        2.0,
      );
      expect(overflows, isEmpty);
    });

    testWidgets('block spacing is untouched at normal text scale',
        (tester) async {
      await setUpContainer(AppLanguage.english);
      await renderRound(
        tester,
        const AuctionRoundScreen(),
        2,
        normalPhone,
        1.0,
      );

      final gaps = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.height == 25.0)
          .length;
      expect(gaps, greaterThanOrEqualTo(2),
          reason: 'both 25px gaps are still exactly 25 at scale 1.0');
    });
  });
}

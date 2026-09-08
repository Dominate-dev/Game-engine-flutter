import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/round_title_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Round HEADER/TITLE text direction. Distinct from
// game_text_direction_test.dart, which covers the server-provided question
// and answer text: these are app-owned strings from PlayGameStrings, and
// they go through different widgets.
//
// The round roots force Directionality.rtl for their mirrored chrome, so a
// heading that does not re-assert its own direction inherits RTL. In English
// that reorders the bidi-neutral punctuation in
// `Round: What do you know?` — the reported `?what do you know :Round`.
//
// The assertion is the resolved ambient Directionality at the heading's text
// element, which is what decides that ordering. The exact-string finder in
// the same test pins that the string itself is never touched.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
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

Map<String, dynamic> _game({required int type, String? currentTurn}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': currentTurn ?? _localId,
      'isTimerStarted': true,
      'currentTimerValue': 30,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'س',
        'textEn': 'q',
        'type': 1,
        'maxCorrectAnswersCount': 23,
        'answers': [
          {'id': 10, 'text': 'ج', 'textEn': 'a'},
        ],
      },
      if (type == 2)
        'auctionGameMetadata': {
          'phase': 1,
          'currentScore': 0,
          'currentBid': 0,
          'answerTimeout': 8,
        },
    };

void main() {
  late ProviderContainer container;

  final en = PlayGameStrings.forLanguage(AppLanguage.english);
  final ar = PlayGameStrings.forLanguage(AppLanguage.arabic);

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
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> pumpRound(
    WidgetTester tester, {
    required String language,
    required int type,
    required Widget screen,
    String? currentTurn,
  }) async {
    await newContainer(language);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameRestore,
      _game(type: type, currentTurn: currentTurn),
    );
    await tester.pump();
    if (type == 2) {
      // Retire the bidding overlay so the panel underneath is reachable.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
    }
  }

  /// The direction the text is actually laid out in — the ambient
  /// Directionality at that element, which resolves the bidi run.
  TextDirection directionOf(WidgetTester tester, String text) =>
      Directionality.of(tester.element(find.text(text)));

  // The exact regression case, proven at the layout level rather than by
  // eyeballing a string: `Round: What do you know?` laid out RTL drags both
  // neutral characters to the wrong side.
  group('the bidi consequence being guarded against', () {
    double xOf(TextDirection direction, int start, int end) {
      final painter = TextPainter(
        text: TextSpan(text: en.roundHeading),
        textDirection: direction,
      )..layout();
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      expect(boxes, isNotEmpty);
      final x = boxes.first.left;
      painter.dispose();
      return x;
    }

    test('`Round: What do you know?` keeps its order under LTR and loses it '
        'under RTL', () {
      final heading = en.roundHeading;
      expect(heading, 'Round: What do you know?', reason: 'the exact case');

      final lastIndex = heading.length - 1;
      expect(heading[lastIndex], '?');

      final ltrQuestionMark = xOf(TextDirection.ltr, lastIndex, heading.length);
      final rtlQuestionMark = xOf(TextDirection.rtl, lastIndex, heading.length);

      expect(rtlQuestionMark, lessThan(ltrQuestionMark),
          reason: 'under RTL the trailing ? is dragged to the start of the '
              'line — the reported `?what do you know :Round`');
      expect(rtlQuestionMark, 0.0,
          reason: 'flush against the left edge');
    });
  });

  final rounds = <String, ({int type, Widget screen, String Function() enText,
      String Function() arText})>{
    'WDYK': (
      type: 1,
      screen: const WdykRoundScreen(),
      enText: () => en.roundHeading,
      arText: () => ar.roundHeading,
    ),
    'Auction': (
      type: 2,
      screen: const AuctionRoundScreen(),
      enText: () => en.auctionRoundHeading,
      arText: () => ar.auctionRoundHeading,
    ),
    'Bell': (
      type: 3,
      screen: const BellRoundScreen(),
      enText: () => en.bellRoundHeading,
      arText: () => ar.bellRoundHeading,
    ),
    'Comeback': (
      type: 4,
      screen: const ComeBackRoundScreen(),
      enText: () => en.comeBackRoundHeading,
      arText: () => ar.comeBackRoundHeading,
    ),
    'Breaker': (
      type: 5,
      screen: const BreakerRoundScreen(),
      enText: () => en.breakerRoundHeading,
      arText: () => ar.breakerRoundHeading,
    ),
  };

  for (final entry in rounds.entries) {
    final name = entry.key;
    final round = entry.value;

    group('$name — round heading direction follows the app language', () {
      testWidgets('the English heading is laid out LTR', (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.english,
          type: round.type,
          screen: round.screen,
        );

        final heading = round.enText();
        expect(find.text(heading), findsOneWidget,
            reason: 'the string itself is never altered');
        expect(directionOf(tester, heading), TextDirection.ltr);
      });

      testWidgets('the Arabic heading stays RTL', (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.arabic,
          type: round.type,
          screen: round.screen,
        );

        final heading = round.arText();
        expect(find.text(heading), findsOneWidget);
        expect(directionOf(tester, heading), TextDirection.rtl);
      });

      testWidgets('the heading bar keeps its RTL layout in English',
          (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.english,
          type: round.type,
          screen: round.screen,
        );

        // The count is end-positioned via PositionedDirectional against the
        // round's own RTL — that mirrored placement is deliberate and must
        // not follow the heading's text direction.
        expect(
          Directionality.of(tester.element(find.byType(RoundTitleBar))),
          TextDirection.rtl,
        );
      });
    });
  }

  // The remaining title/chrome surfaces that sit inside a round-level RTL
  // subtree. Audited alongside the heading bar so the sweep is complete.
  group('the other in-round title surfaces', () {
    testWidgets('Finish Round: the English ready title is laid out LTR',
        (tester) async {
      await newContainer(AppLanguage.english);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FinishRoundScreen())),
        ),
      );
      await tester.pump();

      expect(find.text(en.readyGameTitle), findsOneWidget);
      expect(directionOf(tester, en.readyGameTitle), TextDirection.ltr);
    });

    testWidgets('Finish Round: the Arabic ready title stays RTL',
        (tester) async {
      await newContainer(AppLanguage.arabic);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FinishRoundScreen())),
        ),
      );
      await tester.pump();

      expect(directionOf(tester, ar.readyGameTitle), TextDirection.rtl);
    });

    testWidgets('Auction: the English bidding-panel title is laid out LTR',
        (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.english,
        type: 2,
        screen: const AuctionRoundScreen(),
      );

      expect(find.text(en.auctionRoundTitle), findsOneWidget);
      expect(directionOf(tester, en.auctionRoundTitle), TextDirection.ltr);
    });

    testWidgets('Bell: the English bell-button title is laid out LTR',
        (tester) async {
      // The bell shows only while the race is on: armed, with no turn named
      // yet. A restore with a live countdown and an empty turn is exactly
      // that state.
      await pumpRound(
        tester,
        language: AppLanguage.english,
        type: 3,
        screen: const BellRoundScreen(),
        currentTurn: '',
      );

      expect(find.text(en.bellRoundTitle), findsOneWidget);
      expect(directionOf(tester, en.bellRoundTitle), TextDirection.ltr);
    });
  });

  group('WDYK heading — the exact reported regression', () {
    testWidgets('`Round: What do you know?` renders LTR, unmodified',
        (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.english,
        type: 1,
        screen: const WdykRoundScreen(),
      );

      // Character-for-character, punctuation included.
      expect(find.text('Round: What do you know?'), findsOneWidget);
      expect(
        directionOf(tester, 'Round: What do you know?'),
        TextDirection.ltr,
        reason: 'anything else renders it as `?what do you know :Round`',
      );
    });
  });
}

import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// In-round BODY text direction — the two surfaces the final read-only audit
// left outstanding. Distinct from game_text_direction_test.dart (server
// question/answer text) and game_heading_direction_test.dart (headings and
// titles): these are app-owned prose rendered inside the round's RTL
// subtree, each through its own bare AppTextView.
//
//   1. WDYK  `_passAlertUi`   — 'Warning! You can use\n…'  (leading `!`)
//   2. Auction `_biddingBottomUi` — '… in 30 seconds?'      (trailing `?`)
//
// The assertion is the resolved ambient Directionality at the text element,
// which is what decides the bidi ordering, plus a TextPainter check proving
// that direction really does move the punctuation.

const _localId = '47';
const _opponentId = '211403';

/// Mirrors `_AuctionRoundScreenState._answerTimeout`, which is what the
/// bidding panel passes into the prompt.
const _auctionAnswerTimeout = '30';

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

Map<String, dynamic> _game({required int type}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'isTimerStarted': true,
      'currentTimerValue': 30,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
          'passes': 1,
          'penalty': 2,
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

  Future<void> pumpRound(
    WidgetTester tester, {
    required String language,
    required int type,
    required Widget screen,
  }) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameRestore,
      _game(type: type),
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

  /// Left edge of the glyph at [index] when [text] is laid out in
  /// [direction]. This is what actually moves when the direction is wrong.
  double glyphLeft(String text, int index, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text),
      textDirection: direction,
    )..layout();
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    );
    expect(boxes, isNotEmpty);
    final left = boxes.first.left;
    painter.dispose();
    return left;
  }

  group('WDYK pass alert', () {
    // 'Warning! You can use\nthe pass button only once'
    final alert = en.passAlert;

    test('the exact string is the audited one and is never modified', () {
      expect(alert, 'Warning! You can use\nthe pass button only once');
      expect(alert[7], '!', reason: 'the neutral that moves');
    });

    test('bidi CHARACTERISATION: this `!` does NOT reorder — it is interior '
        'to an LTR run, so the defect here is alignment, not ordering', () {
      // Index 6 is the final `g` of `Warning`, index 7 the `!`. The `!` sits
      // between two strong LTR characters, so it takes their direction in
      // either paragraph direction — unlike a trailing neutral at a line
      // edge (see the Auction prompt below, which really does reorder).
      expect(glyphLeft(alert, 7, TextDirection.ltr),
          greaterThan(glyphLeft(alert, 6, TextDirection.ltr)));
      expect(glyphLeft(alert, 7, TextDirection.rtl),
          greaterThan(glyphLeft(alert, 6, TextDirection.rtl)),
          reason: 'still after `Warning` — `!Warning` does not occur for '
              'this particular string');
    });

    test('bidi: the real consequence is the line hugging the wrong edge', () {
      double firstGlyphLeft(TextDirection direction) {
        final painter = TextPainter(
          text: TextSpan(text: alert),
          textDirection: direction,
          textAlign: TextAlign.start,
        )..layout(maxWidth: 400);
        final boxes = painter.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        );
        expect(boxes, isNotEmpty);
        final left = boxes.first.left;
        painter.dispose();
        return left;
      }

      // `TextAlign.start` resolves against the paragraph direction, so under
      // RTL this English alert is pushed to the right-hand edge.
      expect(firstGlyphLeft(TextDirection.ltr), 0.0);
      expect(firstGlyphLeft(TextDirection.rtl), greaterThan(0.0),
          reason: 'RTL right-aligns the English alert');
    });

    testWidgets('English renders LTR, unmodified', (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.english,
        type: 1,
        screen: const WdykRoundScreen(),
      );

      expect(find.text(alert), findsOneWidget,
          reason: 'character-for-character, newline and `!` included');
      expect(directionOf(tester, alert), TextDirection.ltr,
          reason: 'anything else renders it as `!Warning`');
    });

    testWidgets('Arabic stays RTL', (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.arabic,
        type: 1,
        screen: const WdykRoundScreen(),
      );

      expect(find.text(ar.passAlert), findsOneWidget);
      expect(directionOf(tester, ar.passAlert), TextDirection.rtl);
    });
  });

  group('Auction bidding prompt', () {
    // 'How many answers can you answer in 30 seconds?'
    final prompt = en.howManyAnswersPrompt(_auctionAnswerTimeout);

    test('the exact generated string is the audited one and is unmodified',
        () {
      expect(prompt, 'How many answers can you answer in 30 seconds?');
      expect(prompt.endsWith('seconds?'), isTrue);
    });

    test('bidi: laying it out RTL drags the trailing `?` to the start', () {
      final last = prompt.length - 1;
      expect(prompt[last], '?');

      final ltrMark = glyphLeft(prompt, last, TextDirection.ltr);
      final rtlMark = glyphLeft(prompt, last, TextDirection.rtl);

      expect(rtlMark, lessThan(ltrMark),
          reason: 'RTL pulls the question mark to the left of the line');
      expect(rtlMark, 0.0, reason: 'flush against the left edge');
    });

    testWidgets('English renders LTR, unmodified', (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.english,
        type: 2,
        screen: const AuctionRoundScreen(),
      );

      expect(find.text(prompt), findsOneWidget);
      expect(directionOf(tester, prompt), TextDirection.ltr);
    });

    testWidgets('Arabic stays RTL', (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.arabic,
        type: 2,
        screen: const AuctionRoundScreen(),
      );

      final arabicPrompt = ar.howManyAnswersPrompt(_auctionAnswerTimeout);
      expect(find.text(arabicPrompt), findsOneWidget);
      expect(directionOf(tester, arabicPrompt), TextDirection.rtl);
    });
  });

  group('the round layout itself is untouched', () {
    testWidgets('WDYK still lays out RTL in English', (tester) async {
      await pumpRound(
        tester,
        language: AppLanguage.english,
        type: 1,
        screen: const WdykRoundScreen(),
      );

      // Read above the alert's own wrapper: the round chrome stays mirrored.
      expect(
        Directionality.of(tester.element(find.byType(WdykRoundScreen))),
        TextDirection.ltr,
        reason: 'outside the round root, this is the app-level direction',
      );
      expect(
        Directionality.of(tester.element(find.text(en.pass))),
        TextDirection.rtl,
        reason: 'a sibling in the same actions row keeps the round RTL — '
            'only the alert text re-anchors',
      );
    });
  });
}

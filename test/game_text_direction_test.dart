import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/round_background_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Game-provided text must be laid out in the direction of the app language:
// English LTR, Arabic RTL. The round screens deliberately force
// `Directionality(rtl)` at their root for the LAYOUT (mirrored rows, start/end
// padding), so any game text that does not re-assert its own direction
// inherits RTL — and in English that pushes trailing punctuation to the
// visual left: `what do you know?` renders as `?what do you know`.
//
// The assertion here is the resolved ambient Directionality at the text
// element, which is exactly what decides that bidi ordering. Asserting the
// string alone cannot catch it: the string is never modified either way, and
// this file pins that too.

const _localId = '47';
const _opponentId = '211403';

// Trailing punctuation is the whole point: `?` is bidi-neutral, so it is the
// character that visibly jumps when the paragraph direction is wrong.
const _questionEn = 'what do you know?';
const _questionAr = 'ماذا تعرف؟';
const _answerEn = 'answer one!';
const _answerAr = 'إجابة واحدة؟';

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

Map<String, dynamic> _questionJson() => {
      'id': 1,
      'text': _questionAr,
      'textEn': _questionEn,
      'type': 1,
      'maxCorrectAnswersCount': 23,
      'answers': [
        {'id': 10, 'text': _answerAr, 'textEn': _answerEn},
      ],
    };

Map<String, dynamic> _game({
  required int type,
  bool isTimerStarted = true,
  double currentTimerValue = 30,
  int auctionPhase = 1,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'isTimerStarted': isTimerStarted,
      'currentTimerValue': currentTimerValue,
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
      'currentQuestion': _questionJson(),
      if (type == 2)
        'auctionGameMetadata': {
          'phase': auctionPhase,
          'currentScore': 0,
          'currentBid': 0,
          'answerTimeout': 8,
        },
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
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
  }

  Future<void> settleOverlay(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump();
  }

  Future<void> timerUpdatedSeconds(WidgetTester tester, num seconds) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([seconds, 'g1']),
    );
    await tester.pump();
  }

  Future<void> nextQuestion(WidgetTester tester) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.nextQuestion,
      _questionJson(),
    );
    await tester.pump();
  }

  /// The direction the text is actually laid out in — the ambient
  /// Directionality at that text element, which is what resolves the bidi
  /// run and therefore where trailing punctuation lands.
  TextDirection directionOf(WidgetTester tester, String text) =>
      Directionality.of(tester.element(find.text(text)));

  /// Brings a round to the point where question and answer are both on screen.
  Future<void> pumpRound(
    WidgetTester tester, {
    required String language,
    required int type,
    required Widget screen,
  }) async {
    await newContainer(language);
    await mount(tester, screen);
    notifier().applySessionEvent(
      PlayGameHubEvents.gameRestore,
      _game(type: type),
    );
    await tester.pump();
    if (type == 2) {
      await settleOverlay(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();
    }
    await timerUpdatedSeconds(tester, 30);
    if (type == 4 || type == 5) {
      // Comeback/Breaker render only what NextQuestion delivers.
      await nextQuestion(tester);
    }
  }

  // Proves the property the round tests assert on is the one that actually
  // moves the glyph: laying `what do you know?` out RTL puts the trailing
  // `?` on the visual LEFT — the reported `?what do you know`. Without this,
  // a Directionality assertion would just be a property check.
  group('the bidi consequence being guarded against', () {
    double questionMarkX(TextDirection direction) {
      final painter = TextPainter(
        text: const TextSpan(text: _questionEn),
        textDirection: direction,
      )..layout();
      // The trailing '?' is the last character of the string.
      final boxes = painter.getBoxesForSelection(
        const TextSelection(
          baseOffset: _questionEn.length - 1,
          extentOffset: _questionEn.length,
        ),
      );
      expect(boxes, isNotEmpty);
      final x = boxes.first.left;
      painter.dispose();
      return x;
    }

    test('RTL puts the trailing ? on the left, LTR on the right', () {
      final ltrX = questionMarkX(TextDirection.ltr);
      final rtlX = questionMarkX(TextDirection.rtl);

      expect(rtlX, lessThan(ltrX),
          reason: 'this is exactly the reported defect: under RTL the '
              'question mark is dragged to the start of the line');
      expect(rtlX, 0.0,
          reason: 'flush against the left edge — `?what do you know`');
    });
  });

  final rounds = <String, ({int type, Widget screen})>{
    'WDYK': (type: 1, screen: const WdykRoundScreen()),
    'Auction': (type: 2, screen: const AuctionRoundScreen()),
    'Bell': (type: 3, screen: const BellRoundScreen()),
    'Comeback': (type: 4, screen: const ComeBackRoundScreen()),
    'Breaker': (type: 5, screen: const BreakerRoundScreen()),
  };

  for (final entry in rounds.entries) {
    final name = entry.key;
    final round = entry.value;

    group('$name — game text direction follows the app language', () {
      testWidgets('English question text is laid out LTR', (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.english,
          type: round.type,
          screen: round.screen,
        );

        expect(find.text(_questionEn), findsOneWidget,
            reason: 'the string itself is never altered');
        expect(directionOf(tester, _questionEn), TextDirection.ltr);
      });

      testWidgets('English answer text is laid out LTR', (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.english,
          type: round.type,
          screen: round.screen,
        );

        expect(find.text(_answerEn), findsOneWidget);
        expect(directionOf(tester, _answerEn), TextDirection.ltr);
      });

      testWidgets('Arabic question text stays RTL', (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.arabic,
          type: round.type,
          screen: round.screen,
        );

        expect(find.text(_questionAr), findsOneWidget);
        expect(directionOf(tester, _questionAr), TextDirection.rtl);
      });

      testWidgets('Arabic answer text stays RTL', (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.arabic,
          type: round.type,
          screen: round.screen,
        );

        expect(find.text(_answerAr), findsOneWidget);
        expect(directionOf(tester, _answerAr), TextDirection.rtl);
      });

      testWidgets('the round layout itself stays RTL in both languages',
          (tester) async {
        await pumpRound(
          tester,
          language: AppLanguage.english,
          type: round.type,
          screen: round.screen,
        );

        // The mirrored round chrome is deliberate and unchanged — only the
        // game-provided text re-asserts its own direction.
        expect(
          Directionality.of(tester.element(find.byType(RoundBackgroundImage))),
          TextDirection.rtl,
        );
      });
    });
  }
}

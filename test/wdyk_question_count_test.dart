import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A2 — questionNumber and roundTotalQuestionsCount are both nullable, so the
// WDYK header must never render the word "null". These assert the intended
// rendering, not the current implementation.

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

CurrentQuestion _question({int? number, int? total}) => CurrentQuestion(
      id: 1,
      type: 1,
      answers: const [],
      questionNumber: number,
      roundTotalQuestionsCount: total,
    );

Map<String, dynamic> _roundJson({int? number, int? total}) => {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q',
        'textEn': 'q',
        if (number != null) 'questionNumber': number,
        if (total != null) 'roundTotalQuestionsCount': total,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  group('CurrentQuestion.countLabel', () {
    test('both values present keep the existing format', () {
      expect(_question(number: 2, total: 2).countLabel, '2/2');
      expect(_question(number: 1, total: 5).countLabel, '1/5');
    });

    test('a missing question number yields no label', () {
      expect(_question(total: 5).countLabel, '');
    });

    test('a missing round total yields no label', () {
      expect(_question(number: 1).countLabel, '');
    });

    test('both missing yields no label', () {
      expect(_question().countLabel, '');
    });

    test('no combination can render the word null', () {
      for (final label in [
        _question(number: 2, total: 2).countLabel,
        _question(number: 1).countLabel,
        _question(total: 5).countLabel,
        _question().countLabel,
      ]) {
        expect(label, isNot(contains('null')));
      }
    });
  });

  group('WDYK header rendering', () {
    Future<void> pumpRound(
      WidgetTester tester, {
      int? number,
      int? total,
    }) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      final container = ProviderContainer(
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
          child: const MaterialApp(home: WdykRoundScreen()),
        ),
      );
      container.read(gameControllerProvider.notifier).applySessionEvent(
            PlayGameHubEvents.gameStarted,
            _roundJson(number: number, total: total),
          );
      await tester.pump();
    }

    testWidgets('both values present render the count', (tester) async {
      await pumpRound(tester, number: 2, total: 5);
      expect(find.text('2/5'), findsOneWidget);
    });

    testWidgets('a missing round total renders no null', (tester) async {
      await pumpRound(tester, number: 2);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('2/'), findsNothing);
    });

    testWidgets('a missing question number renders no null', (tester) async {
      await pumpRound(tester, total: 5);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('/5'), findsNothing);
    });

    testWidgets('both missing render no null', (tester) async {
      await pumpRound(tester);
      expect(find.textContaining('null'), findsNothing);
    });
  });
}

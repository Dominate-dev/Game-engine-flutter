import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/domain/game_mode.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The match's first question, delivered on GameStarted.
//
// docs/tasks/private-game-workflow.md §5 pins the contract: for private PvP
// the first question arrives *inside* the GameStarted payload — there is no
// NextQuestion behind it the way the public rounds have. GameStarted also
// always carries `status` 3, so it is _routeByStatus that routes it.
//
// Nothing in the suite covered that pairing for a private game before this
// file: the one existing GameStarted-with-question fixture
// (waiting_lobby_unsubscribe_test.dart) is a public lobby and asserts only
// that the lobby's listeners were torn down.

const _localId = '47';
const _opponentId = '211403';

const _questionAr = 'ما هو السؤال';
const _questionEn = 'what is the question';
const _answer1En = 'answer-one';
const _answer2En = 'answer-two';

class _FakeSignalRService extends SignalRService {
  @override
  bool get isConnected => true;

  @override
  bool get hasLiveConnection => true;

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

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
}

List<Map<String, dynamic>> _players() => [
      {
        'id': _localId,
        'playerName': 'guest',
        'makeupTryCount': 0,
        'maxMakeupTryCount': 3,
      },
      {
        'id': _opponentId,
        'playerName': 'host',
        'makeupTryCount': 0,
        'maxMakeupTryCount': 3,
      },
    ];

Map<String, dynamic> _question() => {
      'id': 501,
      'questionNumber': 1,
      'text': _questionAr,
      'textEn': _questionEn,
      'answers': [
        {'id': 10, 'text': 'إجابة-١', 'textEn': _answer1En},
        {'id': 11, 'text': 'إجابة-٢', 'textEn': _answer2En},
      ],
    };

/// The private lobby the guest sits in before both players are ready.
Map<String, dynamic> _privateLobby() => {
      'id': 'private-1',
      'status': 1,
      'mode': GameMode.privatePvp,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'gameCode': '4821',
      'currentTimerValue': 0,
      'players': _players(),
    };

/// `GameStarted` with the first question nested, as the contract describes:
/// a CreatedGame (status 3, type 1 = WDYK) carrying `currentQuestion`.
Map<String, dynamic> _startedNested() => {
      'id': 'private-1',
      'status': 3,
      'mode': GameMode.privatePvp,
      'type': 1,
      'groupId': 'grp',
      'isPrivate': true,
      'currentTimerValue': 0,
      'currentTurn': _localId,
      'currentQuestion': _question(),
      'players': _players(),
    };

/// The same event with the question's own fields at the payload root instead
/// of nested — the shape `_gameWithQuestionFromData` exists to tolerate.
Map<String, dynamic> _startedFlat() => {
      'id': 'private-1',
      'status': 3,
      'mode': GameMode.privatePvp,
      'type': 1,
      'groupId': 'grp',
      'isPrivate': true,
      'currentTimerValue': 0,
      ..._question(),
      'players': _players(),
    };

/// A public game reaching its first round, for the comparison.
Map<String, dynamic> _publicLobby() => {
      'id': 'public-1',
      'status': 2,
      'mode': 1,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': _players(),
    };

Map<String, dynamic> _publicStarted() => {
      'id': 'public-1',
      'status': 3,
      'mode': 1,
      'type': 1,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': _players(),
    };

void main() {
  late ProviderContainer container;

  GameController notifier() => container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  Future<void> newContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
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
        gameRepositoryProvider.overrideWithValue(_FakeGameRepository()),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  void expectQuestionAndAnswers({required String reason}) {
    final question = current().game?.currentQuestion;
    expect(question, isNotNull, reason: reason);
    expect(question!.displayText(isArabic: false), _questionEn, reason: reason);
    expect(question.displayText(isArabic: true), _questionAr, reason: reason);
    expect(question.answers, hasLength(2), reason: reason);
    expect(
      question.answers.map((a) => a.displayText(isArabic: false)).toList(),
      containsAll(<String>[_answer1En, _answer2En]),
      reason: reason,
    );
  }

  setUp(() async => newContainer());

  group('1. GameStarted carries the match into its first round', () {
    test('a nested currentQuestion survives the status routing', () {
      notifier().enterPrivateLobby();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _privateLobby(),
      );
      expect(current().phase, GamePhase.lobbyPrivate, reason: 'sanity');

      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _startedNested(),
      );

      expect(current().phase, GamePhase.wdyk);
      expectQuestionAndAnswers(
        reason: 'status 3 routes the event; the question must ride along',
      );
    });

    test('a root-level question payload survives it too', () {
      notifier().enterPrivateLobby();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _privateLobby(),
      );

      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _startedFlat(),
      );

      expect(current().phase, GamePhase.wdyk);
      expectQuestionAndAnswers(
        reason: 'the tolerant extractor is what this shape needs',
      );
    });

    test('routing is unchanged — status still decides the destination', () {
      notifier().enterPrivateLobby();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _privateLobby(),
      );

      // status 1 on a GameStarted is not a round, whatever the event is
      // called. _routeByStatus owns that decision and still does.
      notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
        ..._startedNested(),
        'status': 1,
      });

      expect(
        current().phase,
        GamePhase.lobbyPrivate,
        reason: 'a private waiting status routes to the private lobby, and '
            'the reorder must not have changed that',
      );
    });

    test('a GameStarted with no question leaves the previous one alone', () {
      notifier().enterPrivateLobby();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _privateLobby(),
      );
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _startedNested(),
      );

      notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
        'id': 'private-1',
        'status': 3,
        'type': 1,
        'groupId': 'grp',
        'players': _players(),
      });

      expectQuestionAndAnswers(
        reason: 'nothing is cleared by a payload that simply omits it',
      );
    });
  });

  group('2. the public flow is untouched', () {
    test('a public GameStarted still routes by status', () {
      notifier().enterWaiting();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _publicLobby(),
      );
      expect(current().phase, GamePhase.lobbyPlay, reason: 'sanity');

      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _publicStarted(),
      );

      expect(current().phase, GamePhase.wdyk);
    });

    test('and NextQuestion still delivers the question there', () {
      notifier().enterWaiting();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _publicLobby(),
      );
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _publicStarted(),
      );
      expect(
        current().game?.currentQuestion,
        isNull,
        reason: 'the public GameStarted carries none — that is its contract',
      );

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextQuestion,
        _question(),
      );

      expectQuestionAndAnswers(reason: 'the public path is unchanged');
    });
  });

  group('3. the round screen actually renders it', () {
    testWidgets('the private round shows the question and both answers',
        (tester) async {
      notifier().enterPrivateLobby();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _privateLobby(),
      );
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _startedNested(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WdykRoundScreen()),
        ),
      );
      await tester.pump();
      // Answering opens only once a countdown is running (shared rule).
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([30, 'private-1']),
      );
      await tester.pump();

      expect(find.text(_questionEn), findsOneWidget);
      expect(find.text(_answer1En), findsOneWidget);
      expect(find.text(_answer2En), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

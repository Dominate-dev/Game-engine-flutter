import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-2 — bidding state, guards and dispatch.
//
// Confirmed shapes: PlayerBidded {playerId, bidValue}, ChangeTurn
// [playerId, gameId]. isBiding (who bid last) and isMyTurn (ChangeTurn) are
// separate gates, and nothing here moves the phase locally.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  /// Drives invoke()'s return the way a disconnected hub would.
  bool connected = true;

  List<({String method, List<Object?>? args})> get bids =>
      invocations.where((i) => i.method == PlayGameHubEvents.bid).toList();

  List<({String method, List<Object?>? args})> get passes =>
      invocations.where((i) => i.method == PlayGameHubEvents.pass).toList();

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    if (!connected) {
      return false;
    }
    invocations.add((method: methodName, args: args));
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

  void emit(String name, Map<String, dynamic>? data) {
    _events.add(GameHubEvent(name: name, data: data));
  }

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

Map<String, dynamic> _auctionGame({
  String currentTurn = _localId,
  int? maxCorrectAnswersCount = 23,
  int? metadataBid,
  int phase = 1,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 2,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        if (maxCorrectAnswersCount != null)
          'maxCorrectAnswersCount': maxCorrectAnswersCount,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
      'auctionGameMetadata': {
        'phase': phase,
        'currentScore': 0,
        'currentBid': metadataBid ?? 0,
        'answerTimeout': 8,
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;
  late _FakeSignalRService signalR;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    bindings = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  Future<void> enterAuction({
    String currentTurn = _localId,
    int? maxCorrectAnswersCount = 23,
    int? metadataBid,
    int phase = 1,
  }) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _auctionGame(
        currentTurn: currentTurn,
        maxCorrectAnswersCount: maxCorrectAnswersCount,
        metadataBid: metadataBid,
        phase: phase,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> bidded(String playerId, int bidValue) async {
    bindings.emit(
      PlayGameHubEvents.playerBidded,
      {'playerId': playerId, 'bidValue': bidValue},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> changeTurn(String playerId) async {
    bindings.emit(
      PlayGameHubEvents.changeTurn,
      {'arg0': playerId, 'arg1': 'g1'},
    );
    await Future<void>.delayed(Duration.zero);
  }

  group('PlayerBidded updates the current bid', () {
    test('the bid value becomes the standing bid', () async {
      await enterAuction();
      expect(current().currentBid, isNull);

      await bidded(_opponentId, 4);

      expect(current().currentBid, 4);
    });

    test('my own bid closes my raise, the opponent bid reopens it', () async {
      await enterAuction();
      expect(current().isBiding, isTrue);

      await bidded(_localId, 3);
      expect(current().isBiding, isFalse, reason: 'I bid last');

      await bidded(_opponentId, 5);
      expect(current().isBiding, isTrue, reason: 'they raised, I may reply');
      expect(current().currentBid, 5);
    });

    test('a raise war always shows the latest value', () async {
      await enterAuction();
      await bidded(_localId, 2);
      await bidded(_opponentId, 3);
      await bidded(_localId, 6);

      expect(current().currentBid, 6);
    });

    test('it never touches the turn', () async {
      await enterAuction(currentTurn: _opponentId);
      await bidded(_opponentId, 3);

      expect(current().isMyTurn, isFalse, reason: 'ChangeTurn owns the turn');
      expect(current().game?.currentTurn, _opponentId);
    });

    test('an unseated bidder leaves isBiding alone', () async {
      await enterAuction();
      await bidded(_localId, 2);
      expect(current().isBiding, isFalse);

      await bidded('999', 4);

      expect(current().currentBid, 4, reason: 'the bid is still the bid');
      expect(current().isBiding, isFalse, reason: 'no side may be guessed');
    });

    test('a payload missing playerId or bidValue changes nothing', () async {
      await enterAuction();
      bindings.emit(PlayGameHubEvents.playerBidded, {'bidValue': 4});
      bindings.emit(PlayGameHubEvents.playerBidded, {'playerId': _localId});
      await Future<void>.delayed(Duration.zero);

      expect(current().currentBid, isNull);
      expect(current().isBiding, isTrue);
    });

    test('a new bidding phase clears the bid and reopens raising', () async {
      await enterAuction();
      await bidded(_localId, 5);
      expect(current().currentBid, 5);
      expect(current().isBiding, isFalse);

      bindings.emit(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().currentBid, isNull);
      expect(current().isBiding, isTrue);
    });
  });

  group('picker bounds', () {
    test('minimum is 1 when nobody has bid', () async {
      await enterAuction();
      expect(notifier().auctionMinBid, 1);
    });

    test('minimum is one above the standing bid', () async {
      await enterAuction();
      await bidded(_opponentId, 7);
      expect(notifier().auctionMinBid, 8);
    });

    test('maximum is the question answer count', () async {
      await enterAuction(maxCorrectAnswersCount: 23);
      expect(notifier().auctionMaxBid, 23);
    });

    test('maximum is null when the server sent no answer count', () async {
      await enterAuction(maxCorrectAnswersCount: null);
      expect(notifier().auctionMaxBid, isNull,
          reason: 'no ceiling is invented');
    });

    test('restored metadata sets the minimum', () async {
      await enterAuction(metadataBid: 9);
      expect(current().currentBid, 9);
      expect(notifier().auctionMinBid, 10);
    });

    test('a metadata bid of 0 means nobody has bid', () async {
      await enterAuction(metadataBid: 0);
      expect(current().currentBid, isNull);
      expect(notifier().auctionMinBid, 1);
    });
  });

  group('Bid guard', () {
    test('a valid raise on my turn dispatches', () async {
      await enterAuction();
      final sent = await notifier().bid(3);

      expect(sent, isTrue);
      expect(signalR.bids, hasLength(1));
      expect(signalR.bids.single.args, [
        {'gameId': 'g1', 'bidValue': 3},
      ]);
    });

    test('it is blocked when it is not my turn', () async {
      await enterAuction(currentTurn: _opponentId);
      expect(notifier().canBid, isFalse);
      expect(await notifier().bid(3), isFalse);
      expect(signalR.bids, isEmpty);
    });

    test('it is blocked while I am the standing bidder', () async {
      await enterAuction();
      await bidded(_localId, 3);

      expect(notifier().canBid, isFalse, reason: 'isBiding is closed');
      expect(await notifier().bid(4), isFalse);
      expect(signalR.bids, isEmpty);
    });

    test('a bid at or below the standing bid is refused', () async {
      await enterAuction();
      await bidded(_opponentId, 5);

      expect(await notifier().bid(5), isFalse);
      expect(await notifier().bid(4), isFalse);
      expect(await notifier().bid(6), isTrue);
      expect(signalR.bids, hasLength(1));
    });

    test('a bid above the answer count is refused', () async {
      await enterAuction(maxCorrectAnswersCount: 8);

      expect(await notifier().bid(9), isFalse);
      expect(await notifier().bid(8), isTrue);
      expect(signalR.bids, hasLength(1));
    });

    test('with no answer count only the minimum applies', () async {
      await enterAuction(maxCorrectAnswersCount: null);

      expect(await notifier().bid(0), isFalse);
      expect(await notifier().bid(99), isTrue);
    });

    test('a failed dispatch reports false and sends nothing', () async {
      await enterAuction();
      signalR.connected = false;

      expect(await notifier().bid(3), isFalse);
      expect(signalR.bids, isEmpty);
    });
  });

  group('Take Turn guard', () {
    test('it is blocked until someone has bid', () async {
      await enterAuction();

      expect(notifier().canTakeTurn, isFalse);
      expect(await notifier().takeTurn(), isFalse);
      expect(signalR.passes, isEmpty);
    });

    test('it is blocked when it is not my turn', () async {
      await enterAuction(currentTurn: _opponentId);
      await bidded(_opponentId, 3);

      expect(notifier().canTakeTurn, isFalse);
      expect(await notifier().takeTurn(), isFalse);
      expect(signalR.passes, isEmpty);
    });

    test('it dispatches Pass(gameId) once a bid stands on my turn', () async {
      await enterAuction();
      await bidded(_opponentId, 3);

      expect(notifier().canTakeTurn, isTrue);
      expect(await notifier().takeTurn(), isTrue);
      expect(signalR.passes, hasLength(1));
      expect(signalR.passes.single.args, ['g1']);
    });

    test('it becomes available after ChangeTurn hands me the turn', () async {
      await enterAuction(currentTurn: _opponentId);
      await bidded(_opponentId, 3);
      expect(notifier().canTakeTurn, isFalse);

      await changeTurn(_localId);

      expect(notifier().canTakeTurn, isTrue);
    });

    test('it ignores the WDYK pass budget entirely', () async {
      // No passes, no penalties: the WDYK gate would refuse, auction must not.
      await enterAuction();
      await bidded(_opponentId, 2);

      expect(current().me?.passes ?? 0, 0);
      expect(current().me?.penalty ?? 0, 0);
      expect(await notifier().takeTurn(), isTrue);
      expect(await notifier().pass(), isFalse,
          reason: 'the WDYK guard is untouched');
    });
  });

  group('no optimistic transition', () {
    test('Take Turn leaves the phase and the bid alone', () async {
      await enterAuction();
      await bidded(_opponentId, 4);
      final before = current();

      await notifier().takeTurn();

      final after = current();
      expect(after.auctionPhase, before.auctionPhase);
      expect(after.auctionPhase, AuctionPhase.bidding);
      expect(after.currentBid, 4);
      expect(after.answeringPlayerId, isNull);
      expect(after.goalScore, isNull);
    });

    test('only AuctionAnswerPhaseStarted moves the phase', () async {
      await enterAuction();
      await bidded(_opponentId, 4);
      await notifier().takeTurn();
      expect(current().auctionPhase, AuctionPhase.bidding);

      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _opponentId, 'bidValue': 4},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionPhase, AuctionPhase.answering);
      expect(current().answeringPlayerId, _opponentId);
      expect(current().goalScore, 4);
    });

    test('Bid does not move the phase either', () async {
      await enterAuction();
      await notifier().bid(2);

      expect(current().auctionPhase, AuctionPhase.bidding);
      expect(current().currentBid, isNull,
          reason: 'PlayerBidded is the confirmation, not the tap');
      expect(current().isBiding, isTrue, reason: 'not flipped locally');
    });

    test('a dispatched bid does not disturb the timer', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        {'arg0': 10, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      await notifier().bid(2);
      await notifier().takeTurn();

      expect(current().game?.currentTimerValue, 10);
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'still running: the countdown TimerUpdatedSeconds started is '
              'left exactly as it was — a bid never resolves anything');
    });
  });
}

part of 'game_controller.dart';

// Auction (round 2) state reduction.
//
// Confirmed payload shapes — A-0 spec lock:
//   AuctionBiddingPhaseStarted     [gameId]                     (no playerId)
//   AuctionAnswerPhaseStarted      {playerId, bidValue}
//   AuctionAnswerPhaseScoreUpdate  {playerId, currentScore, goalScore,
//                                   wrongScore}
//   PlayerWonAuctionRound          [playerId, gameId]
//   PlayerLostAuctionRound         [playerId, gameId]
//   Penalty                        {playerId, type}
//
// Reduction is order-independent, and every auction value is server-sent —
// the client derives none of its own, and never infers an outcome from a
// penalty or a wrong count.
extension AuctionRoundHandler on GameController {
  void applyAuctionEvent(String name, Map<String, dynamic>? data) {
    switch (name) {
      case PlayGameHubEvents.auctionBiddingPhaseStarted:
        _applyBiddingPhaseStarted(data);
      case PlayGameHubEvents.playerBidded:
        _applyPlayerBidded(data);
      case PlayGameHubEvents.auctionAnswerPhaseStarted:
        _applyAnswerPhaseStarted(data);
      case PlayGameHubEvents.auctionAnswerPhaseScoreUpdate:
        _applyScoreUpdate(data);
      case PlayGameHubEvents.playerWonAuctionRound:
        _applyAuctionOutcome(name, data, AuctionResult.won);
      case PlayGameHubEvents.playerLostAuctionRound:
        _applyAuctionOutcome(name, data, AuctionResult.lost);
    }
  }

  // Carries no playerId, so it says nothing about whose turn it is — that
  // stays with ChangeTurn.
  void _applyBiddingPhaseStarted(Map<String, dynamic>? data) {
    _s = _s.copyWith(
      data: data,
      lastEventName: PlayGameHubEvents.auctionBiddingPhaseStarted,
      auctionPhase: AuctionPhase.bidding,
      isBiding: true,
      answersUnlocked: false,
      clearAuctionAnswer: true,
      clearAuctionBid: true,
    );
  }

  // The bidder decides only whether *this* player may still raise. It never
  // seats a player and never touches the turn; an id naming neither seat
  // leaves isBiding alone rather than guessing a side.
  void _applyPlayerBidded(Map<String, dynamic>? data) {
    final playerId = GameSessionReducer.playerIdFrom(data);
    final bidValue = _auctionInt(data, 'bidValue');
    if (playerId == null || bidValue == null) {
      _logAuctionPayload(
        PlayGameHubEvents.playerBidded,
        data,
        'playerId or bidValue missing',
      );
      return;
    }
    bool? nextIsBiding;
    if (isCurrentUser(playerId)) {
      nextIsBiding = false;
    } else {
      final opponent = _s.opponent;
      if (opponent != null && opponent.matchesHubUserId(playerId)) {
        nextIsBiding = true;
      } else {
        _logUnseatedPlayer(PlayGameHubEvents.playerBidded, playerId);
      }
    }
    _s = _s.copyWith(
      data: data,
      lastEventName: PlayGameHubEvents.playerBidded,
      currentBid: bidValue,
      isBiding: nextIsBiding,
    );
  }

  // Names the only player who may answer, and the bid they must reach.
  void _applyAnswerPhaseStarted(Map<String, dynamic>? data) {
    final playerId = GameSessionReducer.playerIdFrom(data);
    final bidValue = _auctionInt(data, 'bidValue');
    if (playerId == null || bidValue == null) {
      _logAuctionPayload(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        data,
        'playerId or bidValue missing',
      );
      return;
    }
    _logUnseatedPlayer(PlayGameHubEvents.auctionAnswerPhaseStarted, playerId);
    _s = _s.copyWith(
      data: data,
      lastEventName: PlayGameHubEvents.auctionAnswerPhaseStarted,
      auctionPhase: AuctionPhase.answering,
      answeringPlayerId: playerId,
      goalScore: bidValue,
      // The new answer phase waits for its own TimerUpdatedSeconds.
      answersUnlocked: false,
    );
  }

  // Applied whichever player it names and regardless of the phase already
  // recorded, so a score arriving before the phase event is not lost.
  // wrongScore is authoritative; the client never counts penalties.
  void _applyScoreUpdate(Map<String, dynamic>? data) {
    final currentScore = _auctionInt(data, 'currentScore');
    final goalScore = _auctionInt(data, 'goalScore');
    final wrongScore = _auctionInt(data, 'wrongScore');
    if (currentScore == null && goalScore == null && wrongScore == null) {
      _logAuctionPayload(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        data,
        'no score fields resolved',
      );
      return;
    }
    final playerId = GameSessionReducer.playerIdFrom(data);
    if (playerId != null) {
      _logUnseatedPlayer(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        playerId,
      );
    }
    // Reaching the goal ends the answer phase, so the countdown freezes with
    // it. Compared against the merged values, not just this payload, since a
    // partial update may carry only one of the two.
    final nextCurrent = currentScore ?? _s.currentScore;
    final nextGoal = goalScore ?? _s.goalScore;
    final goalReached =
        nextCurrent != null && nextGoal != null && nextCurrent >= nextGoal;
    _s = _s.copyWith(
      data: data,
      lastEventName: PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
      currentScore: currentScore,
      goalScore: goalScore,
      wrongScore: wrongScore,
      game: goalReached ? _frozenTimerGame() : null,
    );
  }

  // Never rewrites currentTimerValue — a stop is a freeze, as everywhere else.
  CreatedGame? _frozenTimerGame() =>
      _s.game?.copyWith(isTimerStarted: false);

  // The result is recorded as sent — never inverted for the other player, and
  // never inferred from a penalty.
  void _applyAuctionOutcome(
    String name,
    Map<String, dynamic>? data,
    AuctionResult result,
  ) {
    final playerId = GameSessionReducer.playerIdFrom(data);
    if (playerId == null) {
      _logAuctionPayload(name, data, 'playerId missing');
      return;
    }
    _logUnseatedPlayer(name, playerId);
    _s = _s.copyWith(
      data: data,
      lastEventName: name,
      auctionResult: result,
      answersUnlocked: false,
      // A terminal outcome ends the answer phase, so the countdown freezes.
      game: _frozenTimerGame(),
    );
  }

  // Validation only — the loss threshold is unknown and
  // PlayerLostAuctionRound is the authoritative outcome, so this changes no
  // auction state. Penalty itself is reduced by applySharedRoundEvent.
  void _validateAuctionPenalty(Map<String, dynamic>? data) {
    final playerId = GameSessionReducer.playerIdFrom(data);
    final type = TypePenalty.fromId(
      JsonValue.parseInt(JsonValue.field(data ?? const {}, 'type')),
    );
    if (playerId == null || type == null) {
      _logAuctionPayload(
        PlayGameHubEvents.penalty,
        data,
        'playerId or type unresolved',
      );
      return;
    }
    _logUnseatedPlayer(PlayGameHubEvents.penalty, playerId);
  }

  // The metadata carries no goal, so that is not reconstructed here —
  // AuctionAnswerPhaseScoreUpdate stays its only source. Nothing here touches
  // the countdown: a restore never starts or resets it (A-5).
  void _applyAuctionMetadata(CreatedGame? game) {
    final metadata = game?.auctionGameMetadata;
    if (metadata == null) {
      return;
    }
    final phase = AuctionPhase.fromId(metadata.phase);
    if (phase == null) {
      _logAuctionPayload(
        PlayGameHubEvents.gameRestore,
        <String, dynamic>{'phase': metadata.phase},
        'unknown auction phase',
      );
    }
    // A bid is at least 1 (the picker floor), so 0 is "nobody has bid", which
    // must stay null or Take Turn would look available.
    final restoredBid = metadata.currentBid > 0 ? metadata.currentBid : null;

    final latestBidder = metadata.latestBidder?.trim() ?? '';
    // Strict matching, as everywhere else: an id naming neither seat is logged
    // and changes nothing.
    final bidderIsMine =
        latestBidder.isEmpty ? null : _isMinePlayerId(latestBidder);
    if (latestBidder.isNotEmpty && bidderIsMine == null) {
      _logAuctionPayload(
        PlayGameHubEvents.gameRestore,
        <String, dynamic>{'latestBidder': latestBidder},
        'latestBidder names neither player',
      );
    }

    // The standing bidder cannot raise their own bid — the same rule the live
    // PlayerBidded path applies, reapplied to the restored roster.
    final isBiding =
        (bidderIsMine != null && restoredBid != null) ? !bidderIsMine : null;

    _s = _s.copyWith(
      auctionPhase: phase,
      currentScore: metadata.currentScore,
      // The same single field AuctionAnswerPhaseScoreUpdate writes — no second
      // counter. A payload without it passes null, which keeps what is held.
      wrongScore: metadata.wrongScore,
      currentBid: restoredBid,
      isBiding: isBiding,
      answeringPlayerId: _restoredAnsweringPlayerId(
        phase,
        latestBidder,
        bidderIsMine,
      ),
    );
  }

  // The metadata names no answering player, so this combines the two confirmed
  // rules: Take Turn hands the question to the last bidder, and
  // AuctionAnswerPhaseStarted names that same player. A live
  // AuctionAnswerPhaseStarted always wins.
  String? _restoredAnsweringPlayerId(
    AuctionPhase? phase,
    String latestBidder,
    bool? bidderIsMine,
  ) {
    if (phase != AuctionPhase.answering ||
        bidderIsMine == null ||
        _s.answeringPlayerId != null) {
      return null;
    }
    return latestBidder;
  }

  int get auctionMinBid => (_s.currentBid ?? 0) + 1;

  // Null when the server has not sent one; the caller decides the fallback
  // rather than inventing a ceiling here.
  int? get auctionMaxBid => _s.game?.currentQuestion?.maxCorrectAnswersCount;

  // Answering ownership is not isMyTurn: nothing establishes that ChangeTurn
  // stays authoritative once the answer phase begins, so the player named by
  // AuctionAnswerPhaseStarted is the only source used.
  bool get isAuctionAnswerer {
    final playerId = _s.answeringPlayerId;
    return playerId != null && isCurrentUser(playerId);
  }

  // Strict matching — null when the id names neither seat, never by
  // elimination.
  GamePlayer? get auctionAnsweringPlayer {
    final playerId = _s.answeringPlayerId;
    if (playerId == null) {
      return null;
    }
    for (final player in [_s.me, _s.opponent]) {
      if (player != null && player.matchesHubUserId(playerId)) {
        return player;
      }
    }
    return null;
  }

  // Both counters come from the roster on GameUpdated; the client never
  // increments them. A maxMakeupTryCount of 0 means the server sent no limit,
  // which leaves selection open rather than locking on a missing value.
  bool get isAuctionWrongLimitReached {
    final player = auctionAnsweringPlayer;
    if (player == null || player.maxMakeupTryCount <= 0) {
      return false;
    }
    return player.makeupTryCount >= player.maxMakeupTryCount;
  }

  bool get canSubmitAuctionAnswer =>
      isAuctionAnswerer && !isAuctionWrongLimitReached;

  // Returns whether the call was dispatched, never whether the answer was
  // right — AuctionAnswerPhaseScoreUpdate is the confirmation. Unlike every
  // other round, a correct *or* wrong Auction answer both leave the countdown
  // running (see _eventStopsTimer); only a timeout Penalty, reaching the goal,
  // or a PlayerWon/LostAuctionRound outcome stops it.
  Future<bool> submitAuctionAnswer(int answerId) async {
    if (!canSubmitAuctionAnswer) {
      return false;
    }
    final gameId = _s.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.submitAnswer} (auction) | '
      'gameId: $gameId | answerId: $answerId',
    );
    return ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.submitAnswer,
          args: [gameId, answerId],
        );
  }

  bool get canBid => _s.isBiding && _s.isMyTurn;

  bool get canTakeTurn => _s.currentBid != null && _s.isMyTurn;

  // Returns whether the call was dispatched, never whether the server accepted
  // it — PlayerBidded is the confirmation.
  Future<bool> bid(int bidValue) async {
    final max = auctionMaxBid;
    if (!canBid ||
        bidValue < auctionMinBid ||
        (max != null && bidValue > max)) {
      return false;
    }
    final gameId = _s.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.bid} | '
      'gameId: $gameId | bidValue: $bidValue',
    );
    return ref.read(signalRServiceProvider).invoke(
      PlayGameHubEvents.bid,
      args: [
        {'gameId': gameId, 'bidValue': bidValue},
      ],
    );
  }

  // Separate from GameController.pass on purpose: that one is gated on the
  // WDYK pass budget and penalties, which do not apply here. Nothing local
  // changes on success — the phase moves only on AuctionAnswerPhaseStarted.
  Future<bool> takeTurn() async {
    if (!canTakeTurn) {
      return false;
    }
    final gameId = _s.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.pass} (auction) | '
      'gameId: $gameId',
    );
    return ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.pass,
          args: [gameId],
        );
  }

  int? _auctionInt(Map<String, dynamic>? data, String field) {
    if (data == null) {
      return null;
    }
    return JsonValue.parseInt(JsonValue.field(data, field));
  }

  // Positive matching only: an id naming neither seat is logged, never
  // assigned to a player by elimination.
  void _logUnseatedPlayer(String event, String playerId) {
    if (isCurrentUser(playerId)) {
      return;
    }
    final opponent = _s.opponent;
    if (opponent != null && opponent.matchesHubUserId(playerId)) {
      return;
    }
    AppLogger.log(
      'GameController — $event names an unseated player | playerId: $playerId',
    );
  }

  void _logAuctionPayload(String event, Map<String, dynamic>? data, String why) {
    AppLogger.log('GameController — $event $why | data: $data');
  }
}

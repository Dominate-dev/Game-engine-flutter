import 'auction_phase.dart';
import 'game_phase.dart';
import '../features/games/domain/entities/created_game.dart';
import '../features/games/domain/entities/game_over_result.dart';
import '../features/games/domain/entities/game_player.dart';
import '../features/games/domain/entities/game_result_player.dart';

class PlayerEmote {
  const PlayerEmote({
    required this.playerId,
    this.imageUrl,
  });

  final String playerId;
  final String? imageUrl;
}

class GameSessionState {
  const GameSessionState({
    required this.phase,
    this.result,
    this.data,
    this.lastEventName,
    this.game,
    this.gameOver,
    this.readyTimerStopped = false,
    this.meEmote,
    this.opponentEmote,
    this.me,
    this.opponent,
    this.readyTimerPlayerId,
    this.opponentReadyPulse = 0,
    this.opponentCardPulse = 0,
    this.auctionPhase,
    this.currentBid,
    this.isBiding = true,
    this.answeringPlayerId,
    this.goalScore,
    this.currentScore,
    this.wrongScore,
    this.auctionResult = AuctionResult.none,
    this.answersUnlocked = false,
    this.bellArmed = false,
    this.comebackAnswerLocked = false,
  });

  factory GameSessionState.initial() =>
      const GameSessionState(phase: GamePhase.waiting);

  final GamePhase phase;
  final GameResult? result;
  final Map<String, dynamic>? data;
  final String? lastEventName;
  final CreatedGame? game;
  final GameOverResult? gameOver;
  final bool readyTimerStopped;
  final PlayerEmote? meEmote;
  final PlayerEmote? opponentEmote;
  final GamePlayer? me;
  final GamePlayer? opponent;
  final String? readyTimerPlayerId;
  final int opponentReadyPulse;
  /// Throb player-two's card when I become ready and they are not.
  final int opponentCardPulse;

  // Auction (round 2). All server-reported; the client derives none of them.
  /// `null` until the server reports a phase this client recognises.
  final AuctionPhase? auctionPhase;

  /// Highest bid so far — PlayerBidded live, auctionGameMetadata on restore.
  /// `null` means nobody has bid yet, which is what disables Take Turn.
  final int? currentBid;

  /// Whether this player may still raise. Distinct from [isMyTurn]: the turn
  /// comes from ChangeTurn, this from who bid last.
  final bool isBiding;

  /// Named by `AuctionAnswerPhaseStarted` — the only player who may answer.
  final String? answeringPlayerId;

  /// Target for the answering player: the winning bid.
  final int? goalScore;
  final int? currentScore;

  /// Authoritative wrong count from `AuctionAnswerPhaseScoreUpdate`; the
  /// client never counts penalties itself.
  final int? wrongScore;

  final AuctionResult auctionResult;

  /// Whether answer selection is open, for every round.
  ///
  /// Only a TimerUpdatedSeconds carrying time opens it; a question, its
  /// answers and TimeStarted do not. It closes when the countdown runs out
  /// and at every boundary that ends an answering phase.
  final bool answersUnlocked;

  // Bell (round 3). Client-derived only — there is no server-sent phase or
  // metadata to restore, unlike Auction.
  /// Whether the Bell button is armed — true from `TimeStarted` (with no
  /// turn yet) until a `ChangeTurn`, `Penalty`, `NextQuestion` or a restore
  /// consumes the race. Distinct from visibility: [BellPhase.racing]
  /// (`bellArmed` with no turn) is what makes Bell actually show.
  final bool bellArmed;

  // Comeback (round 4). Client-derived, like bellArmed: Penalty(timeout)
  // locks answering — server-side attempt limits alone do not cover a
  // timeout — and only a genuine new question clears it (see
  // GameController._applyNextQuestion). Not restored from a snapshot: no
  // server field reports "was locked at timeout", so GameRestore always
  // comes back unlocked.
  /// Whether Comeback answering is locked out by a timeout, independent of
  /// [GamePlayer.makeupTryCount]/[GamePlayer.maxMakeupTryCount].
  final bool comebackAnswerLocked;

  /// Me vs opponent points — e.g. `1-0`.
  String get scoreLabel => '${me?.points ?? 0}-${opponent?.points ?? 0}';

  /// This device's end-of-game result row from `GameOver.gameResultPlayers`,
  /// matched by identity (not array order) via [GamePlayer.matchesHubUserId]
  /// — the same mechanism [isMyTurn] uses. `null` when the game has not
  /// ended, [me] is not yet seated, or the server did not name this player.
  GameResultPlayer? get myResult => _resultPlayerFor(me);

  /// The opponent's end-of-game result row, resolved the same way.
  GameResultPlayer? get opponentResult => _resultPlayerFor(opponent);

  /// The roster player (not a `GameResultPlayer`) named by `GameOver.winnerId`
  /// — real payloads leave `GameResultPlayer.playerName`/`profileImageUrl`
  /// empty, so display identity comes from the roster, matched by
  /// [GamePlayer.matchesHubUserId], never assumed to be [me]. `null` when
  /// there is no gameOver, no winnerId, or it names neither seated player —
  /// callers fall back to whichever side their own result dialog implies.
  GamePlayer? get winnerPlayer {
    final winnerId = gameOver?.winnerId;
    if (winnerId == null || winnerId.trim().isEmpty) {
      return null;
    }
    if (me != null && me!.matchesHubUserId(winnerId)) {
      return me;
    }
    if (opponent != null && opponent!.matchesHubUserId(winnerId)) {
      return opponent;
    }
    return null;
  }

  GameResultPlayer? _resultPlayerFor(GamePlayer? player) {
    if (player == null) {
      return null;
    }
    final players = gameOver?.gameResultPlayers;
    if (players == null || players.isEmpty) {
      return null;
    }
    for (final candidate in players) {
      if (player.matchesHubUserId(candidate.playerId)) {
        return candidate;
      }
    }
    return null;
  }

  bool get isMyTurn => _mayAct(me);

  bool get isOpponentTurn => _mayAct(opponent);

  // Turn resolution, not identity: ALLOW_ALL lets both players act, a player
  // id lets only that player act, and anything else lets neither.
  bool _mayAct(GamePlayer? player) {
    final turn = game?.currentTurn?.trim() ?? '';
    if (turn.isEmpty || player == null) {
      return false;
    }
    if (turn == CreatedGame.allowAllTurn) {
      return true;
    }
    return player.matchesHubUserId(turn);
  }

  GameSessionState copyWith({
    GamePhase? phase,
    GameResult? result,
    Map<String, dynamic>? data,
    String? lastEventName,
    CreatedGame? game,
    GameOverResult? gameOver,
    bool? readyTimerStopped,
    PlayerEmote? meEmote,
    PlayerEmote? opponentEmote,
    GamePlayer? me,
    GamePlayer? opponent,
    String? readyTimerPlayerId,
    int? opponentReadyPulse,
    int? opponentCardPulse,
    AuctionPhase? auctionPhase,
    int? currentBid,
    bool? isBiding,
    String? answeringPlayerId,
    int? goalScore,
    int? currentScore,
    int? wrongScore,
    AuctionResult? auctionResult,
    bool? answersUnlocked,
    bool? bellArmed,
    bool? comebackAnswerLocked,
    /// Drops everything the answer phase produced — used when a new bidding
    /// phase starts, so a stale score cannot survive into the next question.
    bool clearAuctionAnswer = false,
    /// Drops the bid so a new bidding phase starts from nothing.
    bool clearAuctionBid = false,
    /// Drops the recorded auction phase — the next round declares its own.
    bool clearAuctionPhase = false,
    bool clearResult = false,
    bool clearGameOver = false,
    bool clearMeEmote = false,
    bool clearOpponentEmote = false,
    bool clearMe = false,
    bool clearOpponent = false,
    bool clearReadyTimerPlayerId = false,
  }) {
    return GameSessionState(
      phase: phase ?? this.phase,
      result: clearResult ? null : (result ?? this.result),
      data: data ?? this.data,
      lastEventName: lastEventName ?? this.lastEventName,
      game: game ?? this.game,
      gameOver: clearGameOver ? null : (gameOver ?? this.gameOver),
      readyTimerStopped: readyTimerStopped ?? this.readyTimerStopped,
      meEmote: clearMeEmote ? null : (meEmote ?? this.meEmote),
      opponentEmote: clearOpponentEmote
          ? null
          : (opponentEmote ?? this.opponentEmote),
      me: clearMe ? null : (me ?? this.me),
      opponent: clearOpponent ? null : (opponent ?? this.opponent),
      readyTimerPlayerId: clearReadyTimerPlayerId
          ? null
          : (readyTimerPlayerId ?? this.readyTimerPlayerId),
      opponentReadyPulse: opponentReadyPulse ?? this.opponentReadyPulse,
      opponentCardPulse: opponentCardPulse ?? this.opponentCardPulse,
      auctionPhase:
          clearAuctionPhase ? null : (auctionPhase ?? this.auctionPhase),
      currentBid: clearAuctionBid ? null : (currentBid ?? this.currentBid),
      isBiding: isBiding ?? this.isBiding,
      answeringPlayerId: clearAuctionAnswer
          ? null
          : (answeringPlayerId ?? this.answeringPlayerId),
      goalScore: clearAuctionAnswer ? null : (goalScore ?? this.goalScore),
      currentScore:
          clearAuctionAnswer ? null : (currentScore ?? this.currentScore),
      wrongScore: clearAuctionAnswer ? null : (wrongScore ?? this.wrongScore),
      auctionResult: clearAuctionAnswer
          ? AuctionResult.none
          : (auctionResult ?? this.auctionResult),
      answersUnlocked: answersUnlocked ?? this.answersUnlocked,
      bellArmed: bellArmed ?? this.bellArmed,
      comebackAnswerLocked:
          comebackAnswerLocked ?? this.comebackAnswerLocked,
    );
  }
}

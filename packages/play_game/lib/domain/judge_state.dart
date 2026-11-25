import '../features/games/domain/entities/created_game.dart';
import '../features/games/domain/entities/game_over_result.dart';
import '../features/games/domain/entities/game_player.dart';

/// Where a Judge session is. One device, the judge's; the two players are
/// seats the server creates (`"{judgeId}1"` and `"{judgeId}2"`).
enum JudgeStage {
  /// Asking the server for a Judge game.
  creating,

  /// The game exists; the judge names the two players.
  naming,

  /// StartJudgeGame sent, waiting for GameStarted.
  starting,
  playing,

  /// GameOver arrived, or the server ended the game without one.
  finished,
}

/// The three steps of an Auction question, from the server's events.
enum JudgeAuctionStep { bidding, answering, confirming }

enum JudgeCallKind { correct, wrong, timeout, pass }

/// The last call recorded, shown briefly so the judge sees it registered.
class JudgeCall {
  const JudgeCall(this.kind, this.playerId, this.serial);

  final JudgeCallKind kind;
  final String playerId;

  /// Distinguishes two identical calls in a row.
  final int serial;
}

/// Round types as the server numbers them (GameType).
abstract final class JudgeRound {
  static const wdyk = 1;
  static const auction = 2;
  static const bell = 3;
  static const makeup = 4;
  static const breaker = 5;
  static const impossible = 6;

  static bool isBellLike(int round) => round == bell || round == impossible;

  static bool isScoringRace(int round) => round == makeup || round == breaker;
}

class JudgeState {
  const JudgeState({
    required this.stage,
    this.game,
    this.round = JudgeRound.wdyk,
    this.turn = '',
    this.timerEndsAt,
    this.auctionStep,
    this.bidderId,
    this.bid,
    this.auctionScore,
    this.auctionWrong,
    this.result,
    this.lastCall,
    this.busy = false,
    this.awaiting = false,
    this.failed = false,
  });

  factory JudgeState.initial() => const JudgeState(stage: JudgeStage.creating);

  final JudgeStage stage;
  final CreatedGame? game;

  /// The round in play (see [JudgeRound]).
  final int round;

  /// Whose turn it is, from ChangeTurn only: GameUpdated.currentTurn can be
  /// stale in Auction. Empty while nobody holds it (Bell before a ring);
  /// [CreatedGame.allowAllTurn] in Makeup and Breaker.
  final String turn;

  /// When the running answer timer ends; null while no timer runs. Taken from
  /// TimerUpdatedSeconds, the only event that carries the time.
  final DateTime? timerEndsAt;

  final JudgeAuctionStep? auctionStep;
  final String? bidderId;
  final int? bid;
  final int? auctionScore;
  final int? auctionWrong;

  final GameOverResult? result;
  final JudgeCall? lastCall;

  /// A command is on its way; the controls wait for it.
  final bool busy;

  /// A call was recorded and the server has not yet made its next move (the
  /// next turn's clock, the next question). The controls wait: offering
  /// "Start timer" in that gap would start the clock on a question that is
  /// already over.
  final bool awaiting;

  /// The game could not be created or started.
  final bool failed;

  String? get gameId => game?.id;

  bool get timerRunning => timerEndsAt != null;

  List<GamePlayer> get players => game?.players ?? const [];

  GamePlayer? player(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final p in players) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  String nameOf(String? id) => player(id)?.playerName ?? '';

  /// The seat whose turn it is, when exactly one seat holds it.
  GamePlayer? get turnPlayer => player(turn);

  JudgeState copyWith({
    JudgeStage? stage,
    CreatedGame? game,
    int? round,
    String? turn,
    DateTime? timerEndsAt,
    bool clearTimer = false,
    JudgeAuctionStep? auctionStep,
    String? bidderId,
    int? bid,
    int? auctionScore,
    int? auctionWrong,
    bool clearAuction = false,
    GameOverResult? result,
    JudgeCall? lastCall,
    bool? busy,
    bool? awaiting,
    bool? failed,
  }) {
    return JudgeState(
      stage: stage ?? this.stage,
      game: game ?? this.game,
      round: round ?? this.round,
      turn: turn ?? this.turn,
      timerEndsAt: clearTimer ? null : (timerEndsAt ?? this.timerEndsAt),
      auctionStep: clearAuction ? null : (auctionStep ?? this.auctionStep),
      bidderId: clearAuction ? null : (bidderId ?? this.bidderId),
      bid: clearAuction ? null : (bid ?? this.bid),
      auctionScore: clearAuction ? null : (auctionScore ?? this.auctionScore),
      auctionWrong: clearAuction ? null : (auctionWrong ?? this.auctionWrong),
      result: result ?? this.result,
      lastCall: lastCall ?? this.lastCall,
      busy: busy ?? this.busy,
      awaiting: awaiting ?? this.awaiting,
      failed: failed ?? this.failed,
    );
  }
}

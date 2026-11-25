import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/play_game_hub_events.dart';
import '../../domain/game_hub_event.dart';
import '../../domain/judge_state.dart';
import '../../features/games/data/models/created_game_model.dart';
import '../../features/games/data/models/game_over_result_model.dart';
import '../../features/games/domain/entities/created_game.dart';
import '../../features/games/domain/entities/current_question.dart';
import '../game_controller/play_game_hub_bindings.dart';

final judgeControllerProvider =
    NotifierProvider.autoDispose<JudgeController, JudgeState>(
      JudgeController.new,
    );

/// Runs one Judge game for the judge's device (docs/JUDGE_MODE_SPEC.md).
///
/// The server is authoritative: every number on screen comes from its events,
/// and the judge's taps are commands that the next event confirms. The one
/// client-side rule is ordering: the turn comes from ChangeTurn only, because
/// GameUpdated can carry a stale turn during Auction.
class JudgeController extends AutoDisposeNotifier<JudgeState> {
  /// Server game mode for Judge.
  static const judgeMode = 3;

  /// Answer ids the judge can send besides a listed answer.
  static const wrongAnswerId = 0;
  static const notListedAnswerId = -99;

  /// Highest bid the server accepts.
  static const maxBid = 100;

  /// How long the controls wait for the server's next move after a call
  /// before they open again anyway.
  static const awaitingLimit = Duration(seconds: 6);

  int _callSerial = 0;
  bool _created = false;
  Timer? _awaitingLimit;

  /// Answers already sent for the current question, so a double tap cannot
  /// send one twice before the server removes it from the list.
  final Set<int> _sentAnswerIds = {};
  int? _sentForQuestionId;

  @override
  JudgeState build() {
    final bindings = ref.watch(playGameHubBindingsProvider);
    final subscription = bindings.stream.listen(onHubEvent);
    final unregister = ref
        .read(connectionRecoveryControllerProvider)
        .onRecovered(_onRecovered);
    ref.onDispose(() {
      _awaitingLimit?.cancel();
      unregister();
      unawaited(subscription.cancel());
    });
    return JudgeState.initial();
  }

  SignalRService get _hub => ref.read(signalRServiceProvider);

  // ---------------------------------------------------------------------------
  // Commands

  /// Asks the server for a Judge game. Once per controller.
  Future<void> create() async {
    if (_created) {
      return;
    }
    _created = true;
    AppLogger.log('JudgeController — invoke CreateGame | mode: $judgeMode');
    final sent = await _hub.invoke(
      PlayGameHubEvents.createGame,
      args: [judgeMode],
    );
    if (!sent) {
      _created = false;
      state = state.copyWith(failed: true);
    }
  }

  /// Names the players and starts the game. [interestIds] may be empty, in
  /// which case the server uses the judge's own interests.
  Future<bool> start(
    String player1,
    String player2,
    List<int> interestIds,
  ) async {
    final gameId = state.gameId;
    if (gameId == null || state.stage != JudgeStage.naming || state.busy) {
      return false;
    }
    state = state.copyWith(stage: JudgeStage.starting, failed: false);
    final sent = await _send(PlayGameHubEvents.startJudgeGame, [
      gameId,
      player1.trim(),
      player2.trim(),
      if (interestIds.isNotEmpty) interestIds else null,
    ]);
    if (!sent && state.stage == JudgeStage.starting) {
      state = state.copyWith(stage: JudgeStage.naming, failed: true);
    }
    return sent;
  }

  /// WDYK, Makeup and Breaker wait for the judge before the clock runs.
  Future<void> startTimer() async {
    final gameId = state.gameId;
    if (gameId == null || state.timerRunning) {
      return;
    }
    await _send(PlayGameHubEvents.startGameTimer, [gameId]);
  }

  /// Records an answer for [playerId]: a listed answer id, [wrongAnswerId] or
  /// [notListedAnswerId].
  Future<void> answer(int answerId, String playerId) async {
    final gameId = state.gameId;
    if (gameId == null || playerId.isEmpty) {
      return;
    }
    final questionId = state.game?.currentQuestion?.id;
    if (questionId != _sentForQuestionId) {
      _sentForQuestionId = questionId;
      _sentAnswerIds.clear();
    }
    final listed = answerId != wrongAnswerId && answerId != notListedAnswerId;
    if (listed && !_sentAnswerIds.add(answerId)) {
      return;
    }
    final sent = await _send(PlayGameHubEvents.judgeSubmitAnswer, [
      gameId,
      answerId,
      playerId,
    ]);
    if (!sent && listed) {
      _sentAnswerIds.remove(answerId);
    }
  }

  /// Makeup and Breaker: a point for [playerId]. Never a wrong (0): that
  /// counts as a miss and the question sits until it times out.
  Future<void> pointTo(String playerId) async {
    final answers = state.game?.currentQuestion?.answers ?? const [];
    final listed = answers
        .map((a) => a.id)
        .whereType<int>()
        .where((id) => !_sentAnswerIds.contains(id));
    await answer(listed.isEmpty ? notListedAnswerId : listed.first, playerId);
  }

  Future<void> pass() async {
    final gameId = state.gameId;
    if (gameId == null) {
      return;
    }
    await _send(PlayGameHubEvents.pass, [gameId]);
  }

  /// Auction: one bid per question, from 1 to [maxBid]. A bid of 0 is dropped
  /// by the server without a word, so it is never sent.
  Future<void> bid(String playerId, int value) async {
    final gameId = state.gameId;
    if (gameId == null || playerId.isEmpty || value < 1 || value > maxBid) {
      return;
    }
    await _send(PlayGameHubEvents.judgeBid, [
      {'gameId': gameId, 'playerId': playerId, 'bidValue': value},
    ]);
  }

  Future<void> ringBell(String playerId) async {
    final gameId = state.gameId;
    if (gameId == null || playerId.isEmpty || state.turn.isNotEmpty) {
      return;
    }
    await _send(PlayGameHubEvents.judgeRingBell, [gameId, playerId]);
  }

  /// Auction result: whether the bidder reached the bid.
  Future<void> confirmAuction({required bool madeIt}) async {
    final gameId = state.gameId;
    if (gameId == null || state.auctionStep != JudgeAuctionStep.confirming) {
      return;
    }
    await _send(PlayGameHubEvents.auctionConfirmResult, [gameId, madeIt]);
  }

  /// Ends the game on the server. Safe to call more than once.
  Future<void> leave() async {
    final gameId = state.gameId;
    if (gameId == null || state.stage == JudgeStage.finished) {
      return;
    }
    AppLogger.log('JudgeController — invoke LeaveGame | $gameId');
    await _hub.invoke(PlayGameHubEvents.leaveGame, args: [gameId]);
  }

  Future<bool> _send(String method, List<Object?> args) async {
    if (state.busy) {
      return false;
    }
    state = state.copyWith(busy: true);
    AppLogger.log('JudgeController — invoke $method | $args');
    try {
      return await _hub.invoke(method, args: args);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void _onRecovered() {
    if (state.stage == JudgeStage.playing ||
        state.stage == JudgeStage.starting) {
      AppLogger.log('JudgeController — recovered, asking for the game');
      unawaited(_hub.invoke(PlayGameHubEvents.checkPlayerGame));
    }
  }

  // ---------------------------------------------------------------------------
  // Events

  void onHubEvent(GameHubEvent event) {
    if (!_isMine(event)) {
      return;
    }
    if (_endsAwaiting.contains(event.name)) {
      _stopAwaiting();
    }
    final data = event.data;
    switch (event.name) {
      case PlayGameHubEvents.gameCreated:
        _onCreated(data);
      case PlayGameHubEvents.gameStarted:
        _onStarted(data);
      case PlayGameHubEvents.gameRestore:
        _onRestore(data);
      case PlayGameHubEvents.gameUpdated:
        _onGameUpdated(data);
      case PlayGameHubEvents.changeTurn:
        state = state.copyWith(turn: _arg(data, 0) ?? '');
      case PlayGameHubEvents.timerUpdatedSeconds:
        _onTimer(data);
      case PlayGameHubEvents.nextQuestion:
        _onNextQuestion(data);
      case PlayGameHubEvents.penalty:
        _onPenalty(data);
      case PlayGameHubEvents.correctAnswer:
        _call(JudgeCallKind.correct, _arg(data, 2) ?? state.turn);
      case PlayGameHubEvents.playerPassed:
        _call(JudgeCallKind.pass, _arg(data, 0) ?? state.turn);
      case PlayGameHubEvents.roundFinished:
        state = state.copyWith(clearTimer: true, clearAuction: true);
      case PlayGameHubEvents.nextRoundStarted:
        _onNextRound(data);
      case PlayGameHubEvents.auctionBiddingPhaseStarted:
        state = state
            .copyWith(clearAuction: true, clearTimer: true)
            .copyWith(auctionStep: JudgeAuctionStep.bidding);
      case PlayGameHubEvents.playerBidded:
        state = state.copyWith(
          bidderId: _string(data, 'playerId'),
          bid: _int(data, 'bidValue'),
        );
      case PlayGameHubEvents.auctionAnswerPhaseStarted:
        state = state.copyWith(
          auctionStep: JudgeAuctionStep.answering,
          bidderId: _string(data, 'playerId'),
          bid: _int(data, 'bidValue'),
          auctionScore: 0,
          auctionWrong: 0,
        );
      case PlayGameHubEvents.auctionAnswerPhaseScoreUpdate:
        state = state.copyWith(
          auctionScore: _int(data, 'currentScore'),
          auctionWrong: _int(data, 'wrongScore'),
          bid: _int(data, 'goalScore'),
        );
      case PlayGameHubEvents.showAuctionConfirmationDialog:
        // Shown whenever it arrives, even early: the server waits for it.
        state = state.copyWith(
          auctionStep: JudgeAuctionStep.confirming,
          clearTimer: true,
        );
      case PlayGameHubEvents.gameOver:
        _onGameOver(data);
      case PlayGameHubEvents.gameFinished:
        _onFinished();
      default:
        break;
    }
  }

  /// The server's next move after a call: a clock, a question, a new step.
  static const _endsAwaiting = {
    PlayGameHubEvents.timerUpdatedSeconds,
    PlayGameHubEvents.nextQuestion,
    PlayGameHubEvents.nextRoundStarted,
    PlayGameHubEvents.roundFinished,
    PlayGameHubEvents.auctionBiddingPhaseStarted,
    PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
    PlayGameHubEvents.showAuctionConfirmationDialog,
    PlayGameHubEvents.gameRestore,
    PlayGameHubEvents.gameOver,
  };

  void _stopAwaiting() {
    _awaitingLimit?.cancel();
    if (state.awaiting) {
      state = state.copyWith(awaiting: false);
    }
  }

  /// Events are delivered per user, so a judge can still receive a late
  /// event from an earlier game. Before this game exists only a Judge game's
  /// creation or restore is taken; after, only this game's events.
  bool _isMine(GameHubEvent event) {
    if (state.stage == JudgeStage.finished) {
      return false;
    }
    final known = state.gameId;
    final incoming = HubEventPayload.gameIdOf(event.data);
    if (known == null || known.isEmpty) {
      if (event.name == PlayGameHubEvents.gameCreated ||
          event.name == PlayGameHubEvents.gameRestore) {
        return _mode(event.data) == judgeMode;
      }
      return false;
    }
    if (event.name == PlayGameHubEvents.gameRestore) {
      return _mode(event.data) == judgeMode;
    }
    return incoming == null || incoming == known;
  }

  void _onCreated(Map<String, dynamic>? data) {
    if (data == null || state.stage != JudgeStage.creating) {
      return;
    }
    state = state.copyWith(
      stage: JudgeStage.naming,
      game: CreatedGameModel.fromJson(data),
    );
  }

  void _onStarted(Map<String, dynamic>? data) {
    if (data == null) {
      return;
    }
    final game = CreatedGameModel.merge(state.game, data);
    state = JudgeState(
      stage: JudgeStage.playing,
      game: game,
      round: game.type == 0 ? JudgeRound.wdyk : game.type,
      turn: game.currentTurn ?? '',
      lastCall: state.lastCall,
    );
  }

  /// Rebuilds the round from a snapshot (reconnect): the timer comes from
  /// the TimerUpdatedSeconds that follows, the turn from the ChangeTurn.
  void _onRestore(Map<String, dynamic>? data) {
    if (data == null) {
      return;
    }
    final game = CreatedGameModel.fromJson(data);
    if (game.status == 1 && (game.players?.isEmpty ?? true)) {
      state = JudgeState(stage: JudgeStage.naming, game: game);
      return;
    }
    final phase = game.auctionGameMetadata?.phase;
    state = JudgeState(
      stage: JudgeStage.playing,
      game: game,
      round: game.type == 0 ? JudgeRound.wdyk : game.type,
      turn: game.currentTurn ?? '',
      auctionStep: game.type == JudgeRound.auction
          ? switch (phase) {
              1 => JudgeAuctionStep.bidding,
              2 => JudgeAuctionStep.answering,
              3 => JudgeAuctionStep.confirming,
              _ => null,
            }
          : null,
      bid: game.auctionGameMetadata?.currentBid,
      auctionScore: game.auctionGameMetadata?.currentScore,
      auctionWrong: game.auctionGameMetadata?.wrongScore,
      bidderId: game.auctionGameMetadata?.latestBidder,
    );
  }

  void _onGameUpdated(Map<String, dynamic>? data) {
    if (data == null || state.game == null) {
      return;
    }
    // The turn is not taken from here (stale in Auction).
    state = state.copyWith(game: CreatedGameModel.merge(state.game, data));
  }

  void _onTimer(Map<String, dynamic>? data) {
    final seconds = num.tryParse('${data?['arg0'] ?? ''}');
    if (seconds == null || seconds <= 0) {
      return;
    }
    state = state.copyWith(
      timerEndsAt: DateTime.now().add(
        Duration(milliseconds: (seconds * 1000).round()),
      ),
    );
  }

  void _onNextQuestion(Map<String, dynamic>? data) {
    final question = CreatedGameModel.questionFromHub(data);
    final game = state.game;
    if (question == null || game == null) {
      return;
    }
    final isNew = question.id != game.currentQuestion?.id;
    state = state.copyWith(
      game: game.copyWith(
        currentQuestion: _keepCount(question, game.currentQuestion),
      ),
      // A new question has no clock until the judge starts it (or someone
      // rings); a word-by-word reveal of the same question keeps the one
      // running.
      clearTimer: isNew,
      // Bell opens the ring window on NextQuestion; nobody holds the turn.
      turn: isNew && JudgeRound.isBellLike(state.round) ? '' : null,
    );
  }

  /// A revealed word carries no count of its own on some payloads.
  CurrentQuestion _keepCount(CurrentQuestion next, CurrentQuestion? previous) {
    if (next.questionNumber != null ||
        previous == null ||
        previous.id != next.id) {
      return next;
    }
    return CurrentQuestion(
      id: next.id,
      type: next.type,
      answers: next.answers,
      text: next.text,
      textEn: next.textEn,
      description: next.description,
      image: next.image,
      video: next.video,
      audio: next.audio,
      maxCorrectAnswersCount: next.maxCorrectAnswersCount,
      questionNumber: previous.questionNumber,
      roundTotalQuestionsCount: previous.roundTotalQuestionsCount,
    );
  }

  void _onPenalty(Map<String, dynamic>? data) {
    final playerId = _string(data, 'playerId') ?? '';
    final type = _int(data, 'type');
    _call(type == 1 ? JudgeCallKind.timeout : JudgeCallKind.wrong, playerId);
  }

  void _call(JudgeCallKind kind, String playerId) {
    // In Auction's answer phase one clock covers the whole phase and a call
    // only moves the score; everywhere else a call ends the turn.
    final endsTurn =
        !(state.round == JudgeRound.auction &&
            state.auctionStep == JudgeAuctionStep.answering);
    state = state.copyWith(
      lastCall: JudgeCall(kind, playerId, ++_callSerial),
      clearTimer: endsTurn,
      awaiting: endsTurn,
    );
    if (endsTurn) {
      _awaitingLimit?.cancel();
      _awaitingLimit = Timer(awaitingLimit, _stopAwaiting);
    }
  }

  void _onNextRound(Map<String, dynamic>? data) {
    final round = int.tryParse('${data?['arg0'] ?? ''}');
    if (round == null) {
      return;
    }
    state = state.copyWith(
      round: round,
      turn: JudgeRound.isScoringRace(round) ? CreatedGame.allowAllTurn : '',
      clearTimer: true,
      clearAuction: true,
      game: state.game?.copyWith(type: round, clearCurrentQuestion: true),
    );
  }

  void _onGameOver(Map<String, dynamic>? data) {
    if (data == null) {
      return;
    }
    state = state.copyWith(
      stage: JudgeStage.finished,
      result: GameOverResultModel.fromJson(data),
      clearTimer: true,
      clearAuction: true,
    );
  }

  /// GameFinished without a GameOver: the game ended with nothing to show
  /// (no questions, or the server closed it).
  void _onFinished() {
    if (state.stage == JudgeStage.creating) {
      return;
    }
    if (state.stage == JudgeStage.starting) {
      state = state.copyWith(stage: JudgeStage.naming, failed: true);
      return;
    }
    state = state.copyWith(stage: JudgeStage.finished, clearTimer: true);
  }

  // ---------------------------------------------------------------------------
  // Payload helpers

  // Named fields go through JsonValue, which tolerates PascalCase keys and
  // numbers sent as strings, as the 1v1 handlers do.
  static int? _mode(Map<String, dynamic>? data) =>
      data == null ? null : JsonValue.parseInt(JsonValue.field(data, 'mode'));

  static String? _arg(Map<String, dynamic>? data, int index) {
    final value = data?['arg$index'];
    return value?.toString();
  }

  static String? _string(Map<String, dynamic>? data, String key) =>
      data == null ? null : JsonValue.field(data, key)?.toString();

  static int? _int(Map<String, dynamic>? data, String key) =>
      data == null ? null : JsonValue.parseInt(JsonValue.field(data, key));
}

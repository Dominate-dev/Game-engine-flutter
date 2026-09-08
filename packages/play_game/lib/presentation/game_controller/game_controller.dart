import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/play_game_hub_events.dart';
import '../../domain/auction_phase.dart';
import '../../domain/bell_phase.dart';
import '../../domain/game_hub_event.dart';
import '../../domain/game_mode.dart';
import '../../domain/game_phase.dart';
import '../../domain/game_session_state.dart';
import '../../domain/game_type.dart';
import '../../domain/status_game.dart';
import '../../domain/type_penalty.dart';
import '../../features/games/data/models/created_game_model.dart';
import '../../features/games/data/models/game_over_result_model.dart';
import '../../features/games/domain/entities/created_game.dart';
import '../../features/games/domain/entities/game_over_result.dart';
import '../../features/games/domain/entities/game_player.dart';
import '../../l10n/play_game_strings.dart';
import '../dialogs/player_answered_dialog.dart';
import '../dialogs/round_lottie_dialog.dart';
import 'game_session_reducer.dart';
import 'play_game_hub_bindings.dart';

part 'waiting_screen_handler.dart';
part 'lobby_screen_handler.dart';
part 'round_screen_handler.dart';
part 'auction_round_handler.dart';
part 'auction_dialog_handler.dart';
part 'bell_round_handler.dart';
part 'bell_dialog_handler.dart';
part 'comeback_round_handler.dart';
part 'comeback_dialog_handler.dart';
part 'private_lobby_handler.dart';

final gameControllerProvider =
    NotifierProvider.autoDispose<GameController, GameSessionState>(
  GameController.new,
);

/// Owns Play session state. Hub [sessionEvents] pick the screen;
/// [sharedRoundEvents] update question/timer/turn for every round.
/// Waiting / lobby / host call [onWaitingGameUpdated], [onWaitingGameRestore],
/// [onLobbyGameUpdated], [applyPlayerEmoted]. Round widgets read this provider.
class GameController extends AutoDisposeNotifier<GameSessionState> {
  @override
  GameSessionState build() {
    final bindings = ref.watch(playGameHubBindingsProvider);
    final subscription = bindings.stream.listen(_onHubEvent);

    final unregister = ref
        .read(connectionRecoveryControllerProvider)
        .onRecovered(onRecovered);
    ref.onDispose(() {
      _meEmoteTimer?.cancel();
      _opponentEmoteTimer?.cancel();
      unregister();
      unawaited(subscription.cancel());
    });

    return GameSessionState.initial();
  }

  /// Get current user ID from SharedPreferences.
  String? _getMyUserId() {
    final prefs = ref.read(sharedPrefsProvider);
    final userId = prefs.getUserId();
    if (userId != 0) {
      return userId.toString();
    }
    final social = prefs.getSocialMediaId().trim();
    if (social.isNotEmpty) {
      return social;
    }
    return null;
  }

  bool _didJoinRandom = false;
  bool _didCreatePrivateGame = false;

  /// Separate from [_didCreatePrivateGame] on purpose: one entry creates a
  /// private game and the other joins one, and a single flag would let
  /// whichever ran first suppress the other.
  bool _didJoinPrivateGame = false;

  /// The interest ids the private entry asked to create a game with, kept so
  /// the recovery path can re-issue a create that was deferred because the
  /// hub was not connected yet. Null whenever no create is owed — cleared on
  /// [PrivateLobbyHandler.enterPrivateLobby], set when a create is first
  /// attempted.
  List<int>? _pendingPrivateInterestIds;
  Timer? _meEmoteTimer;
  Timer? _opponentEmoteTimer;

  // Round overlays run one at a time, per round phase. showDialog pushes a route immediately, so
  // two events arriving together would stack two full-screen dialogs; T30 shows
  // them in sequence. WDYK and Auction share this one chain.
  Future<void> _roundDialogChain = Future<void>.value();

  /// Overlays queued or on screen. Zero means the next one can be shown
  /// straight away, without waiting a microtask for an empty queue.
  int _roundDialogsPending = 0;

  // Part-file extensions cannot use the @protected/@visibleForTesting state.
  GameSessionState get _s => state;

  set _s(GameSessionState value) => state = value;

  /// Whether this session has been left. Set once per session and cleared in
  /// exactly one place — [PrivateLobbyHandler.enterPrivateLobby], where a
  /// genuinely new session begins. A controller is normally per-entry
  /// (autoDispose), so a fresh entry gets a fresh `false`; a host that keeps
  /// one cached FlutterEngine across entries reaches the next entry on the
  /// same controller instead, and without that reset a left session would
  /// silence the new one's dispatches.
  ///
  /// This is the single choke point for "nothing may be dispatched after the
  /// user has left". The screen is not it — a popped route stays mounted for
  /// its whole exit transition, so `mounted` is still true while callbacks,
  /// post-frame work and hub events from the dying screen are still landing.
  bool _leftGame = false;

  /// Whether a dispatch is still allowed on this session.
  bool get hasLeftGame => _leftGame;

  /// Records the leave without dispatching `LeaveGame` — for the exits the
  /// server already knows about (a concluded game's result dialog, a refused
  /// private join). The suppression is identical; only the hub call differs.
  void markLeftGame() {
    _leftGame = true;
  }

  /// Leaves every game this player is in. One `LeaveGame` per session: the
  /// flag is claimed before the await, so two exit paths racing in the same
  /// tick cannot both dispatch.
  Future<void> leaveGame() async {
    if (_leftGame) {
      return;
    }
    _leftGame = true;
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.leaveGame} | all',
    );
    await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.leaveGame,
          args: ['all'],
        );
  }

  Future<void> sendEmoji(String imagePath) async {
    final gameId = state.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.sendEmoji} | '
      'gameId: $gameId | path: $imagePath',
    );
    await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.sendEmoji,
          args: [gameId, imagePath],
        );
  }

  // The timer is not stopped here: only the authoritative event that follows
  // (PlayerPassed) freezes it, so a dispatch that never left keeps counting.
  Future<bool> pass() async {
    final me = state.me;
    if (!state.isMyTurn || (me?.passes ?? 0) <= 0 || (me?.penalty ?? 0) < 2) {
      return false;
    }
    final gameId = state.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.pass} | gameId: $gameId',
    );
    return ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.pass,
          args: [gameId],
        );
  }

  // As with pass(): CorrectAnswer or Penalty freezes the timer, not the tap.
  Future<bool> submitAnswer(int answerId) async {
    if (!state.isMyTurn) {
      return false;
    }
    final gameId = state.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.submitAnswer} | '
      'gameId: $gameId | answerId: $answerId',
    );
    return ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.submitAnswer,
          args: [gameId, answerId],
        );
  }

  /// The countdown reached zero. The value it counted down from is still the
  /// server's — this only reports that it ran out, so answering closes.
  void onAnswerTimerExpired() {
    if (!state.answersUnlocked) {
      return;
    }
    state = state.copyWith(answersUnlocked: false);
  }

  void _onHubEvent(GameHubEvent event) {
    if (state.phase == GamePhase.waiting &&
        PlayGameHubEvents.waitingScreenEvents.contains(event.name)) {
      return;
    }
    if (state.phase == GamePhase.lobbyPlay &&
        PlayGameHubEvents.lobbyScreenEvents.contains(event.name)) {
      return;
    }
    // The private lobby's twin of the line above, and the same reason: its
    // screen binds `privateLobbyScreenEvents` itself, so anything on that
    // list reaching here as well is the event handled twice.
    //
    // GameFinished is why this matters rather than merely being untidy. It
    // sits in both that list and `gameOverEvents`, so the copy that got
    // through ran `endGame` — a result of `GameResult.ended` and the neutral
    // "The game is over" dialog — for what in this lobby only ever means the
    // creator terminated it. The public lobby never saw that, because its own
    // suppression above has always been there.
    //
    // `gameOver` and `gameTerminated` are deliberately not on the private
    // list, so a genuine game result still reaches `endGame` unchanged.
    if (state.phase == GamePhase.lobbyPrivate &&
        PlayGameHubEvents.privateLobbyScreenEvents.contains(event.name)) {
      return;
    }
    // BUG-01: once the game has ended, every event on this stream is stale
    // by definition except a terminal confirmation (already applied, and
    // idempotent if repeated) or a GameRestore snapshot (the authoritative
    // resync mechanism — its own routing already preserves `result`, see
    // showPhase/_refreshLobby). Anything else — a late TimeStarted,
    // TimerUpdatedSeconds, ChangeTurn, or a stale GameUpdated/auction event —
    // must not resurrect round/timer/answering state behind the
    // already-showing result dialog, since endGame deliberately leaves
    // `phase` untouched.
    if (state.result != null &&
        !PlayGameHubEvents.gameOverEvents.contains(event.name) &&
        event.name != PlayGameHubEvents.gameRestore) {
      return;
    }
    if (PlayGameHubEvents.sessionEvents.contains(event.name)) {
      applySessionEvent(event.name, event.data);
      return;
    }
    if (PlayGameHubEvents.auctionRoundEvents.contains(event.name)) {
      applyAuctionEvent(event.name, event.data);
      return;
    }
    if (PlayGameHubEvents.sharedRoundEvents.contains(event.name)) {
      applySharedRoundEvent(event.name, event.data);
    }
  }

  /// Session routing from [PlayGameHubBindings.stream].
  void applySessionEvent(String name, Map<String, dynamic>? data) {
    var game = _gameFromData(data);
    final gameOver = _gameOverFromData(name, data);

    if (PlayGameHubEvents.gameOverEvents.contains(name) || gameOver != null) {
      endGame(
        // Never default to loss: an undeterminable outcome shows the neutral
        // end-of-game dialog rather than telling a possible winner they lost.
        result: _resultFromGameOver(gameOver) ??
            _resultFromData(data) ??
            GameResult.ended,
        data: data,
        game: game,
        gameOver: gameOver,
        eventName: name,
      );
      return;
    }

    // Ahead of _routeByStatus, not behind it. GameStarted carries the match's
    // first question (docs/tasks/private-game-workflow.md §5) and always
    // carries `status` 3, so status routing claims the event — which left the
    // question extraction below on an unreachable branch.
    //
    // That is currently harmless rather than a bug: on a GameStarted payload
    // `CreatedGameModel.merge` already resolves `currentQuestion` through the
    // same `questionFromHub` extractor, and its `currentQuestion`/`answers`
    // key check accepts exactly the shapes that extractor accepts (a payload
    // carrying `players`/`status`/`groupId` can never satisfy
    // `looksLikeCurrentQuestion`). The two agree today. This makes the
    // extraction explicit at the point that owns it, so they cannot silently
    // drift apart if either side's accepted shapes change.
    //
    // Routing is unchanged: _routeByStatus sees the same status and takes the
    // same branch it always did.
    if (name == PlayGameHubEvents.gameStarted) {
      final startedGame = _gameWithQuestionFromData(data, game);
      if (_routeByStatus(
        game: startedGame,
        data: data,
        eventName: name,
      )) {
        return;
      }
      _goToRound(
        data: data,
        game: startedGame,
        stopReadyTimer: true,
        eventName: name,
      );
      return;
    }

    if (_routeByStatus(game: game, data: data, eventName: name)) {
      return;
    }

    if (name == PlayGameHubEvents.gameRestore) {
      // R-05: _routeByStatus already failed (status absent/null/unrecognized)
      // — this is the authoritative resync, and merged `game` (see
      // CreatedGameModel.merge) can still carry a fresh `type` even without a
      // usable `status`. GameType.fromId(...).phase is the same, already-
      // established mapping _goToRound uses for every other in-progress
      // routing path — reusing it here (not inventing a new one) re-derives
      // the round instead of blindly keeping whatever phase happened to be
      // showing before the restore, which can otherwise disagree with the
      // round data this same call just merged into `game`. When type can't
      // resolve either, this still falls back to the prior, safe behavior:
      // stay on the current phase rather than guess.
      final restoredPhase = GameType.fromId(game?.type)?.phase ?? state.phase;
      showPhase(restoredPhase, data: data, game: game, eventName: name);
      return;
    }

    final phase = GamePhase.fromHubEvent(name) ??
        GamePhase.fromHubValue(
          data?['screen'] ??
              data?['Screen'] ??
              data?['round'] ??
              data?['Round'] ??
              data?['roundType'] ??
              data?['RoundType'] ??
              game?.type,
        );
    if (phase == null) {
      // W-IMPL residual: the session-path twin of the round-path reseat above.
      // me/opponent are state fields of their own, so a refreshed roster
      // arriving on an event with no resolvable phase never reached them —
      // the session kept the previous roster while `game` moved on. Reseat
      // the way showPhase and the round path already do.
      final players = _findPlayers(game?.players);
      state = state.copyWith(
        data: data,
        lastEventName: name,
        game: game,
        me: players.me,
        opponent: players.opponent,
      );
      return;
    }
    showPhase(phase, data: data, game: game, eventName: name);
  }

  /// Question / timer / turn / finish — same for every round screen.
  void applySharedRoundEvent(String name, Map<String, dynamic>? data) {
    if (name == PlayGameHubEvents.nextQuestion) {
      _applyNextQuestion(data);
      return;
    }

    final game = _gameFromData(data);
    // Decided here, above the routing return below, not only in the timer
    // branch further down.
    //
    // A resolution — CorrectAnswer, or a Penalty that stops the clock — can
    // arrive carrying a game-shaped payload: `looksLikeCreatedGame` is
    // satisfied by any one of `id`, `players`, `currentQuestion`,
    // `currentTimerValue`, `currentTurn`, `status` or `answers`, and a
    // roster update alone is enough. `_gameFromData` then merges it onto the
    // current game, which *inherits* `status` when the payload omits it, so
    // `_routeByStatus` resolves it as still in progress and routes — taking
    // the early return and never reaching `_eventStopsTimer`. The routed
    // snapshot also inherits `isTimerStarted: true`, so the countdown was
    // not merely left unfrozen, it was actively preserved and ran on to
    // 00:00 while the question was already resolved.
    //
    // Handing the routed snapshot the flag the resolution implies fixes that
    // without touching what `_eventStopsTimer` decides, which events route,
    // or where they route to.
    final stopsTimer = _eventStopsTimer(name, data);
    final payloadIsGame =
        data != null && CreatedGameModel.looksLikeCreatedGame(data);
    if (payloadIsGame &&
        _routeByStatus(
          game: stopsTimer ? game?.copyWith(isTimerStarted: false) : game,
          data: data,
          eventName: name,
        )) {
      return;
    }

    if (name == PlayGameHubEvents.roundFinished ||
        name == PlayGameHubEvents.showResults) {
      // Neither event carries its own game snapshot, so showPhase's trailing
      // _applyAuctionMetadata would reapply stale auctionGameMetadata over
      // fields already updated directly on GameSessionState. Clear it here,
      // same as NextRoundStarted already does one step later.
      showPhase(
        GamePhase.finishRound,
        data: data,
        game: game?.copyWith(clearAuctionGameMetadata: true),
        eventName: name,
      );
      return;
    }

    if (name == PlayGameHubEvents.nextRoundStarted) {
      final roundType = GameSessionReducer.roundTypeFrom(data);
      final phase = GameType.fromId(roundType)?.phase;
      final baseGame = game ?? state.game;
      final clearedGame = baseGame?.copyWith(
        clearCurrentQuestion: true,
        // The old metadata is the previous round's; leaving it would let
        // showPhase re-apply the phase and score that were just cleared.
        clearAuctionGameMetadata: true,
        // Native clears isTurnPlaying here; an empty currentTurn is this
        // codebase's "nobody may act", the same value an empty ChangeTurn sets.
        currentTurn: '',
        type: roundType ?? baseGame.type,
      );
      // NextRoundStarted is the reset boundary for the round that just ended:
      // its question, turn and auction state end here, not on whatever event
      // happens to arrive next.
      state = state.copyWith(
        isBiding: true,
        answersUnlocked: false,
        clearAuctionAnswer: true,
        clearAuctionBid: true,
        clearAuctionPhase: true,
        // Bell starts idle: unarmed, waiting for the round's own TimeStarted.
        bellArmed: false,
        // Comeback starts unlocked — any prior round's timeout lock ends here.
        comebackAnswerLocked: false,
      );
      if (phase != null) {
        showPhase(
          phase,
          data: data,
          game: clearedGame,
          stopReadyTimer: true,
          eventName: name,
        );
        return;
      }
      _goToRound(
        data: data,
        game: clearedGame,
        stopReadyTimer: true,
        eventName: name,
      );
      return;
    }

    // Penalty is routed once, here. Auction only inspects it for diagnostics —
    // it changes no auction state and no timer behaviour.
    if (name == PlayGameHubEvents.penalty &&
        state.phase == GamePhase.auction) {
      _validateAuctionPenalty(data);
    }

    CreatedGame? nextGame = game;
    // Answer availability is shared by every round: only TimerUpdatedSeconds
    // opens it, and null here means "leave it as it is".
    bool? unlockAnswers;
    if (name == PlayGameHubEvents.timeStarted) {
      nextGame = game?.copyWith(isTimerStarted: true);
    } else if (name == PlayGameHubEvents.changeTurn) {
      final playerId = GameSessionReducer.turnPlayerIdFrom(data);
      if (playerId != null) {
        // Bell only: a winner named while the race is still on ends the race
        // countdown right here — the answering countdown starts from the
        // server's next TimerUpdatedSeconds. An answering-phase ChangeTurn
        // (a turn already existed) is a normal transition and stops nothing.
        final endsBellRace = state.phase == GamePhase.bell &&
            state.bellArmed &&
            (game?.currentTurn?.trim() ?? '').isEmpty;
        if (endsBellRace) {
          // The race countdown that just ended had itself opened answering —
          // it is a TimerUpdatedSeconds like any other. Without this, the
          // winner named here inherits that open lock and their chips appear
          // on this event instead of on the answering countdown's own first
          // TimerUpdatedSeconds. Same condition as the freeze above, so the
          // two halves of ending the race cannot disagree.
          unlockAnswers = false;
        }
        nextGame = game?.copyWith(
          currentTurn: playerId,
          isTimerStarted: endsBellRace ? false : null,
        );
      } else if (_carriesTurnField(data)) {
        nextGame = game?.copyWith(currentTurn: '');
      }
    } else if (stopsTimer) {
      // The authoritative resolution of an action. PlayerAnswered is
      // deliberately absent: it announces an answer, it does not resolve it.
      //
      // Same value computed above, reused rather than recomputed: routing
      // returned, so nothing has changed the phase it depends on, and one
      // evaluation cannot disagree with itself.
      nextGame = game?.copyWith(isTimerStarted: false);
    } else if (name == PlayGameHubEvents.timerUpdatedSeconds) {
      final seconds = GameSessionReducer.timerValueFrom(data);
      if (seconds != null) {
        // A countdown with time on it *is* the timer running, so this event
        // reports the flag as well as the value. RoundScoreColumn freezes
        // only on an isTimerStarted true->false edge, and the per-question
        // cycle the server actually sends (NextQuestion -> ChangeTurn ->
        // TimerUpdatedSeconds) contains no TimeStarted to raise one:
        // _applyNextQuestion had just written false, so a resolution's own
        // false landed on a false, no edge was produced, and the countdown
        // ran on to 00:00 with the question already resolved. TimeStarted is
        // therefore no longer the only writer of true.
        //
        // A non-positive value is deliberately left alone rather than
        // written false: the branches that own a stop (the terminal
        // resolutions, a ChangeTurn ending a bell race, endGame, the auction
        // freeze) write that false themselves, and each carries a meaning
        // this event does not have.
        nextGame = game?.copyWith(
          currentTimerValue: seconds,
          isTimerStarted: seconds > 0 ? true : null,
        );
        // The one signal that opens answering, for every round: a countdown
        // with time on it. A value at or below zero closes it again.
        unlockAnswers = seconds > 0;
      }
    }

    // Bell only — arms/disarms the buzz button off the same events above.
    bool? bellArmed;
    if (state.phase == GamePhase.bell) {
      bellArmed = _nextBellArmed(name, nextGame);
    }

    // Comeback only — a timeout locks answering beyond what the tries count
    // alone covers, matching the native adapter.isClickable = false; timeOut()
    // pairing. A genuine new question clears it — Comeback's own question
    // content can arrive on GameUpdated as well as NextQuestion (the latter
    // is handled separately in _applyNextQuestion, which never reaches this
    // path), so the identity check is repeated here rather than assumed to
    // be covered by one event name.
    bool? comebackAnswerLocked;
    if (state.phase == GamePhase.comeBack || state.phase == GamePhase.breaker) {
      final previousQuestion = state.game?.currentQuestion;
      final nextQuestion = nextGame?.currentQuestion;
      final questionChanged = previousQuestion?.id != nextQuestion?.id ||
          previousQuestion?.questionNumber != nextQuestion?.questionNumber;
      if (questionChanged) {
        comebackAnswerLocked = false;
      } else if (name == PlayGameHubEvents.penalty &&
          TypePenalty.fromId(_penaltyTypeFrom(data)) == TypePenalty.timeout) {
        comebackAnswerLocked = true;
      }
    }

    // me/opponent are state fields of their own, so a refreshed roster in
    // the snapshot does not reach them. Reseat the way showPhase does.
    final players = _findPlayers(nextGame?.players);
    state = state.copyWith(
      data: data,
      lastEventName: name,
      game: nextGame,
      me: players.me,
      opponent: players.opponent,
      answersUnlocked: unlockAnswers,
      bellArmed: bellArmed,
      comebackAnswerLocked: comebackAnswerLocked,
    );
  }

  /// Which events freeze the countdown.
  ///
  /// The list is WDYK's and is unchanged for every round except Auction, whose
  /// answer phase is **one continuous countdown**: a correct answer and a wrong
  /// answer both leave it running, and only a timeout `Penalty(type: 1)` ends
  /// it here. The other auction terminals — reaching the goal, and
  /// PlayerWon/LostAuctionRound — are handled where those events are reduced.
  ///
  /// Comeback (and Breaker, confirmed identical) is an exception in the
  /// other direction: neither `CorrectAnswer` nor `Penalty` freeze the
  /// shared timer — the round's own countdown keeps running through both,
  /// independent of the separate `comebackAnswerLocked` timeout-lock (which
  /// still applies unchanged; it gates answering, not the timer).
  bool _eventStopsTimer(String name, Map<String, dynamic>? data) {
    final isStopEvent = name == PlayGameHubEvents.playerPassed ||
        name == PlayGameHubEvents.correctAnswer ||
        name == PlayGameHubEvents.penalty;
    if (!isStopEvent) {
      return false;
    }
    if (state.phase == GamePhase.comeBack || state.phase == GamePhase.breaker) {
      return name != PlayGameHubEvents.correctAnswer &&
          name != PlayGameHubEvents.penalty;
    }
    if (state.phase != GamePhase.auction) {
      return true;
    }
    if (name == PlayGameHubEvents.correctAnswer) {
      return false;
    }
    if (name == PlayGameHubEvents.penalty) {
      return TypePenalty.fromId(_penaltyTypeFrom(data)) == TypePenalty.timeout;
    }
    return true;
  }

  // ChangeTurn ['', gameId] is an explicit clear; a payload carrying no
  // turn field at all is not, and leaves currentTurn alone.
  bool _carriesTurnField(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    if (data.containsKey('arg0')) {
      return true;
    }
    return JsonValue.hasField(data, 'playerId') ||
        JsonValue.hasField(data, 'userId');
  }

  /// [NextQuestion] arg0 is the question object (title, answers, counts).
  void _applyNextQuestion(Map<String, dynamic>? data) {
    final question = CreatedGameModel.questionFromHub(data);
    if (question == null) {
      AppLogger.log(
        'GameController — ${PlayGameHubEvents.nextQuestion} payload not '
        'parsed | data: $data',
      );
      return;
    }
    final game = state.game;
    // Bell and Comeback (and Breaker, confirmed identical to Comeback) all
    // resend NextQuestion several times for the *same* question —
    // progressively revealing more of its text — while a countdown may
    // already be running (real-device evidence). Only a genuinely new
    // question locks answering and resets the timer; a same-question repeat
    // must leave both alone, or the shared countdown widget stops on the
    // isTimerStarted flip and the display freezes mid-question. Same
    // identity check as bell_round_screen.dart's and the shared Comeback
    // content's own _didQuestionChange (id + questionNumber). WDYK/Auction
    // never repeat a question this way, so isSameQuestion is always false
    // for them and this reset is unchanged.
    final previousQuestion = game?.currentQuestion;
    final isSameQuestion = previousQuestion != null &&
        previousQuestion.id == question.id &&
        previousQuestion.questionNumber == question.questionNumber;
    // Bell and Comeback/Breaker can also start a genuinely new question's
    // timer before delivering its content in full: Bell's real device
    // showed TimerUpdatedSeconds(10.999) followed 5ms later by NextQuestion
    // for the new question; Comeback's showed the question/answers already
    // present on GameUpdated before TimerUpdatedSeconds even started, so
    // the question identity NextQuestion later repeats does not reliably
    // match isSameQuestion above. A running timer is authoritative either
    // way — the native reference gives NextQuestion no timer ownership on
    // any of these rounds (it only (re)binds chips; Penalty/CorrectAnswer
    // stop the countdown) — so neither a same-question repeat nor an
    // identity-mismatched repeat may kill it. When no timer is running, the
    // question still arrives locked exactly as before.
    final timerAlreadyRunning = (state.phase == GamePhase.bell ||
            state.phase == GamePhase.comeBack ||
            state.phase == GamePhase.breaker) &&
        game?.isTimerStarted == true;
    final preserveTimer = isSameQuestion || timerAlreadyRunning;
    state = state.copyWith(
      data: data,
      lastEventName: PlayGameHubEvents.nextQuestion,
      game: game?.copyWith(
        currentQuestion: question,
        isTimerStarted: preserveTimer ? null : false,
      ),
      // A new question arrives locked: the next TimerUpdatedSeconds opens it.
      answersUnlocked: preserveTimer ? null : false,
      // bellArmed is deliberately left untouched here. NextQuestion can (and
      // does, per real-device evidence) repeat several times for the same
      // race — each repetition carrying progressively more question text —
      // while Bell is still actively racing, before any ChangeTurn/Penalty
      // ends it. Disarming on every one of those repeats hid an already-armed
      // Bell mid-race. ChangeTurn and Penalty already disarm it when the race
      // genuinely ends (see _nextBellArmed), and TimeStarted always
      // re-derives it fresh from the current turn — so nothing here needs to
      // force it false.
      // Comeback/Breaker: a genuinely new question is the only thing that
      // reopens answering after a timeout lock — a same-question repeat
      // (Bell's own case) leaves it untouched, and this is a no-op for
      // every other round.
      comebackAnswerLocked:
          ((state.phase == GamePhase.comeBack ||
                      state.phase == GamePhase.breaker) &&
                  !isSameQuestion)
              ? false
              : null,
    );
  }

  /// True when [PlayerLeft] playerId is this device's SharedPreferences user_id.
  bool isLocalPlayerLeft(Map<String, dynamic>? data) {
    return isCurrentUser(GameSessionReducer.playerIdFrom(data));
  }

  // Positive match against the persisted login user_id. Hub player ids share
  // that namespace and can name either player, so "not the opponent" is not
  // evidence of being the local user.
  bool isCurrentUser(String? playerId) {
    if (playerId == null || playerId.isEmpty) {
      return false;
    }
    if (playerIdsEqual(_getMyUserId(), playerId)) {
      return true;
    }
    final me = state.me;
    return me != null && me.matchesHubUserId(playerId);
  }

  bool _emoteIsMine(String eventUserId) => isCurrentUser(eventUserId);

  /// Whether a payload describes a private (invite-code) game.
  ///
  /// Both signals are honoured: the payload carries its own `isPrivate` flag,
  /// and the confirmed creation contract identifies private PvP by `mode` 4.
  /// Neither is inferred from the other.
  bool _isPrivateGame(CreatedGame? game) =>
      game != null && (game.isPrivate || game.mode == GameMode.privatePvp);

  /// Status first: 1 waiting, 2 lobby, 3 round by type, 4 game-ended dialog.
  bool _routeByStatus({
    required CreatedGame? game,
    Map<String, dynamic>? data,
    String? eventName,
  }) {
    final status = StatusGame.fromId(game?.status);
    if (status == null) {
      return false;
    }
    switch (status) {
      case StatusGame.waitingPlayers:
        showPhase(
          // A private game waits for its invited opponent in its own lobby,
          // never on WaitingScreen — that screen's whole job is dispatching
          // JoinRandomGame, the public matchmaking flow.
          _isPrivateGame(game) ? GamePhase.lobbyPrivate : GamePhase.waiting,
          data: data,
          game: game,
          eventName: eventName,
        );
        return true;
      case StatusGame.isReady:
        _refreshLobby(
          data: data,
          game: game,
          eventName: eventName,
          stopReadyTimer: GameSessionReducer.shouldStopReadyTimer(data, game),
        );
        return true;
      case StatusGame.inProgress:
        _goToRound(
          data: data,
          game: game,
          stopReadyTimer: true,
          eventName: eventName,
        );
        return true;
      case StatusGame.ended:
        endGame(
          result: GameResult.ended,
          data: data,
          game: game,
          eventName: eventName,
        );
        return true;
    }
  }

  void _refreshLobby({
    Map<String, dynamic>? data,
    CreatedGame? game,
    String? eventName,
    bool? stopReadyTimer,
    String? readyTimerPlayerId,
    int? opponentReadyPulse,
    int? opponentCardPulse,
    bool clearOpponentEmote = false,
    bool clearReadyTimerPlayerId = false,
  }) {
    final nextGame = game ?? state.game;
    final players = _findPlayers(nextGame?.players);
    final timerId = clearReadyTimerPlayerId
        ? null
        : readyTimerPlayerId ??
            GameSessionReducer.playerIdFrom(data) ??
            state.readyTimerPlayerId;
    state = GameSessionState(
      // Which lobby this refresh belongs to is a property of the game, not of
      // the call site: every lobby event (PlayerReady, PlayerLeft, a plain
      // GameUpdated) lands here, and a private game must stay in its own
      // lobby through all of them. Public games are unaffected.
      phase: _isPrivateGame(nextGame)
          ? GamePhase.lobbyPrivate
          : GamePhase.lobbyPlay,
      // A raw constructor, not copyWith — result must be carried over
      // explicitly or it silently reverts to null (there is no lobby-return
      // path that is meant to un-end an already-ended game).
      result: state.result,
      data: data ?? state.data,
      lastEventName: eventName ?? state.lastEventName,
      game: nextGame,
      gameOver: state.gameOver,
      readyTimerStopped: stopReadyTimer ?? state.readyTimerStopped,
      meEmote: state.meEmote,
      opponentEmote: clearOpponentEmote ? null : state.opponentEmote,
      me: players.me,
      opponent: players.opponent,
      readyTimerPlayerId: timerId,
      opponentReadyPulse: opponentReadyPulse ?? state.opponentReadyPulse,
      opponentCardPulse: opponentCardPulse ?? state.opponentCardPulse,
      // Auction state survives re-seating: GameUpdated rebuilds the session on
      // every hub update, and the round's scores are not part of that payload.
      auctionPhase: state.auctionPhase,
      currentBid: state.currentBid,
      isBiding: state.isBiding,
      answeringPlayerId: state.answeringPlayerId,
      goalScore: state.goalScore,
      currentScore: state.currentScore,
      wrongScore: state.wrongScore,
      auctionResult: state.auctionResult,
      answersUnlocked: state.answersUnlocked,
      bellArmed: state.bellArmed,
      comebackAnswerLocked: state.comebackAnswerLocked,
    );
  }

  void _goToRound({
    Map<String, dynamic>? data,
    CreatedGame? game,
    bool stopReadyTimer = false,
    String? eventName,
  }) {
    final phase = GameType.fromId(game?.type)?.phase;
    if (phase == null) {
      _refreshLobby(
        data: data,
        game: game,
        eventName: eventName,
        stopReadyTimer: stopReadyTimer,
      );
      return;
    }
    showPhase(
      phase,
      data: data,
      game: game,
      stopReadyTimer: stopReadyTimer,
      eventName: eventName,
    );
  }

  void showPhase(
    GamePhase phase, {
    Map<String, dynamic>? data,
    CreatedGame? game,
    bool? stopReadyTimer,
    String? eventName,
  }) {
    final nextGame = game ?? state.game;
    final players = _findPlayers(nextGame?.players);
    // Comeback: this is the path GameUpdated actually takes for an
    // in-progress game (routed here via _routeByStatus/_goToRound, not
    // through applySharedRoundEvent), so a genuine new question needs the
    // same identity check here to reopen answering after a timeout lock.
    final previousQuestion = state.game?.currentQuestion;
    final nextQuestion = nextGame?.currentQuestion;
    final comebackQuestionChanged =
        previousQuestion?.id != nextQuestion?.id ||
            previousQuestion?.questionNumber != nextQuestion?.questionNumber;
    state = GameSessionState(
      phase: phase,
      // A raw constructor, not copyWith — result must be carried over
      // explicitly or it silently reverts to null on the next routine event
      // (e.g. a stray GameUpdated arriving while the result dialog is still
      // up). Nothing in this codebase ever means to un-end an ended game;
      // GameSessionState.copyWith's own clearResult flag, the only sanctioned
      // way to null it out, has no call site.
      result: state.result,
      data: data,
      lastEventName: eventName ?? state.lastEventName,
      game: nextGame,
      gameOver: state.gameOver,
      readyTimerStopped: stopReadyTimer ?? state.readyTimerStopped,
      meEmote: state.meEmote,
      opponentEmote: state.opponentEmote,
      me: players.me ?? state.me,
      opponent: players.opponent ?? state.opponent,
      readyTimerPlayerId: state.readyTimerPlayerId,
      opponentReadyPulse: state.opponentReadyPulse,
      opponentCardPulse: state.opponentCardPulse,
      // Auction state survives re-seating: GameUpdated rebuilds the session on
      // every hub update, and the round's scores are not part of that payload.
      auctionPhase: state.auctionPhase,
      currentBid: state.currentBid,
      isBiding: state.isBiding,
      answeringPlayerId: state.answeringPlayerId,
      goalScore: state.goalScore,
      currentScore: state.currentScore,
      wrongScore: state.wrongScore,
      auctionResult: state.auctionResult,
      // WDYK/Auction/Bell only (BUG-03/BUG-04): a restore snapshot with a
      // genuinely active countdown (isTimerStarted + currentTimerValue > 0)
      // means the server already had answering open — the client must not
      // wait for a fresh TimerUpdatedSeconds to reflect that. This only
      // re-derives the shared "is a countdown open" signal; each round's own
      // isMyTurn/isAuctionAnswerer eligibility check (read alongside this
      // flag on the round screens) is untouched, so an ineligible player
      // still cannot answer. A restore with no active countdown explicitly
      // closes answering rather than preserving a possibly-stale value —
      // the same full-override treatment bellArmed already gets just below.
      // Comeback/Breaker never read answersUnlocked (their own eligibility
      // and restore handling is entirely separate) and are deliberately
      // left out of this.
      answersUnlocked: eventName == PlayGameHubEvents.gameRestore &&
              (phase == GamePhase.wdyk ||
                  phase == GamePhase.auction ||
                  phase == GamePhase.bell)
          ? (nextGame?.isTimerStarted == true &&
              (nextGame?.currentTimerValue ?? 0) > 0)
          : state.answersUnlocked,
      // A genuine restore re-derives "armed" from the restored snapshot
      // (B-10): no turn plus a running server countdown means the race was
      // still on, so the Bell comes back armed with no fresh TimeStarted
      // required. Anything else restores unarmed. A routine GameUpdated
      // mid-race is not a restore and must not disarm it.
      bellArmed: eventName == PlayGameHubEvents.gameRestore
          ? (phase == GamePhase.bell &&
              (nextGame?.currentTurn?.trim() ?? '').isEmpty &&
              nextGame?.isTimerStarted == true &&
              (nextGame?.currentTimerValue ?? 0) > 0)
          : state.bellArmed,
      // No server field reports "locked at timeout" — a restore always comes
      // back unlocked. Otherwise, a genuine new question clears an existing
      // lock; anything else (including a GameUpdated with the same question)
      // leaves it as it was. Breaker shares this exactly (confirmed
      // identical to Comeback).
      comebackAnswerLocked: eventName == PlayGameHubEvents.gameRestore
          ? false
          : ((phase == GamePhase.comeBack || phase == GamePhase.breaker) &&
                  comebackQuestionChanged)
              ? false
              : state.comebackAnswerLocked,
    );
    // Metadata is the authority on the auction phase after a restore or a
    // GameUpdated; applied after the rebuild so it is not overwritten.
    _applyAuctionMetadata(nextGame);
  }

  void endGame({
    required GameResult result,
    Map<String, dynamic>? data,
    CreatedGame? game,
    GameOverResult? gameOver,
    String? eventName,
  }) {
    // The game is authoritatively over — freeze the shared "still live"
    // signals every round reads (RoundScoreColumn's countdown stops only on
    // an isTimerStarted true→false edge; answersUnlocked's own contract is
    // "closes ... at every boundary that ends an answering phase", which
    // this is). A round can still be on screen behind the result dialog —
    // phase is deliberately left as-is below — so nothing here may keep
    // ticking or accepting taps under it.
    final nextGame = (game ?? state.game)?.copyWith(isTimerStarted: false);
    final players = _findPlayers(nextGame?.players);
    state = GameSessionState(
      phase: state.phase,
      result: result,
      data: data ?? state.data,
      lastEventName: eventName ?? state.lastEventName,
      game: nextGame,
      gameOver: gameOver ?? state.gameOver,
      readyTimerStopped: true,
      meEmote: state.meEmote,
      opponentEmote: state.opponentEmote,
      me: players.me ?? state.me,
      opponent: players.opponent ?? state.opponent,
      readyTimerPlayerId: state.readyTimerPlayerId,
      opponentReadyPulse: state.opponentReadyPulse,
      opponentCardPulse: state.opponentCardPulse,
      // Auction state survives re-seating: GameUpdated rebuilds the session on
      // every hub update, and the round's scores are not part of that payload.
      auctionPhase: state.auctionPhase,
      currentBid: state.currentBid,
      isBiding: state.isBiding,
      answeringPlayerId: state.answeringPlayerId,
      goalScore: state.goalScore,
      currentScore: state.currentScore,
      wrongScore: state.wrongScore,
      auctionResult: state.auctionResult,
      // See the comment on nextGame above — an ended game answers nothing.
      answersUnlocked: false,
      bellArmed: state.bellArmed,
      comebackAnswerLocked: state.comebackAnswerLocked,
    );
  }

  Future<void> onRecovered() async {
    // A session the player has left owns nothing on the hub any more: no
    // CheckPlayerGame, and none of the re-entry dispatches behind it.
    if (_leftGame) {
      return;
    }
    AppLogger.log('GameController — hub recovered, invoking CheckPlayerGame');
    await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.checkPlayerGame,
        );
    // CheckPlayerGame has had its turn to route the session onward. Only a
    // session still sitting in waiting, whose join never went out, needs
    // another attempt — a reconnect alone is not a reason to re-join.
    if (state.phase == GamePhase.waiting && !_didJoinRandom) {
      await onWaitingShown();
    }
    // The private lobby's equivalent, and for the same reason: its create is
    // deferred while the hub is down, so the connect landing is what lets it
    // go out. Nothing is retried unless a create is actually owed — the ids
    // are only non-null between entering the lobby and a create succeeding.
    final pendingInterestIds = _pendingPrivateInterestIds;
    if (state.phase == GamePhase.lobbyPrivate &&
        !_didCreatePrivateGame &&
        pendingInterestIds != null) {
      await createPrivateGame(pendingInterestIds);
    }
  }

  /// Find me and opponent from players list.
  ({GamePlayer? me, GamePlayer? opponent}) _findPlayers(List<GamePlayer>? players) {
    if (players == null || players.isEmpty) {
      return (me: state.me, opponent: state.opponent);
    }

    // The persisted login user_id is the authority; a previously seated me is
    // only a fallback when prefs cannot supply one.
    final myId = _getMyUserId() ?? state.me?.id;
    GamePlayer? me;

    if (myId != null && myId.isNotEmpty) {
      for (final player in players) {
        if (player.matchesHubUserId(myId)) {
          me = player;
          break;
        }
      }
    }

    // No positional guess: seating the wrong player is worse than seating none.
    if (me == null) {
      return (me: state.me, opponent: state.opponent);
    }

    GamePlayer? opponent;
    for (final player in players) {
      if (player.id != me.id) {
        opponent = player;
        break;
      }
    }
    return (me: me, opponent: opponent);
  }

  CreatedGame? _gameFromData(Map<String, dynamic>? data) {
    if (data == null || !CreatedGameModel.looksLikeCreatedGame(data)) {
      return state.game;
    }
    return CreatedGameModel.merge(state.game, data);
  }

  CreatedGame? _gameWithQuestionFromData(
    Map<String, dynamic>? data,
    CreatedGame? game,
  ) {
    final merged = game ?? _gameFromData(data);
    if (merged?.currentQuestion != null) {
      return merged;
    }
    final question = CreatedGameModel.questionFromHub(data);
    if (question == null || merged == null) {
      return merged;
    }
    return merged.copyWith(currentQuestion: question);
  }

  GameOverResult? _gameOverFromData(
    String eventName,
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      return null;
    }
    final shouldParse = PlayGameHubEvents.gameOverEvents.contains(eventName) ||
        GameOverResultModel.looksLikeGameOver(data);
    if (!shouldParse) {
      return null;
    }
    return GameOverResultModel.fromJson(data);
  }

  // Returns null when the outcome cannot be determined, so the caller falls
  // through to _resultFromData rather than assuming a loss.
  GameResult? _resultFromGameOver(GameOverResult? gameOver) {
    if (gameOver == null) {
      return null;
    }
    if (!gameOver.hasKnownWinner) {
      return null;
    }
    final userId = ref.read(sharedPrefsProvider).getUserId().toString();
    return gameOver.isWinner(userId) ? GameResult.win : GameResult.loss;
  }

  GameResult? _resultFromData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final isWin = data['isWin'] ?? data['IsWin'];
    if (isWin is bool) {
      return isWin ? GameResult.win : GameResult.loss;
    }
    final key = (data['result'] ?? data['Result'] ?? data['gameResult'])
        ?.toString()
        .trim()
        .toLowerCase();
    return switch (key) {
      'win' || 'won' || 'winner' => GameResult.win,
      'loss' || 'lose' || 'lost' || 'loser' => GameResult.loss,
      _ => null,
    };
  }
}

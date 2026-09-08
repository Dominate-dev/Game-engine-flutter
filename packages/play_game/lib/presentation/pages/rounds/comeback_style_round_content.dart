import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/play_game_hub_events.dart';
import '../../../domain/game_session_state.dart';
import '../../../features/games/domain/entities/current_question.dart';
import '../../../features/games/domain/entities/question_answer.dart';
import '../../../l10n/play_game_strings.dart';
import '../../game_controller/game_controller.dart';
import '../../widgets/rounds/round_actions_row.dart';
import '../../widgets/rounds/round_attempts_info.dart';
import '../../widgets/rounds/round_background_image.dart';
import '../../widgets/rounds/round_header_bar.dart';
import '../../widgets/rounds/round_info_card.dart';
import '../../widgets/rounds/round_player_avatar.dart';
import '../../widgets/rounds/round_players_score_row.dart';
import '../../widgets/rounds/round_score_column.dart';
import '../../widgets/rounds/round_title_bar.dart';
import '../../widgets/rounds/selectable_chip.dart';

/// The live round content shared by [ComeBackRoundScreen] (round 4) and
/// [BreakerRoundScreen] (round 5): confirmed to have the identical game
/// flow and answering behavior — both players may answer simultaneously,
/// gated only by each player's own `makeupTryCount`/`maxMakeupTryCount`,
/// never by `currentTurn`. Comeback is the source of truth this content was
/// built for; Breaker reuses it exactly rather than duplicating it. The one
/// thing that differs between the two rounds — the heading text — is
/// derived from the live session phase via [PlayGameStrings.roundHeadingFor],
/// the same lookup the shared round-intro dialog already uses.
class ComebackStyleRoundContent extends ConsumerStatefulWidget {
  const ComebackStyleRoundContent({super.key});

  @override
  ConsumerState<ComebackStyleRoundContent> createState() =>
      _ComebackStyleRoundContentState();
}

class _ComebackStyleRoundContentState
    extends BaseState<ComebackStyleRoundContent> {
  @override
  bool get handleInternetConnection => false;

  /// Which chip was last tapped — locks the box until the server gives
  /// authoritative evidence of a new answering opportunity: a new question,
  /// or the same question with a fresh try count (e.g. after a wrong
  /// answer). Never unlocked from a local assumption, and never used to
  /// gate eligibility — [GameController.canSubmitComebackAnswer] is the
  /// single source of truth for that (Comeback and Breaker alike).
  int? _selectedAnswer;

  /// Set once `CorrectAnswer` resolves the current question — for both
  /// players, since the question is over whoever answered it. Cleared only
  /// when a new question arrives, the same authoritative signal that clears
  /// [_selectedAnswer].
  bool _questionResolved = false;

  /// Whether the question/answer UI may be revealed yet. `GameUpdated` can
  /// (and does, per real-device evidence) deliver the question well before
  /// the round is actually active, and `TimeStarted`'s own Start Timer
  /// dialog is presentation only — neither reveals anything. The single
  /// live-flow trigger is the server's first `TimerUpdatedSeconds` for this
  /// question (`lastEventName`, not `isTimerStarted` — that flips on
  /// `TimeStarted`, too early). The underlying server state
  /// (`session.game?.currentQuestion`) is untouched either way — only this
  /// widget's presentation of it is gated, and once revealed it never hides
  /// again for a later NextQuestion/GameUpdated on the same round.
  bool _questionVisible = false;

  /// What is actually rendered — sourced **only** from `NextQuestion`
  /// events (or a restore's own snapshot, which has no `NextQuestion`
  /// history to draw on). `session.game?.currentQuestion` is shared with
  /// `GameUpdated`, which can carry the FULL question/answers well before
  /// the round is active; rendering that field directly is exactly the bug
  /// real-device evidence reported — the server sends the question
  /// progressively through repeated `NextQuestion` for the same id
  /// (growing text each time), and that progression, not `GameUpdated`'s
  /// snapshot, is what must reach the screen. Every `NextQuestion` — same
  /// id or a genuinely new one — simply overwrites this with its own
  /// content, which already reproduces both the growing-text and
  /// new-question-replaces-old cases with no extra logic.
  CurrentQuestion? _displayedQuestion;

  @override
  void initState() {
    super.initState();
    // This screen (re)building mid-round — e.g. landing on a session that
    // was already mid-question — means TimerUpdatedSeconds already reached
    // this device (or another) before this widget started observing state,
    // and there is no NextQuestion history available to replay. The
    // snapshot itself is the best available truth here, unlike the live
    // GameUpdated-before-TimerUpdatedSeconds case this fix targets.
    final session = ref.read(gameControllerProvider);
    // A question in the snapshot is the other half of the evidence. A round
    // that has only just begun has none — `NextRoundStarted` clears it — and
    // the countdown flags left standing at that boundary are the *previous*
    // round's, not this one's. Without this, entering Comeback/Breaker from
    // a round whose countdown was still running latched this widget open at
    // mount, and the new round's first `NextQuestion` then rendered its
    // chips with no countdown of its own having started.
    if (_hasRunningCountdown(session) && session.game?.currentQuestion != null) {
      _questionVisible = true;
      _displayedQuestion = session.game?.currentQuestion;
    }
  }

  /// A genuinely running countdown: the timer is going **and** has time on it.
  ///
  /// `currentTimerValue` on its own is not that. Stopping a countdown is a
  /// freeze everywhere in this codebase — `_frozenTimerGame()` says so
  /// explicitly and nothing ever resets the value to zero — so the previous
  /// question's, or (across `NextRoundStarted`) the previous *round's*, last
  /// value is still sitting in the snapshot when this round begins. Reading
  /// the value alone therefore latched this round open at mount and let its
  /// first `NextQuestion` render chips before the round's own countdown had
  /// started. This is the same evidence [GameController] already requires to
  /// re-derive answering from a restore snapshot.
  bool _hasRunningCountdown(GameSessionState? session) =>
      session?.game?.isTimerStarted == true &&
      (session?.game?.currentTimerValue ?? 0) > 0;

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    final answerEntities = _questionVisible
        ? (_displayedQuestion?.answers ?? const <QuestionAnswer>[])
        : const <QuestionAnswer>[];
    final answers = [
      for (final answer in answerEntities)
        answer.displayText(isArabic: isArabic),
    ];
    final questionTitle = _questionVisible
        ? (_displayedQuestion?.displayText(isArabic: isArabic) ?? '')
        : '';
    final questionCount = session.game?.currentQuestion?.countLabel ?? '';

    ref.listen(gameControllerProvider, (previous, next) {
      if (next.lastEventName == PlayGameHubEvents.nextQuestion) {
        // The one source of truth for what to render — captured exactly as
        // the server sent it, id-for-id and character-for-character, never
        // reconstructed or animated locally.
        setState(() => _displayedQuestion = next.game?.currentQuestion);
      }
      if (!_questionVisible) {
        // The primary live-flow trigger: the server's TimerUpdatedSeconds
        // event, regardless of its value. TimeStarted's Start Timer dialog
        // and a bare GameUpdated/NextQuestion carrying the question never
        // reveal it on their own — and revealing does not, by itself,
        // populate _displayedQuestion; that still waits for NextQuestion.
        final revealedByTimerUpdate =
            next.lastEventName == PlayGameHubEvents.timerUpdatedSeconds;
        // Arriving into an already-running countdown — a restore, or this
        // device's first observation of a round already mid-question — is
        // the same TimerUpdatedSeconds-lineage evidence: a real positive
        // value already recorded server-side, so there is no fresh event
        // left to wait for. This is currentTimerValue, not isTimerStarted,
        // crossing from non-positive to positive. Unlike the pure
        // TimerUpdatedSeconds case, there is no NextQuestion history behind
        // this arrival, so the snapshot itself becomes what is displayed.
        //
        // The value must be *running*, not merely present: a snapshot taken
        // after a freeze still carries the last value, and treating that as
        // an active countdown revealed the chips with no countdown at all.
        // The crossing test stays on the value itself, so a TimeStarted that
        // flips the flag while a stale value is still standing is not a
        // crossing and still reveals nothing.
        final arrivedAlreadyActive =
            (previous?.game?.currentTimerValue ?? 0) <= 0 &&
                (next.game?.currentTimerValue ?? 0) > 0 &&
                next.game?.isTimerStarted == true &&
                next.lastEventName != PlayGameHubEvents.timerUpdatedSeconds;
        if (revealedByTimerUpdate || arrivedAlreadyActive) {
          setState(() {
            _questionVisible = true;
            if (arrivedAlreadyActive) {
              _displayedQuestion = next.game?.currentQuestion;
            }
          });
        }
      }
      if (_didQuestionChange(previous, next)) {
        if (_selectedAnswer != null || _questionResolved) {
          setState(() {
            _selectedAnswer = null;
            _questionResolved = false;
          });
        }
        return;
      }
      // CorrectAnswer ends the question for both players, not only whoever
      // answered it — no further submission until the next question.
      if (next.lastEventName == PlayGameHubEvents.correctAnswer &&
          !_questionResolved) {
        setState(() => _questionResolved = true);
        return;
      }
      // A try count that moved for the *same* question is the server's own
      // evidence of a new opportunity (e.g. after a wrong answer) — the only
      // other authoritative reason to release the local lock.
      final triesChanged =
          previous?.me?.makeupTryCount != next.me?.makeupTryCount;
      if (triesChanged && _selectedAnswer != null) {
        setState(() => _selectedAnswer = null);
      }
    });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RoundBackgroundImage(),
          SafeArea(
            left: false,
            right: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                const RoundHeaderBar(),
                const SizedBox(height: 10),
                RoundTitleBar(
                  heading: strings.roundHeadingFor(session.phase),
                  count: questionCount,
                ),
                const SizedBox(height: 25),
                _playersScoreUi(strings, session),
                const SizedBox(height: 15),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RoundInfoCard(text: questionTitle),
                        const SizedBox(height: 15),
                        // Always visible to both players — no turn gate.
                        // Only selection/submission is gated, by each
                        // player's own remaining tries.
                        SelectableChipsBox(
                          items: answers,
                          selectedIndex: _selectedAnswer,
                          onSelected: (index) =>
                              _onAnswerSelected(index, answerEntities),
                        ),
                        const SizedBox(height: 16),
                        _actionsRowUi(session),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _didQuestionChange(GameSessionState? previous, GameSessionState next) {
    final prev = previous?.game?.currentQuestion;
    final nextQuestion = next.game?.currentQuestion;
    if (prev?.id != nextQuestion?.id ||
        prev?.questionNumber != nextQuestion?.questionNumber) {
      return true;
    }
    final prevIds = [
      for (final answer in prev?.answers ?? const <QuestionAnswer>[])
        answer.id,
    ];
    final nextIds = [
      for (final answer in nextQuestion?.answers ?? const <QuestionAnswer>[])
        answer.id,
    ];
    if (prevIds.length != nextIds.length) {
      return true;
    }
    for (var i = 0; i < prevIds.length; i++) {
      if (prevIds[i] != nextIds[i]) {
        return true;
      }
    }
    return false;
  }

  Future<void> _onAnswerSelected(
    int index,
    List<QuestionAnswer> answers,
  ) async {
    final notifier = ref.read(gameControllerProvider.notifier);
    // One in-flight submission per opportunity: the lock releases only from
    // the server-authoritative evidence in ref.listen above, never
    // optimistically after a successful dispatch.
    if (_questionResolved ||
        _selectedAnswer != null ||
        !notifier.canSubmitComebackAnswer ||
        index < 0 ||
        index >= answers.length) {
      return;
    }
    final answerId = answers[index].id;
    if (answerId == null) {
      return;
    }
    setState(() => _selectedAnswer = index);
    final sent = await notifier.submitComebackAnswer(answerId);
    // Nothing left the device, so the lock would block a retry forever.
    if (!sent && mounted) {
      setState(() => _selectedAnswer = null);
    }
  }

  Widget _playersScoreUi(PlayGameStrings strings, GameSessionState session) {
    final me = session.me;
    final opponent = session.opponent;
    return RoundPlayersScoreRow(
      leftPlayer: RoundPlayerAvatar(
        name: opponent?.playerName ?? '',
        imageUrl: opponent?.profileImageUrl,
        playerId: opponent?.id,
        isTurn: session.isOpponentTurn,
      ),
      score: RoundScoreColumn(
        resultLabel: strings.result,
        scoreText: session.scoreLabel,
      ),
      rightPlayer: RoundPlayerAvatar(
        name: me?.playerName ?? '',
        imageUrl: me?.profileImageUrl,
        playerId: me?.id,
        isTurn: session.isMyTurn,
        isLocalUser: true,
      ),
    );
  }

  Widget _actionsRowUi(GameSessionState session) {
    final me = session.me;
    return RoundActionsRow(
      leading: RoundAttemptsInfo(
        tryCount: me?.makeupTryCount ?? 0,
        maxTryCount: me?.maxMakeupTryCount ?? 0,
      ),
    );
  }
}

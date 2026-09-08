import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game_session_state.dart';
import '../../../features/games/domain/entities/question_answer.dart';
import '../../../l10n/play_game_strings.dart';
import '../../game_controller/game_controller.dart';
import '../../widgets/rounds/round_actions_row.dart';
import '../../widgets/rounds/round_background_image.dart';
import '../../widgets/rounds/round_header_bar.dart';
import '../../widgets/rounds/round_info_card.dart';
import '../../widgets/rounds/round_player_avatar.dart';
import '../../widgets/rounds/round_players_score_row.dart';
import '../../widgets/rounds/round_score_column.dart';
import '../../widgets/rounds/round_title_bar.dart';
import '../../widgets/rounds/round_touch_target.dart';
import '../../widgets/rounds/selectable_chip.dart';

class WdykRoundScreen extends ConsumerStatefulWidget {
  const WdykRoundScreen({super.key});

  @override
  ConsumerState<WdykRoundScreen> createState() => _WdykRoundScreenState();
}

class _WdykRoundScreenState extends BaseState<WdykRoundScreen> {
  @override
  bool get handleInternetConnection => false;

  static const _maxStrikes = 3;

  int? _selectedAnswer;

  bool _passRequested = false;

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    final question = session.game?.currentQuestion;
    final answerEntities = question?.answers ?? const <QuestionAnswer>[];
    final answers = [
      for (final answer in answerEntities)
        answer.displayText(isArabic: isArabic),
    ];
    final questionTitle = question?.displayText(isArabic: isArabic) ?? '';
    final questionCount = question?.countLabel ?? '';
    // Answering opens on the first TimerUpdatedSeconds and closes when the
    // countdown runs out — the shared rule, not a WDYK one.
    final isUserTurn = session.isMyTurn && session.answersUnlocked;

    ref.listen(gameControllerProvider, (previous, next) {
      // The server owns the pass budget; a changed value is its confirmation.
      if (_passRequested && previous?.me?.passes != next.me?.passes) {
        setState(() => _passRequested = false);
      }
      if (_didQuestionChange(previous, next)) {
        if (_selectedAnswer != null) {
          setState(() => _selectedAnswer = null);
        }
        return;
      }
      final wasMyTurn = previous?.isMyTurn ?? false;
      final isMyTurn = next.isMyTurn;
      if (wasMyTurn && !isMyTurn && _selectedAnswer != null) {
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
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const RoundHeaderBar(),
                  const SizedBox(height: 10),
                  RoundTitleBar(
                    heading: strings.roundHeading,
                    count: questionCount,
                  ),
                  const SizedBox(height: 25),
                  _playersScoreUi(strings, session),
                  const SizedBox(height: 25),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RoundInfoCard(text: questionTitle),
                        const SizedBox(height: 15),
                        SelectableChipsBox(
                          items: isUserTurn ? answers : const [],
                          selectedIndex: isUserTurn ? _selectedAnswer : null,
                          onSelected: (index) => _onAnswerSelected(
                            index,
                            answerEntities,
                            isUserTurn,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _actionsRowUi(strings, session),
                      ],
                    ),
                  ),
                ],
              ),
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
      for (final answer in prev?.answers ?? const <QuestionAnswer>[]) answer.id,
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
    bool isUserTurn,
  ) async {
    // One submission per question: 1v1 answers are single-choice, and
    // _selectedAnswer is cleared when the question changes or the turn is lost.
    if (!isUserTurn ||
        _selectedAnswer != null ||
        index < 0 ||
        index >= answers.length) {
      return;
    }
    final answerId = answers[index].id;
    if (answerId == null) {
      return;
    }
    setState(() => _selectedAnswer = index);
    final sent =
        await ref.read(gameControllerProvider.notifier).submitAnswer(answerId);
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
        trailing: _strikesUi(opponent?.penalty ?? 0),
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
        trailing: _strikesUi(me?.penalty ?? 0),
        flipTrailing: true,
      ),
    );
  }

  Widget _strikesUi(int penalty) {
    final count = penalty.clamp(0, _maxStrikes);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _maxStrikes; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          AppImageView(
            assetPath: AppAssets.strikeIcon,
            package: AppAssets.packageName,
            size: 15,
            color: i < count ? AppColors.error : AppColors.strikeInactive,
          ),
        ],
      ],
    );
  }

  Widget _actionsRowUi(PlayGameStrings strings, GameSessionState session) {
    return RoundActionsRow(
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _passButtonUi(strings, session),
          const SizedBox(height: 8),
          _passAlertUi(strings),
        ],
      ),
    );
  }

  Future<void> _onPassPressed() async {
    setState(() => _passRequested = true);
    final sent = await ref.read(gameControllerProvider.notifier).pass();
    // A pass that never dispatched would otherwise leave the button dead:
    // the guard normally clears only when the server reports a new passes.
    if (!sent && mounted) {
      setState(() => _passRequested = false);
    }
  }

  Widget _passButtonUi(PlayGameStrings strings, GameSessionState session) {
    final me = session.me;
    final canPass = !_passRequested &&
        session.isMyTurn &&
        (me?.passes ?? 0) > 0 &&
        (me?.penalty ?? 0) >= 2;
    return Opacity(
      opacity: canPass ? 1 : 0.4,
      child: GestureDetector(
        // Opaque so the whole 48dp block below is tappable, not just the
        // pill's own painted pixels.
        behavior: HitTestBehavior.opaque,
        onTap: canPass ? _onPassPressed : null,
        child: ConstrainedBox(
          // The pill stays its designed size; only the hit area grows around
          // it, to the 48dp Android / 44pt iOS minimum. Nothing visible
          // changes — the extra height is transparent padding.
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              // minHeight, not a fixed height: at normal text scale the
              // content is shorter than 30 so the pill is exactly 30 as
              // before, but a raised text scale now grows it instead of
              // clipping the label inside it.
              constraints: const BoxConstraints(minHeight: 30),
              padding: const EdgeInsetsDirectional.only(start: 15, end: 20),
              decoration: BoxDecoration(
                color: AppColors.button,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppImageView(
                    assetPath: AppAssets.passIcon,
                    package: AppAssets.packageName,
                    width: 23,
                    height: 15,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                  // The pill is sized by its content, so an unbounded label
                  // pushed the row past whatever width was left for it. It
                  // now yields instead; at normal scale it fits on one line
                  // and nothing changes.
                  Flexible(
                    child: AppTextView(
                      strings.pass,
                      fontWeight: AppFontWeight.medium,
                      fontSize: 12,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passAlertUi(PlayGameStrings strings) {
    // The round is laid out RTL for its mirrored chrome; this alert still
    // reads in the app language's own direction. Its `!` is interior to an
    // LTR run so it does not itself reorder — what RTL got wrong here is
    // `TextAlign.start`, which resolved to the right-hand edge for English.
    return Directionality(
      textDirection: AppLanguage.isArabic(ref.watch(appLanguageProvider))
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AppTextView(
        strings.passAlert,
        fontWeight: AppFontWeight.regular,
        fontSize: 10,
        color: AppColors.onBackground.withValues(alpha: 0.5),
        textAlign: TextAlign.start,
      ),
    );
  }
}

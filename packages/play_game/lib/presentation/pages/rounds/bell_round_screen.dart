import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game_session_state.dart';
import '../../../features/games/domain/entities/question_answer.dart';
import '../../../l10n/play_game_strings.dart';
import '../../game_controller/game_controller.dart';
import '../../widgets/rounds/round_background_image.dart';
import '../../widgets/rounds/round_header_bar.dart';
import '../../widgets/rounds/round_info_card.dart';
import '../../widgets/rounds/round_player_avatar.dart';
import '../../widgets/rounds/round_players_score_row.dart';
import '../../widgets/rounds/round_report_button.dart';
import '../../widgets/rounds/round_score_column.dart';
import '../../widgets/rounds/round_title_bar.dart';
import '../../widgets/rounds/selectable_chip.dart';

class BellRoundScreen extends ConsumerStatefulWidget {
  const BellRoundScreen({super.key});

  @override
  ConsumerState<BellRoundScreen> createState() => _BellRoundScreenState();
}

class _BellRoundScreenState extends BaseState<BellRoundScreen> {
  @override
  bool get handleInternetConnection => false;

  // Which chip was last tapped — locks the box until a server round event
  // (a new question, or the turn moving on) clears it. Never unlocked from
  // a local assumption.
  int? _selectedAnswer;

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);
    final notifier = ref.read(gameControllerProvider.notifier);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    final question = session.game?.currentQuestion;
    final answerEntities = question?.answers ?? const <QuestionAnswer>[];
    final answers = [
      for (final answer in answerEntities)
        answer.displayText(isArabic: isArabic),
    ];
    final questionTitle = question?.displayText(isArabic: isArabic) ?? '';
    final questionCount = question?.countLabel ?? '';
    // Chips belong to the player ChangeTurn named, and only once a countdown
    // is running — the same shared rule WDYK's turn already uses.
    final isUserTurn = session.isMyTurn && session.answersUnlocked;

    ref.listen(gameControllerProvider, (previous, next) {
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
            child: Column(
              children: [
                const SizedBox(height: 8),
                const RoundHeaderBar(),
                const SizedBox(height: 10),
                RoundTitleBar(
                  heading: strings.bellRoundHeading,
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
                        // The container itself stays up before a turn is
                        // decided and while it is the opponent's — only the
                        // chip options are gated by isUserTurn, same as WDYK.
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
                        const Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: RoundReportButton(),
                        ),
                      ],
                    ),
                  ),
                ),
                if (notifier.isBellVisible) _bellButtonUi(strings, notifier),
                const SizedBox(height: 5),
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
    // One submission per question, same as WDYK: _selectedAnswer is cleared
    // only by a question change or losing the turn, never by this method.
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

  // The buzz sound lands on the tap, before RingBell's own canRingBell
  // re-check — the button is only tappable while the race is on.
  void _onBellPressed() {
    unawaited(audio.playBellRound());
    unawaited(ref.read(gameControllerProvider.notifier).ringBell());
  }

  Widget _bellButtonUi(PlayGameStrings strings, GameController notifier) {
    final canRingBell = notifier.canRingBell;
    return Opacity(
      opacity: canRingBell ? 1 : 0.4,
      child: GestureDetector(
        onTap: canRingBell ? _onBellPressed : null,
        child: SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const AppImageView(
                assetPath: AppAssets.purpleCircle,
                package: AppAssets.packageName,
                size: 180,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppImageView(
                      assetPath: AppAssets.bellIcon,
                      package: AppAssets.packageName,
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    // Title text reads in the app language's direction, not
                    // the round's mirrored layout direction.
                    Directionality(
                      textDirection:
                          AppLanguage.isArabic(ref.watch(appLanguageProvider))
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      child: AppTextView(
                        strings.bellRoundTitle,
                        fontWeight: AppFontWeight.medium,
                        fontSize: 18,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

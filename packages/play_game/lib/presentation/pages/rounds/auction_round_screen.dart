import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/play_game_hub_events.dart';
import '../../../domain/auction_phase.dart';
import '../../../domain/game_session_state.dart';
import '../../../features/games/domain/entities/question_answer.dart';
import '../../../l10n/play_game_strings.dart';
import '../../dialogs/count_answer_dialog.dart';
import '../../game_controller/game_controller.dart';
import '../../game_controller/round_sub_panel.dart';
import '../../widgets/rounds/round_actions_row.dart';
import '../../widgets/rounds/round_attempts_info.dart';
import '../../widgets/rounds/round_background_image.dart';
import '../../widgets/rounds/round_header_bar.dart';
import '../../widgets/rounds/round_info_card.dart';
import '../../widgets/rounds/round_player_avatar.dart';
import '../../widgets/rounds/round_players_score_row.dart';
import '../../widgets/rounds/round_report_button.dart';
import '../../widgets/rounds/round_score_column.dart';
import '../../widgets/rounds/round_title_bar.dart';
import '../../widgets/rounds/selectable_chip.dart';

class AuctionRoundScreen extends ConsumerStatefulWidget {
  const AuctionRoundScreen({super.key});

  @override
  ConsumerState<AuctionRoundScreen> createState() => _AuctionRoundScreenState();
}

class _AuctionRoundScreenState extends BaseState<AuctionRoundScreen>
    with HubEventMixin {
  @override
  bool get handleInternetConnection => false;

  @override
  List<String> get listenHubEvents => PlayGameHubEvents.auctionScreenEvents;

  @override
  void onEventReceived(String name, Map<String, dynamic>? data) {
    switch (name) {
      case PlayGameHubEvents.auctionBiddingPhaseStarted:
      case PlayGameHubEvents.playerBidded:
      case PlayGameHubEvents.auctionAnswerPhaseStarted:
      case PlayGameHubEvents.showAuctionConfirmationDialog:
        // Auction-only — shared question/timer events live on GameController.
        break;
      case PlayGameHubEvents.playerLostAuctionRound:
        ref
            .read(gameControllerProvider.notifier)
            .onAuctionRoundLost(data, _roundDialogPresenter);
      case PlayGameHubEvents.playerWonAuctionRound:
        ref
            .read(gameControllerProvider.notifier)
            .onAuctionRoundWon(data, _roundDialogPresenter);
      default:
        break;
    }
  }

  static const _answerTimeout = '30';

  /// Which chip was last tapped — highlight only, cleared when the server
  /// reports a score.
  int? _selectedAnswer;

  /// Blocks a second tap while one submission is in flight.
  bool _answerRequested = false;

  /// Blocks a second Bid while one is in flight. Not optimistic state: it is
  /// released the moment a dispatch fails, and otherwise until the server's
  /// PlayerBidded lands.
  bool _bidRequested = false;

  /// One "start increasing" overlay per bidding phase; reset on the way out.
  bool _startIncreasingShown = false;
  late final TextEditingController _countController;

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController();
    // The phase is usually already `bidding` by the time this screen first
    // builds — showPhase applies the metadata before the round is rendered —
    // and ref.listen never fires for state that already exists. Without this
    // pass the overlay is only ever requested on a later transition, which is
    // why it never appeared on device.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeShowStartIncreasing(ref.read(gameControllerProvider));
      }
    });
  }

  /// Shows the overlay the first time this bidding phase is one this player
  /// may act in. Eligibility is re-checked rather than assumed at phase start,
  /// so a ChangeTurn arriving after AuctionBiddingPhaseStarted still counts —
  /// no ordering is inferred either way.
  void _maybeShowStartIncreasing(GameSessionState session) {
    if (session.auctionPhase != AuctionPhase.bidding) {
      _startIncreasingShown = false;
      return;
    }
    if (_startIncreasingShown) {
      return;
    }
    final notifier = ref.read(gameControllerProvider.notifier);
    if (!notifier.canBid) {
      return;
    }
    _startIncreasingShown = true;
    notifier.showAuctionStartIncreasing(_roundDialogPresenter);
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  /// Same presenter [GameControllerScreen] gives the other handlers: a
  /// round overlay goes to the sub-panel layer that screen hosts (this
  /// screen is inside its subtree), everything else keeps its dialog route.
  Future<void> Function({required Widget child, bool barrierDismissible})
      get _roundDialogPresenter => roundDialogPresenter(
            ref,
            // The same guard showAppDialog applies before pushing a route.
            canPresent: () =>
                mounted && ModalRoute.of(context)?.isActive != false,
            fallback: ({
              required Widget child,
              bool barrierDismissible = true,
            }) =>
                showAppDialog<void>(
              child: child,
              barrierDismissible: barrierDismissible,
            ),
          );
  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);
    final questionCount = session.game?.currentQuestion?.countLabel ?? '';
    // The phase is the server's, never the tap's: Take Turn does not switch
    // panels, AuctionAnswerPhaseStarted does.
    final isAnswering = session.auctionPhase == AuctionPhase.answering;

    ref.listen(gameControllerProvider, (previous, next) {
      // The server confirmed a bid — whoever made it, this player's own
      // request is settled.
      if (_bidRequested && previous?.currentBid != next.currentBid) {
        setState(() => _bidRequested = false);
      }
      // A new bidding phase starts from an empty field, whatever was typed
      // for the previous question.
      if (previous?.auctionPhase != AuctionPhase.bidding &&
          next.auctionPhase == AuctionPhase.bidding &&
          _countController.text.isNotEmpty) {
        _countController.clear();
      }
      // A bidding phase this player may act in — the legacy startIncreasing().
      // Read from reduced state, so it does not depend on event ordering.
      _maybeShowStartIncreasing(next);
      // Server feedback on the last answer — drop the highlight so the next
      // one can be tapped.
      final scoreMoved = previous?.currentScore != next.currentScore ||
          previous?.wrongScore != next.wrongScore;
      if (_selectedAnswer != null && scoreMoved) {
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
                  heading: strings.auctionRoundHeading,
                  count: questionCount,
                ),
                SizedBox(height: _blockGap(context)),
                _playersScoreUi(strings, session),
                SizedBox(height: _blockGap(context)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Column(
                              mainAxisAlignment: isAnswering
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (isAnswering)
                                  _gameBodyUi(strings, session)
                                else
                                  _biddingTopUi(session),
                                if (!isAnswering)
                                  _biddingBottomUi(strings, session),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Whitespace between the header blocks, eased back as text grows.
  ///
  /// The blocks above the scroll region — header bar, title bar, score row —
  /// are laid out at their natural height and grow with the text scale,
  /// while these gaps stayed a constant 25 each. On a 320x568 screen at the
  /// maximum accessibility scale that block ran 21px past the viewport on its
  /// own, leaving the Expanded below it nothing and overflowing the column.
  ///
  /// Reclaiming it from the gaps keeps every word, every font size and every
  /// control exactly as designed — larger text already separates the blocks
  /// visually, so it needs less blank space between them, not more. At scale
  /// 1.0 this returns 25 and the layout is unchanged.
  double _blockGap(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale <= 1) {
      return _maxBlockGap;
    }
    return (_maxBlockGap / scale).clamp(_minBlockGap, _maxBlockGap);
  }

  static const _maxBlockGap = 25.0;
  static const _minBlockGap = 12.0;

  Widget _playersScoreUi(PlayGameStrings strings, GameSessionState session) {
    // Turn flags come from ChangeTurn, the same source the bid controls use.
    final me = session.me;
    final opponent = session.opponent;
    return RoundPlayersScoreRow(
      leftPlayer: RoundPlayerAvatar(
        name: opponent?.playerName ?? '',
        imageUrl: opponent?.profileImageUrl,
        playerId: opponent?.id,
        isTurn: session.isOpponentTurn,
        trailingSpacing: 8,
        trailing: _auctionProgressUi(session, opponent?.id),
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
        trailingSpacing: 8,
        trailing: _auctionProgressUi(session, me?.id),
      ),
    );
  }

  /// `current/goal` on the seat named by AuctionAnswerPhaseStarted, and only
  /// there — the other player has no auction progress of their own.
  Widget? _auctionProgressUi(GameSessionState session, String? playerId) {
    final answeringPlayerId = session.answeringPlayerId;
    if (answeringPlayerId == null || playerId == null) {
      return null;
    }
    final player = session.me?.id == playerId ? session.me : session.opponent;
    if (player == null || !player.matchesHubUserId(answeringPlayerId)) {
      return null;
    }
    final goal = session.goalScore;
    if (goal == null) {
      return null;
    }
    return AppNumberTextView(
      '${session.currentScore ?? 0}/$goal',
      fontSize: 12,
      fontWeight: AppFontWeight.enBold,
      color: AppColors.green,
      textAlign: TextAlign.center,
    );
  }

  Widget _gameBodyUi(PlayGameStrings strings, GameSessionState session) {
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    final question = session.game?.currentQuestion;
    final answerEntities = question?.answers ?? const <QuestionAnswer>[];
    final answers = [
      for (final answer in answerEntities)
        answer.displayText(isArabic: isArabic),
    ];
    // Only the player named by AuctionAnswerPhaseStarted sees chips; the one
    // watching keeps the layout space but has nothing to tap.
    final notifier = ref.read(gameControllerProvider.notifier);
    // The shared rule: no answering until a countdown is running.
    final isAnswerer = notifier.isAuctionAnswerer && session.answersUnlocked;
    // Selection closes once the server's wrong-attempt allowance is spent.
    final canSelect = notifier.canSubmitAuctionAnswer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoundInfoCard(text: question?.displayText(isArabic: isArabic) ?? ''),
        const SizedBox(height: 15),
        Opacity(
          opacity: !isAnswerer || canSelect ? 1 : 0.4,
          child: SelectableChipsBox(
            items: isAnswerer ? answers : const [],
            selectedIndex: isAnswerer ? _selectedAnswer : null,
            onSelected: (index) => _onAnswerSelected(index, answerEntities),
          ),
        ),
        const SizedBox(height: 16),
        _actionsRowUi(strings, session),
      ],
    );
  }

  /// "Number of attempts" for the answering player.
  ///
  /// Only rendered from [_gameBodyUi], so it is structurally absent during
  /// bidding — the legacy layout shows this row on the answer screen only.
  ///
  /// The values stay the confirmed `makeupTryCount` / `maxMakeupTryCount`:
  /// [GamePlayer] carries no generic tryCount, so there is no mapping to adopt.
  /// Only the label is the legacy `number_of_attempts` one — `Strike` stays
  /// with the wrong-answer dialog.
  Widget _actionsRowUi(PlayGameStrings strings, GameSessionState session) {
    final player =
        ref.read(gameControllerProvider.notifier).auctionAnsweringPlayer;
    // Visibility only: the row belongs to the player whose turn it is, so the
    // one watching sees nothing. The counters themselves are untouched.
    if (!session.isMyTurn || player == null || player.maxMakeupTryCount <= 0) {
      return const RoundActionsRow(leading: SizedBox.shrink());
    }
    return RoundActionsRow(
      leading: RoundAttemptsInfo(
        tryCount: player.makeupTryCount,
        maxTryCount: player.maxMakeupTryCount,
      ),
    );
  }

  Future<void> _onAnswerSelected(
    int index,
    List<QuestionAnswer> answers,
  ) async {
    final notifier = ref.read(gameControllerProvider.notifier);
    if (!notifier.canSubmitAuctionAnswer ||
        _answerRequested ||
        index < 0 ||
        index >= answers.length) {
      return;
    }
    final answerId = answers[index].id;
    if (answerId == null) {
      return;
    }
    // Visual only. The score moves when the server says so.
    setState(() {
      _selectedAnswer = index;
      _answerRequested = true;
    });
    final sent = await notifier.submitAuctionAnswer(answerId);
    if (!mounted) {
      return;
    }
    setState(() {
      _answerRequested = false;
      if (!sent) {
        _selectedAnswer = null;
      }
    });
  }

  Widget _biddingTopUi(GameSessionState session) {
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    final question = session.game?.currentQuestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The question being bid on — the same one the answer panel shows.
        RoundInfoCard(text: question?.displayText(isArabic: isArabic) ?? ''),
        const SizedBox(height: 16),
        const Align(
          alignment: AlignmentDirectional.centerEnd,
          child: RoundReportButton(),
        ),
      ],
    );
  }

  Widget _biddingBottomUi(PlayGameStrings strings, GameSessionState session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title text reads in the app language's direction, not the round's
        // mirrored layout direction — same rule as the heading bar.
        Directionality(
          textDirection: AppLanguage.isArabic(ref.watch(appLanguageProvider))
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: AppTextView(
            strings.auctionRoundTitle,
            fontWeight: AppFontWeight.medium,
            fontSize: 26,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        AppNumberTextView(
          // The standing bid, from PlayerBidded or restored metadata.
          session.currentBid?.toString() ?? '00',
          fontSize: 20,
          fontWeight: AppFontWeight.enBold,
          color: AppColors.yellow,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        // Prompt text reads in the app language's direction, not the round's
        // mirrored layout direction — the trailing `seconds?` and the
        // embedded timeout both reorder against the words otherwise.
        Directionality(
          textDirection: AppLanguage.isArabic(ref.watch(appLanguageProvider))
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: AppTextView(
            strings.howManyAnswersPrompt(_answerTimeout),
            fontWeight: AppFontWeight.bold,
            fontSize: 12,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 10),
        AppTextField(
          controller: _countController,
          hint: strings.chooseTheNumberOfAnswers,
          fontWeight: AppFontWeight.bold,
          fontSize: 12,
          color: const Color(0xCB47474E),
          fillColor: AppColors.onBackground,
          borderColor: AppColors.blue,
          borderWidth: 2,
          textAlign: TextAlign.center,
          focusedBorderWidth: 2,
          readOnly: true,
          showCursor: false,
          enableInteractiveSelection: false,
          keyboardType: TextInputType.none,
          onTap: session.isMyTurn ? _showCountPicker : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
        ),
        const SizedBox(height: 16),
        _biddingActionsUi(strings, session),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _biddingActionsUi(PlayGameStrings strings, GameSessionState session) {
    final notifier = ref.read(gameControllerProvider.notifier);
    // isBiding (who bid last) and isMyTurn (ChangeTurn) are separate gates;
    // Bid needs both, Take Turn needs a standing bid and the turn.
    // Legacy parity: the button stays live without a chosen number, and the
    // empty case is answered with an error snackbar from the tap handler.
    final canBid = notifier.canBid && !_bidRequested;
    final canTakeTurn = notifier.canTakeTurn;
    return Row(
      children: [
        Expanded(
          child: _biddingButtonUi(
            label: strings.bidding,
            color: AppColors.purple,
            enabled: canBid,
            onTap: _onBidding,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _biddingButtonUi(
            label: strings.takeTheTurn,
            color: AppColors.button,
            enabled: canTakeTurn,
            onTap: _onTakeTurn,
          ),
        ),
      ],
    );
  }

  Widget _biddingButtonUi({
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 45,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AppTextView(
            label,
            fontWeight: AppFontWeight.medium,
            fontSize: 16,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// The picked value, or null when it is empty or outside the allowed range.
  int? _pickedBid(GameSessionState session) {
    final value = int.tryParse(_countController.text.trim());
    if (value == null) {
      return null;
    }
    final notifier = ref.read(gameControllerProvider.notifier);
    final max = notifier.auctionMaxBid;
    if (value < notifier.auctionMinBid || (max != null && value > max)) {
      return null;
    }
    return value;
  }

  Future<void> _showCountPicker() async {
    final notifier = ref.read(gameControllerProvider.notifier);
    final min = notifier.auctionMinBid;
    // Without a server answer count there is no ceiling to enforce, so the
    // picker keeps its own default rather than inventing one.
    final max = notifier.auctionMaxBid;
    final selected = await showAppDialog<int>(
      child: max == null
          ? CountAnswerDialog(
              selected: int.tryParse(_countController.text),
              min: min,
            )
          : CountAnswerDialog(
              selected: int.tryParse(_countController.text),
              min: min,
              max: max,
            ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _countController.text = selected.toString();
    });
  }

  Future<void> _onBidding() async {
    // The legacy check: no number chosen means no hub call, just the error.
    if (_countController.text.trim().isEmpty) {
      showAppSnackBar(
        ref.read(playGameStringsProvider).chooseTheNumberOfAnswers,
        type: ToastType.error,
      );
      return;
    }
    final session = ref.read(gameControllerProvider);
    final value = _pickedBid(session);
    if (value == null) {
      // A number is present but no longer in range — the existing guard
      // refuses it; the server is never asked.
      return;
    }
    setState(() => _bidRequested = true);
    final sent = await ref.read(gameControllerProvider.notifier).bid(value);
    if (!mounted) {
      return;
    }
    setState(() {
      if (sent) {
        // The number was for this bid only: the next turn starts from an empty
        // field, with the picker floor moved on by the server's new bid.
        _countController.clear();
      } else {
        // Nothing left the device, so the guard would block a retry forever.
        _bidRequested = false;
      }
    });
  }

  Future<void> _onTakeTurn() async {
    // No local phase change: the answer panel appears only when the server
    // sends AuctionAnswerPhaseStarted.
    await ref.read(gameControllerProvider.notifier).takeTurn();
  }
}

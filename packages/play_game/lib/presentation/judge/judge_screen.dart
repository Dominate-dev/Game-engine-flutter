import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/judge_state.dart';
import '../../features/games/domain/entities/game_player.dart';
import '../../l10n/judge_strings.dart';
import '../game_controller/game_session_handle.dart';
import '../widgets/rounds/round_background_image.dart';
import '../widgets/rounds/round_info_card.dart';
import '../widgets/rounds/round_title_bar.dart';
import 'judge_controller.dart';

/// Judge mode: one device, the judge's, recording two players who answer out
/// loud. Owns its route and its single exit, as GameControllerScreen does for
/// 1v1: every way out (Back, Exit, Done, a host-initiated leave) goes through
/// [_exit] once.
class JudgeScreen extends ConsumerStatefulWidget {
  const JudgeScreen({super.key, this.interestIds = const []});

  /// The host's interest ids for the questions; empty lets the server use the
  /// judge's own interests.
  final List<int> interestIds;

  @override
  ConsumerState<JudgeScreen> createState() => _JudgeScreenState();
}

class _JudgeScreenState extends BaseState<JudgeScreen> {
  static const _maxNameLength = 12;

  final _player1 = TextEditingController();
  final _player2 = TextEditingController();
  GameSessionHandle? _sessionHandle;
  bool _leaving = false;
  bool _exitDialogShown = false;
  int _bidSeat = 0;
  int _bidValue = 1;

  @override
  bool get handleInternetConnection => false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final handle = ref.read(gameSessionHandleProvider);
      _sessionHandle = handle;
      handle.register(_exit);
      unawaited(_begin());
    });
  }

  @override
  void dispose() {
    _sessionHandle?.unregister(_exit);
    _player1.dispose();
    _player2.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    if (!ref.read(signalRServiceProvider).hasLiveConnection) {
      await connectHub(error: ErrorType.none);
    }
    if (mounted) {
      await ref.read(judgeControllerProvider.notifier).create();
    }
  }

  void _exit({bool dispatchLeaveGame = true}) {
    if (_leaving) {
      return;
    }
    _leaving = true;
    if (dispatchLeaveGame) {
      unawaited(ref.read(judgeControllerProvider.notifier).leave());
    }
    if (mounted) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
    ref.read(gameSessionHandleProvider).notifyExited();
  }

  Future<void> _confirmExit() async {
    final state = ref.read(judgeControllerProvider);
    if (state.stage == JudgeStage.finished ||
        state.stage == JudgeStage.creating) {
      _exit(dispatchLeaveGame: state.stage != JudgeStage.finished);
      return;
    }
    if (_exitDialogShown) {
      return;
    }
    _exitDialogShown = true;
    final strings = ref.read(judgeStringsProvider);
    final shouldExit = await showAppDialog<bool>(
      child: ShowDialogGame(
        title: strings.exitConfirm,
        buttonText: strings.exit,
      ),
    );
    _exitDialogShown = false;
    if (shouldExit == true && mounted) {
      _exit();
    }
  }

  @override
  Widget buildPage(BuildContext context) {
    final state = ref.watch(judgeControllerProvider);
    final strings = ref.watch(judgeStringsProvider);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmExit());
        }
      },
      // A Material of its own: the name fields need one, and so does the
      // default text style everything else here inherits.
      child: Material(
        color: AppColors.background,
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const RoundBackgroundImage(),
              SafeArea(
                child: switch (state.stage) {
                  JudgeStage.creating => _waitingUi(strings, state),
                  JudgeStage.naming ||
                  JudgeStage.starting => _setupUi(strings, state),
                  JudgeStage.playing => _playingUi(strings, state, isArabic),
                  JudgeStage.finished => _resultUi(strings, state),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Header -----------------------------------------------------------------

  Widget _topBar(JudgeStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: AppTextView(
              strings.title,
              fontWeight: AppFontWeight.enBold,
              fontSize: 18,
            ),
          ),
          TextButton(
            onPressed: _confirmExit,
            child: AppTextView(
              strings.exit,
              color: AppColors.error,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // -- Creating / setup -------------------------------------------------------

  Widget _waitingUi(JudgeStrings strings, JudgeState state) {
    return Column(
      children: [
        _topBar(strings),
        Expanded(
          child: Center(
            child: state.failed
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppTextView(
                      strings.couldNotStart,
                      textAlign: TextAlign.center,
                    ),
                  )
                : const CircularProgressIndicator(color: AppColors.white),
          ),
        ),
      ],
    );
  }

  Widget _setupUi(JudgeStrings strings, JudgeState state) {
    final p1 = _player1.text.trim();
    final p2 = _player2.text.trim();
    final sameName = p1.isNotEmpty && p1.toLowerCase() == p2.toLowerCase();
    final starting = state.stage == JudgeStage.starting;
    final canStart = p1.isNotEmpty && p2.isNotEmpty && !sameName && !starting;
    return Column(
      children: [
        _topBar(strings),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextView(
                  strings.setupHint,
                  fontSize: 14,
                  color: AppColors.hint,
                ),
                const SizedBox(height: 20),
                _nameField(_player1, strings.player1),
                const SizedBox(height: 12),
                _nameField(_player2, strings.player2),
                if (sameName) ...[
                  const SizedBox(height: 8),
                  AppTextView(
                    strings.namesMustDiffer,
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ],
                if (state.failed) ...[
                  const SizedBox(height: 8),
                  AppTextView(
                    strings.couldNotStart,
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                ],
                const SizedBox(height: 24),
                GameButton(
                  label: starting ? strings.preparing : strings.startGame,
                  onPressed: canStart
                      ? () => ref
                            .read(judgeControllerProvider.notifier)
                            .start(p1, p2, widget.interestIds)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _nameField(TextEditingController controller, String hint) {
    return AppTextField(
      controller: controller,
      hint: hint,
      maxLength: _maxNameLength,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      inputFormatters: [LengthLimitingTextInputFormatter(_maxNameLength)],
    );
  }

  // -- Playing ----------------------------------------------------------------

  Widget _playingUi(JudgeStrings strings, JudgeState state, bool isArabic) {
    final question = state.game?.currentQuestion;
    return Column(
      children: [
        _topBar(strings),
        const SizedBox(height: 6),
        RoundTitleBar(
          heading: strings.roundName(state.round),
          count: question?.countLabel ?? '',
        ),
        const SizedBox(height: 14),
        _scoreRow(strings, state),
        const SizedBox(height: 10),
        _JudgeCallBanner(state: state, strings: strings),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RoundInfoCard(
                  text: question?.displayText(isArabic: isArabic) ?? '',
                ),
                const SizedBox(height: 14),
                _roundPanel(strings, state, isArabic),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreRow(JudgeStrings strings, JudgeState state) {
    final players = state.players;
    Widget seat(GamePlayer? p) {
      final isTurn =
          p != null &&
          (state.turn == p.id ||
              state.turn == 'ALLOW_ALL' && state.timerRunning);
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTurn ? AppColors.yellow : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              AppTextView(
                p?.playerName ?? '',
                fontWeight: AppFontWeight.enBold,
                fontSize: 16,
                maxLines: 1,
              ),
              const SizedBox(height: 4),
              AppTextView(
                '${p?.points ?? 0}',
                fontWeight: AppFontWeight.number,
                fontSize: 28,
              ),
              if (state.round == JudgeRound.wdyk)
                AppTextView(
                  '✕' * (p?.penalty ?? 0).clamp(0, 3),
                  color: AppColors.error,
                  fontSize: 14,
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          seat(players.isNotEmpty ? players[0] : null),
          SizedBox(
            width: 92,
            child: Center(child: _JudgeTimer(endsAt: state.timerEndsAt)),
          ),
          seat(players.length > 1 ? players[1] : null),
        ],
      ),
    );
  }

  Widget _roundPanel(JudgeStrings strings, JudgeState state, bool isArabic) {
    if (state.awaiting) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.white)),
      );
    }
    final round = state.round;
    if (round == JudgeRound.auction) {
      return _auctionPanel(strings, state, isArabic);
    }
    if (JudgeRound.isBellLike(round)) {
      return _bellPanel(strings, state, isArabic);
    }
    if (JudgeRound.isScoringRace(round)) {
      return _racePanel(strings, state);
    }
    return _wdykPanel(strings, state, isArabic);
  }

  JudgeController get _judge => ref.read(judgeControllerProvider.notifier);

  Widget _startTimerButton(JudgeStrings strings, JudgeState state) =>
      GameButton(
        label: strings.startTimer,
        onPressed: state.busy ? null : _judge.startTimer,
      );

  /// A listed answer for the seat in turn, plus "right, not listed" and
  /// "wrong".
  Widget _answerControls(
    JudgeStrings strings,
    JudgeState state,
    bool isArabic, {
    required String playerId,
  }) {
    // Alphabetical, not server order: the server reshuffles the list on every
    // update, and the judge is looking for the word a player just said.
    final answers = [...?state.game?.currentQuestion?.answers]
      ..sort(
        (a, b) => a
            .displayText(isArabic: isArabic)
            .compareTo(b.displayText(isArabic: isArabic)),
      );
    final enabled = !state.busy && playerId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (answers.isEmpty)
          AppTextView(
            strings.noAnswersLeft,
            color: AppColors.hint,
            fontSize: 13,
            textAlign: TextAlign.center,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in answers)
                if (a.id != null)
                  _chip(
                    a.displayText(isArabic: isArabic),
                    enabled ? () => _judge.answer(a.id!, playerId) : null,
                  ),
            ],
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GameButton(
                label: strings.rightNotListed,
                fontSize: 14,
                onPressed: enabled
                    ? () => _judge.answer(
                        JudgeController.notListedAnswerId,
                        playerId,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GameButton(
                label: strings.wrong,
                fontSize: 14,
                onPressed: enabled
                    ? () =>
                          _judge.answer(JudgeController.wrongAnswerId, playerId)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.answerChip,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.6)),
          ),
          child: AppTextView(
            text,
            fontSize: 15,
            fontWeight: AppFontWeight.medium,
          ),
        ),
      ),
    );
  }

  Widget _turnLabel(JudgeStrings strings, JudgeState state) {
    final name = state.turnPlayer?.playerName;
    if (name == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppTextView(
        strings.turnOf(name),
        fontSize: 15,
        color: AppColors.yellow,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _wdykPanel(JudgeStrings strings, JudgeState state, bool isArabic) {
    if (!state.timerRunning) {
      return _startTimerButton(strings, state);
    }
    final seat = state.turnPlayer;
    final canPass =
        seat != null && seat.passes > 0 && seat.penalty >= 2 && !state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _turnLabel(strings, state),
        _answerControls(strings, state, isArabic, playerId: state.turn),
        if (canPass) ...[
          const SizedBox(height: 10),
          GameButton(label: strings.pass, fontSize: 14, onPressed: _judge.pass),
        ],
      ],
    );
  }

  Widget _auctionPanel(JudgeStrings strings, JudgeState state, bool isArabic) {
    switch (state.auctionStep) {
      case JudgeAuctionStep.answering:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextView(
              '${strings.bidOf(state.nameOf(state.bidderId), state.bid ?? 0)} · '
              '${strings.scoreOf(state.auctionScore ?? 0, state.bid ?? 0)}',
              fontSize: 15,
              color: AppColors.yellow,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            _answerControls(
              strings,
              state,
              isArabic,
              playerId: state.bidderId ?? state.turn,
            ),
          ],
        );
      case JudgeAuctionStep.confirming:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextView(
              strings.didMakeIt(state.nameOf(state.bidderId)),
              fontSize: 17,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: strings.yes,
                    onPressed: state.busy
                        ? null
                        : () => _judge.confirmAuction(madeIt: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GameButton(
                    label: strings.no,
                    onPressed: state.busy
                        ? null
                        : () => _judge.confirmAuction(madeIt: false),
                  ),
                ),
              ],
            ),
          ],
        );
      case JudgeAuctionStep.bidding:
      case null:
        return _biddingControls(strings, state);
    }
  }

  Widget _biddingControls(JudgeStrings strings, JudgeState state) {
    final players = state.players;
    final maxUseful =
        state.game?.currentQuestion?.answers.length ?? JudgeController.maxBid;
    final top = maxUseful.clamp(1, JudgeController.maxBid);
    if (_bidValue > top) {
      _bidValue = top;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextView(strings.whoBids, fontSize: 15, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < players.length && i < 2; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _seatToggle(
                  players[i].playerName,
                  _bidSeat == i,
                  () => setState(() => _bidSeat = i),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stepButton(
              Icons.remove,
              _bidValue > 1 ? () => setState(() => _bidValue--) : null,
            ),
            SizedBox(
              width: 80,
              child: AppTextView(
                '$_bidValue',
                fontSize: 34,
                fontWeight: AppFontWeight.number,
                textAlign: TextAlign.center,
              ),
            ),
            _stepButton(
              Icons.add,
              _bidValue < top ? () => setState(() => _bidValue++) : null,
            ),
          ],
        ),
        const SizedBox(height: 14),
        GameButton(
          label: strings.confirmBid,
          onPressed: state.busy || players.length < 2
              ? null
              : () => _judge.bid(players[_bidSeat].id, _bidValue),
        ),
      ],
    );
  }

  Widget _seatToggle(String name, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.yellow : AppColors.divider,
          ),
        ),
        child: AppTextView(
          name,
          fontSize: 16,
          fontWeight: AppFontWeight.medium,
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return IconButton.filled(
      onPressed: onTap,
      iconSize: 28,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.button,
        minimumSize: const Size(52, 52),
      ),
      icon: Icon(icon, color: AppColors.white),
    );
  }

  Widget _bellPanel(JudgeStrings strings, JudgeState state, bool isArabic) {
    final players = state.players;
    if (state.turn.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextView(
            strings.whoRang,
            fontSize: 15,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < players.length && i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: GameButton(
                    label: strings.rang(players[i].playerName),
                    onPressed: state.busy
                        ? null
                        : () => _judge.ringBell(players[i].id),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _turnLabel(strings, state),
        _answerControls(strings, state, isArabic, playerId: state.turn),
      ],
    );
  }

  Widget _racePanel(JudgeStrings strings, JudgeState state) {
    if (!state.timerRunning) {
      return _startTimerButton(strings, state);
    }
    final players = state.players;
    return Row(
      children: [
        for (var i = 0; i < players.length && i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: GameButton(
              label: strings.pointTo(players[i].playerName),
              fontSize: 15,
              onPressed: state.busy
                  ? null
                  : () => _judge.pointTo(players[i].id),
            ),
          ),
        ],
      ],
    );
  }

  // -- Result -----------------------------------------------------------------

  Widget _resultUi(JudgeStrings strings, JudgeState state) {
    final result = state.result;
    final winnerName = result == null ? '' : state.nameOf(result.winnerId);
    return Column(
      children: [
        _topBar(strings),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                AppTextView(
                  winnerName.isEmpty
                      ? strings.gameEnded
                      : strings.winner(winnerName),
                  fontSize: 26,
                  fontWeight: AppFontWeight.enBold,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (result != null)
                  for (final row in result.gameResultPlayers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: row.playerId == result.winnerId
                                ? AppColors.yellow
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppTextView(
                              state.nameOf(row.playerId),
                              fontSize: 18,
                              fontWeight: AppFontWeight.enBold,
                            ),
                            const SizedBox(height: 6),
                            AppTextView(
                              '${strings.points}: ${row.points}   '
                              '${strings.correct}: ${row.correctAnswersCount}   '
                              '${strings.strikes}: ${row.strikes}',
                              fontSize: 14,
                              color: AppColors.hint,
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
                GameButton(
                  label: strings.done,
                  onPressed: () => _exit(dispatchLeaveGame: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The running answer clock, counted down locally from the server's time.
class _JudgeTimer extends StatefulWidget {
  const _JudgeTimer({required this.endsAt});

  final DateTime? endsAt;

  @override
  State<_JudgeTimer> createState() => _JudgeTimerState();
}

class _JudgeTimerState extends State<_JudgeTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && widget.endsAt != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = widget.endsAt;
    final seconds = endsAt == null
        ? 0
        : (endsAt.difference(DateTime.now()).inMilliseconds / 1000)
              .ceil()
              .clamp(0, 999);
    return AppTextView(
      endsAt == null ? '—' : '$seconds',
      fontSize: 34,
      fontWeight: AppFontWeight.number,
      color: endsAt != null && seconds <= 3 ? AppColors.error : AppColors.blue,
    );
  }
}

/// The judge's last call, shown for a moment so the judge sees it register.
class _JudgeCallBanner extends StatelessWidget {
  const _JudgeCallBanner({required this.state, required this.strings});

  final JudgeState state;
  final JudgeStrings strings;

  @override
  Widget build(BuildContext context) {
    final call = state.lastCall;
    return SizedBox(
      height: 30,
      child: call == null
          ? null
          : _FadingLabel(
              key: ValueKey(call.serial),
              text: switch (call.kind) {
                JudgeCallKind.correct => strings.correctFor(
                  state.nameOf(call.playerId),
                ),
                JudgeCallKind.wrong => strings.strikeFor(
                  state.nameOf(call.playerId),
                ),
                JudgeCallKind.timeout => strings.timeUpFor(
                  state.nameOf(call.playerId),
                ),
                JudgeCallKind.pass => strings.passFor(
                  state.nameOf(call.playerId),
                ),
              },
              color: call.kind == JudgeCallKind.correct
                  ? AppColors.green
                  : AppColors.error,
            ),
    );
  }
}

class _FadingLabel extends StatefulWidget {
  const _FadingLabel({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  State<_FadingLabel> createState() => _FadingLabelState();
}

class _FadingLabelState extends State<_FadingLabel> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      child: Center(
        child: AppTextView(
          widget.text,
          fontSize: 16,
          fontWeight: AppFontWeight.enBold,
          color: widget.color,
        ),
      ),
    );
  }
}

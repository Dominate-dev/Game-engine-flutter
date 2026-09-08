import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/play_game_hub_events.dart';
import '../../../domain/auction_phase.dart';
import '../../../domain/game_phase.dart';
import '../../../domain/game_session_state.dart';
import '../../game_controller/game_controller.dart';

// Timer / result label / score column shown between the two players —
// identical across every round screen. [TimerUpdatedSeconds] starts the
// countdown from hub `arg0`; not handled on [GameControllerScreen].
class RoundScoreColumn extends ConsumerStatefulWidget {
  const RoundScoreColumn({
    super.key,
    required this.resultLabel,
    required this.scoreText,
  });

  final String resultLabel;
  final String scoreText;

  @override
  ConsumerState<RoundScoreColumn> createState() => _RoundScoreColumnState();
}

class _RoundScoreColumnState extends ConsumerState<RoundScoreColumn> {
  final _timer = CountdownTimerController();

  @override
  Widget build(BuildContext context) {
    ref.listen(gameControllerProvider, (previous, next) {
      // Auction resets the countdown at every phase boundary: back to 00:00 and
      // stopped, waiting for the next TimerUpdatedSeconds. Other rounds keep
      // the freeze-in-place behaviour below.
      if (next.phase == GamePhase.auction &&
          _auctionBoundaryCrossed(previous, next)) {
        _timer.startTimer(0);
      }
      final wasTimerRunning = previous?.game?.isTimerStarted == true;
      final timerStopped = next.game?.isTimerStarted == false;
      if (wasTimerRunning && timerStopped) {
        // The terminal-event freeze — this flag flips false only for the
        // resolutions `_eventStopsTimer` identifies. The last server value
        // stays readable, then the display clears.
        _timer.freezeAndReset();
      }
      // Bell only (B-10): a restore can land mid-race with a running server
      // countdown and no fresh TimerUpdatedSeconds to follow — the restored
      // value itself is the start signal. Other rounds keep waiting for
      // TimerUpdatedSeconds, the A-5 rule their restore tests pin.
      if (next.lastEventName == PlayGameHubEvents.gameRestore &&
          next.phase == GamePhase.bell &&
          next.game?.isTimerStarted == true) {
        final restored = _secondsFrom(next.game?.currentTimerValue);
        if (restored > 0) {
          _timer.startTimer(restored);
        }
        return;
      }
      if (next.lastEventName != PlayGameHubEvents.timerUpdatedSeconds) {
        return;
      }
      final valueChanged =
          previous?.game?.currentTimerValue != next.game?.currentTimerValue;
      final becameTimerEvent =
          previous?.lastEventName != PlayGameHubEvents.timerUpdatedSeconds;
      if (!valueChanged && !becameTimerEvent) {
        return;
      }
      // TimerUpdatedSeconds is the server telling us what to show *now*, so
      // it is applied immediately and never schedules a delayed clear — a
      // non-positive value zeroes the display straight away rather than
      // freezing it. Going through startTimer also cancels any clear a
      // terminal freeze had pending, so a fresh server value can never be
      // zeroed out from under itself.
      final seconds = _secondsFrom(next.game?.currentTimerValue);
      _timer.startTimer(seconds);
    });

    // Controller-driven only: TimerUpdatedSeconds is the sole start signal, so
    // a stop freezes the display instead of snapping it back to a state value.
    return Column(
      children: [
        CountdownTimerText(
          seconds: 0,
          controller: _timer,
          autoStart: false,
          onFinished: () {
            ref.read(gameControllerProvider.notifier).onAnswerTimerExpired();
          },
          fontSize: 25,
          normalColor: AppColors.blue,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        AppTextView(
          widget.resultLabel,
          fontSize: 15,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        AppNumberTextView(
          widget.scoreText,
          fontSize: 20,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  bool _auctionBoundaryCrossed(
    GameSessionState? previous,
    GameSessionState next,
  ) {
    if (previous?.auctionPhase != next.auctionPhase) {
      return true;
    }
    return next.auctionResult != AuctionResult.none &&
        previous?.auctionResult != next.auctionResult;
  }

  int _secondsFrom(double? value) {
    if (value == null || value <= 0) {
      return 0;
    }
    return value.floor();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_fonts.dart';
import 'app_text_view.dart';

/// Imperative handle for a [CountdownTimerText] — lets any parent widget
/// call [startTimer] (with a new starting value) or [stopTimer] without
/// rebuilding the timer widget itself.
///
/// ```dart
/// final controller = CountdownTimerController();
/// CountdownTimerText(seconds: 10, controller: controller);
/// ...
/// controller.startTimer(30); // cancels the running timer, restarts at 30
/// controller.stopTimer(); // freezes the countdown in place
/// ```
class CountdownTimerController {
  _CountdownTimerTextState? _state;

  void _attach(_CountdownTimerTextState state) => _state = state;

  void _detach(_CountdownTimerTextState state) {
    if (_state == state) {
      _state = null;
    }
  }

  /// (Re)starts the countdown at [seconds]. Any timer already running for
  /// this widget is cancelled first, so calling this repeatedly always
  /// leaves exactly one timer ticking.
  void startTimer(int seconds) => _state?._startTimer(seconds);

  /// Stops the countdown, freezing it at whatever value it's currently
  /// showing, and leaves it there.
  ///
  /// This is the plain stop — no delayed clear. Use it wherever the server
  /// is still the authority over what the display should show next.
  void stopTimer() => _state?._stopTimer();

  /// Freezes the countdown, then clears it.
  ///
  /// For **terminal events only** — the round-ending resolutions that
  /// `_eventStopsTimer` already identifies (CorrectAnswer, a freezing
  /// penalty, PlayerPassed, a won/lost or goal-reached freeze). The freeze is
  /// immediate, so the value the server last reported stays readable; after
  /// [CountdownTimerText.freezeResetDelay] the countdown is disposed and the
  /// display returns to `00:00`.
  ///
  /// A [startTimer] arriving inside that window supersedes the pending
  /// reset — a fresh `TimerUpdatedSeconds` must never be zeroed by a clear
  /// that was scheduled before it.
  void freezeAndReset() => _state?._freezeAndReset();
}

/// Reusable countdown number — starts at [seconds] and ticks down by one
/// every second (`00:10`, `00:09`, `00:08` … `00:00`). Once the remaining
/// count drops to half of the starting value the color starts gradually
/// shifting from [normalColor] toward [dangerColor], reaching full
/// [dangerColor] at [criticalAt] (default `3`) seconds left — at which
/// point the number also throbs (a pulsing scale) to draw attention to it.
///
/// Drop this in anywhere a round/lobby needs a live timer — pass a new
/// [seconds] (e.g. wrap in a `ValueKey`) to restart it declaratively, or
/// pass a [controller] to restart/stop it imperatively via [startTimer]
/// and [stopTimer].
class CountdownTimerText extends StatefulWidget {
  const CountdownTimerText({
    super.key,
    required this.seconds,
    this.controller,
    this.fontSize,
    this.fontWeight = AppFontWeight.enBold,
    this.textAlign,
    this.normalColor = AppColors.yellow,
    this.dangerColor = AppColors.error,
    this.criticalAt = 3,
    this.autoStart = true,
    this.onFinished,
  });

  final int seconds;
  final CountdownTimerController? controller;
  final double? fontSize;
  final AppFontWeight fontWeight;
  final TextAlign? textAlign;
  final Color normalColor;
  final Color dangerColor;
  final int criticalAt;
  final bool autoStart;
  final VoidCallback? onFinished;

  /// How long a frozen value stays on screen before the countdown is
  /// disposed and the display resets to `00:00`.
  ///
  /// The freeze itself is still immediate — this delay runs only after it,
  /// so the last value the server reported is readable before it clears.
  static const freezeResetDelay = Duration(milliseconds: 500);

  @override
  State<CountdownTimerText> createState() => _CountdownTimerTextState();
}

class _CountdownTimerTextState extends State<CountdownTimerText>
    with SingleTickerProviderStateMixin {
  static const _throbDuration = Duration(milliseconds: 400);
  static const _throbScale = 1.2;

  Timer? _timer;

  /// The post-freeze reset. Held so a new [_startTimer] can cancel it —
  /// otherwise a server countdown started inside the freeze window would be
  /// zeroed out from under itself when this fired.
  Timer? _resetTimer;

  late int _total;
  late int _remaining;
  late final AnimationController _throbController;
  late final Animation<double> _throbAnimation;
  bool _isThrobbing = false;

  @override
  void initState() {
    super.initState();
    _total = widget.seconds;
    _remaining = widget.seconds;
    _throbController = AnimationController(
      vsync: this,
      duration: _throbDuration,
    );
    _throbAnimation = Tween<double>(begin: 1, end: _throbScale).animate(
      CurvedAnimation(parent: _throbController, curve: Curves.easeInOut),
    );
    widget.controller?._attach(this);
    if (widget.autoStart) {
      _runTimer();
    }
    _syncThrob();
  }

  @override
  void didUpdateWidget(covariant CountdownTimerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (widget.seconds != oldWidget.seconds) {
      // Same reason as _startTimer: a declarative restart also supersedes a
      // pending post-freeze reset.
      _cancelPendingReset();
      _total = widget.seconds;
      _remaining = widget.seconds;
      _timer?.cancel();
      if (widget.autoStart) {
        _runTimer();
      }
      _syncThrob();
    }
  }

  /// Cancels any timer already running for this widget, then starts a
  /// fresh countdown at [seconds].
  void _startTimer(int seconds) {
    // A fresh start supersedes a pending post-freeze reset — the server just
    // told us to count again, so the reset must not land afterwards.
    _cancelPendingReset();
    _timer?.cancel();
    setState(() {
      _total = seconds;
      _remaining = seconds;
    });
    _runTimer();
    _syncThrob();
  }

  /// The plain stop: freeze in place, schedule nothing.
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    // A stop supersedes a clear that a previous terminal freeze scheduled —
    // otherwise that clear would land on top of this new frozen value.
    _cancelPendingReset();
    _syncThrob();
  }

  /// Terminal freeze: the same immediate stop, then the delayed clear.
  void _freezeAndReset() {
    _stopTimer();
    // Armed only after the freeze, and re-armed from scratch so two terminal
    // events in a row cannot leave two clears pending.
    _cancelPendingReset();
    _resetTimer = Timer(CountdownTimerText.freezeResetDelay, _resetAfterFreeze);
  }

  /// Disposes the countdown and returns the display to zero.
  ///
  /// `_timer` is cancelled again here rather than trusted: nothing may tick
  /// the value after this point, and cancelling an already-null timer is
  /// free. `_total` is deliberately left alone so the cleared display reads
  /// exactly like a countdown that expired on its own.
  void _resetAfterFreeze() {
    _resetTimer = null;
    if (!mounted) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    setState(() => _remaining = 0);
    _syncThrob();
  }

  void _cancelPendingReset() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  void _runTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      _syncThrob();
      if (_remaining <= 0) {
        timer.cancel();
        widget.onFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelPendingReset();
    widget.controller?._detach(this);
    _throbController.dispose();
    super.dispose();
  }

  /// [widget.criticalAt] clamped below halfway so the color lerp below
  /// never divides by zero for a very short countdown.
  int get _criticalThreshold {
    final halfway = (_total / 2).ceil();
    return widget.criticalAt < halfway ? widget.criticalAt : 0;
  }

  bool get _isCritical => _remaining > 0 && _remaining <= _criticalThreshold;

  void _syncThrob() {
    if (_isCritical == _isThrobbing) {
      return;
    }
    _isThrobbing = _isCritical;
    if (_isThrobbing) {
      _throbController.repeat(reverse: true);
    } else {
      _throbController.stop();
      _throbController.reset();
    }
  }

  Color get _color {
    // Zero is not "running out" — it is over. The danger colour is there to
    // warn while there is still time to act on; once the countdown has
    // finished (expired, or cleared after a terminal freeze) it goes back to
    // the normal colour rather than sitting on screen as a red alarm.
    // [_syncThrob] already excludes zero for the same reason, so the two
    // agree: no throb, no danger colour.
    if (_remaining <= 0) {
      return widget.normalColor;
    }
    final halfway = (_total / 2).ceil();
    if (_remaining >= halfway) {
      return widget.normalColor;
    }
    final critical = _criticalThreshold;
    if (_remaining <= critical) {
      return widget.dangerColor;
    }
    final t = (halfway - _remaining) / (halfway - critical);
    return Color.lerp(widget.normalColor, widget.dangerColor, t)!;
  }

  /// `mm:ss`, zero-padded (e.g. `00:10`, `00:09` … `00:00`).
  String get _formatted {
    final minutes = _remaining ~/ 60;
    final secs = _remaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _throbAnimation,
      child: AppNumberTextView(
        _formatted,
        fontWeight: widget.fontWeight,
        fontSize: widget.fontSize,
        color: _color,
        textAlign: widget.textAlign,
      ),
    );
  }
}

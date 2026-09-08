import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_controller/round_sub_panel.dart';

/// Transparent round overlay — Lottie + auto-dismiss, like Android
/// `ShowStartGameDialog` (`lottie_loop="false"`, not cancelable).
class RoundLottieDialog extends ConsumerStatefulWidget {
  const RoundLottieDialog({
    super.key,
    required this.lottie,
    this.text,
    this.sound,
    this.marginTop = 0,
    this.timer = 3000,
  });

  final Widget lottie;
  final String? text;
  final String? sound;
  final double marginTop;
  final int timer;

  @override
  ConsumerState<RoundLottieDialog> createState() => _RoundLottieDialogState();
}

class _RoundLottieDialogState extends ConsumerState<RoundLottieDialog> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    final sound = widget.sound;
    if (sound != null) {
      unawaited(ref.read(audioServiceProvider).start(sound));
    }
    _dismissTimer = Timer(Duration(milliseconds: widget.timer), _dismiss);
  }

  /// Closes this overlay — and only this overlay.
  ///
  /// Hosted in a [RoundSubPanelLayer] (every handler-raised overlay is), the
  /// scope's callback removes it by token, so nothing on the Navigator is
  /// touched and a regular dialog sitting above it cannot be closed by this
  /// timer. `Navigator.of(context).pop()` used to be safe only because the
  /// queue guaranteed this dialog was topmost; it pops the topmost route,
  /// not this widget's own.
  ///
  /// The fallback covers a [RoundLottieDialog] mounted on a route of its own
  /// (a direct `showDialog`, as some tests do): it pops that route, and only
  /// while it is still the current one.
  void _dismiss() {
    if (!mounted) {
      return;
    }
    final dismissPanel = RoundSubPanelScope.maybeOf(context);
    if (dismissPanel != null) {
      dismissPanel();
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.text?.trim() ?? '';

    return PopScope(
      canPop: false,
      child: GameDialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              widget.lottie,
              if (message.isNotEmpty)
                Transform.translate(
                  offset: Offset(0, widget.marginTop),
                  child: AppTextView(
                    message,
                    fontWeight: AppFontWeight.medium,
                    fontSize: 18,
                    color: AppColors.onBackground,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

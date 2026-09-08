import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_controller/round_sub_panel.dart';

/// Native PlayerAnswered banner — full-width purple bar with answer text,
/// slides up from the bottom and auto-dismisses.
class PlayerAnsweredDialog extends ConsumerStatefulWidget {
  const PlayerAnsweredDialog({
    super.key,
    required this.answer,
    this.playerName = '',
    this.timer = 2000,
  });

  final String answer;

  // Shown in yellow under the answer. Empty means no attribution line at all,
  // which is the case when the answer is this device's own.
  final String playerName;

  final int timer;

  @override
  ConsumerState<PlayerAnsweredDialog> createState() =>
      _PlayerAnsweredDialogState();
}

class _PlayerAnsweredDialogState extends ConsumerState<PlayerAnsweredDialog>
    with SingleTickerProviderStateMixin {
  static const _barHeight = 70.0;
  static const _slideDuration = Duration(milliseconds: 300);

  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _slideDuration);
    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _dismissTimer = Timer(Duration(milliseconds: widget.timer), _dismiss);
  }

  /// Closes this banner — and only this banner.
  ///
  /// The slide-out animation is unchanged; only what happens after it is.
  /// Hosted in a [RoundSubPanelLayer] (every handler-raised banner is), the
  /// scope's callback removes it by token, so nothing on the Navigator is
  /// touched and a regular dialog above it cannot be closed by this timer.
  /// `Navigator.of(context).pop()` pops the topmost route, not this widget's
  /// own, and was safe only while the queue guaranteed this was topmost.
  ///
  /// The fallback covers a banner mounted on a route of its own (a direct
  /// `showDialog`): it pops that route, and only while it is still current.
  Future<void> _dismiss() async {
    if (!mounted) {
      return;
    }
    await _controller.reverse();
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerName = widget.playerName.trim();
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: SlideTransition(
            position: _slide,
            child: Center(
              child: Material(
                color: AppColors.purple,
                child: ConstrainedBox(
                  // minHeight, not a fixed height: with no player name the bar
                  // is exactly _barHeight as before, and the attribution line
                  // grows it instead of being clipped inside it. No Center
                  // here — it would expand to the incoming max, which the
                  // previous fixed height happened to cap.
                  constraints: const BoxConstraints(minHeight: _barHeight),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppTextView(
                            widget.answer,
                            fontWeight: AppFontWeight.bold,
                            fontSize: 14,
                            color: AppColors.onBackground,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (playerName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            AppTextView(
                              playerName,
                              fontWeight: AppFontWeight.enBold,
                              fontSize: 14,
                              color: AppColors.yellow,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

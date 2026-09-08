import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_provider.dart';
import '../../constants/app_fonts.dart';
import 'app_text_view.dart';

// Shared game button — [btn_bg] background + [AppTextView] label
// so EN/AR fonts follow the current app language.
class GameButton extends ConsumerStatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.width,
    this.height = GameButton.minHeight,
    this.isExpanded = true,
    this.fontWeight = AppFontWeight.number,
    this.fontSize = GameButton.labelFontSize,
    this.color = Colors.white,
  });

  static const backgroundAsset = 'assets/images/btn_bg.png';
  static const packageName = 'coreapp';
  static const minHeight = 52.0;
  static const labelFontSize = 16.0;
  static const labelBottomInset = 6.0;
  static const horizontalPadding = 24.0;
  static const disabledOpacity = 0.55;
  static const pressScale = 0.9;
  static const pressAnimDuration = Duration(milliseconds: 100);

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? width;
  final double height;
  final bool isExpanded;
  final AppFontWeight fontWeight;
  final double fontSize;
  final Color color;

  @override
  ConsumerState<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends ConsumerState<GameButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scale;
  bool _held = false;

  bool get _isEnabled => widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: GameButton.pressAnimDuration,
      reverseDuration: GameButton.pressAnimDuration,
    );
    _scale = Tween<double>(begin: 1, end: GameButton.pressScale).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: widget.isExpanded ? double.infinity : widget.width,
        height: widget.height,
        child: Opacity(
          opacity: _isEnabled ? 1 : GameButton.disabledOpacity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                GameButton.backgroundAsset,
                package: GameButton.packageName,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
              Center(
                child: _ButtonContent(
                  label: widget.label,
                  icon: widget.icon,
                  fontWeight: widget.fontWeight,
                  fontSize: widget.fontSize,
                  color: widget.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _isEnabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _isEnabled ? (_) => _onTapDown() : null,
        onTapUp: _isEnabled ? (_) => _onTapUp() : null,
        onTapCancel: _isEnabled ? _onTapCancel : null,
        onTap: _isEnabled ? _onTap : null,
        child: button,
      ),
    );
  }

  void _onTap() {
    unawaited(ref.read(audioServiceProvider).playAnswerClick());
    widget.onPressed?.call();
  }

  void _onTapDown() {
    _held = true;
    _pressController.forward();
  }

  Future<void> _onTapUp() async {
    _held = false;
    if (_pressController.status != AnimationStatus.completed) {
      await _pressController.forward();
    }
    if (!mounted || _held) {
      return;
    }
    await _pressController.reverse();
  }

  void _onTapCancel() {
    _held = false;
    _pressController.reverse();
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.fontWeight,
    required this.fontSize,
    required this.color,
    this.icon,
  });

  final String label;
  final AppFontWeight fontWeight;
  final double fontSize;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelWidget = AppTextView(
      label,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: color,
      textAlign: TextAlign.center,
      padding: const EdgeInsets.only(bottom: GameButton.labelBottomInset),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GameButton.horizontalPadding,
      ),
      child: icon == null
          ? labelWidget
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                labelWidget,
              ],
            ),
    );
  }
}

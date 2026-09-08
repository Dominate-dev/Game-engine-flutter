import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_fonts.dart';
import '../providers/app_language_provider.dart';
import 'app_text_view.dart';
import 'game_button.dart';

// Full-screen reconnect card — purple card, [SpinKitThreeBounce],
// optional retry button (shown after [retryAfter] when [onRetry] is set).
class ConnectionLoader extends ConsumerStatefulWidget {
  const ConnectionLoader({
    super.key,
    this.showRetry = false,
    this.onRetry,
    this.retryAfter = const Duration(seconds: 5),
  });

  static const cardRadius = 8.0;
  static const outerMargin = 15.0;
  static const innerPadding = 15.0;

  final bool showRetry;
  final VoidCallback? onRetry;
  final Duration retryAfter;

  @override
  ConsumerState<ConnectionLoader> createState() => _ConnectionLoaderState();
}

class _ConnectionLoaderState extends ConsumerState<ConnectionLoader> {
  bool _showRetry = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _showRetry = widget.showRetry;
    _scheduleRetryButton();
  }

  @override
  void didUpdateWidget(covariant ConnectionLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showRetry && !_showRetry) {
      setState(() => _showRetry = true);
    }
    if (oldWidget.onRetry == null && widget.onRetry != null) {
      _scheduleRetryButton();
    }
  }

  void _scheduleRetryButton() {
    if (_showRetry || widget.onRetry == null) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(widget.retryAfter, () {
      if (mounted) {
        setState(() => _showRetry = true);
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final showRetry = _showRetry && widget.onRetry != null;

    return Stack(
      children: [
        const ModalBarrier(
          dismissible: false,
          color: AppColors.scrim,
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(ConnectionLoader.outerMargin),
            child: Card(
              color: AppColors.connectionCard,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ConnectionLoader.cardRadius,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(ConnectionLoader.innerPadding),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 50,
                        height: 30,
                        child: SpinKitThreeBounce(
                          color: AppColors.onBackground,
                          size: 30,
                        ),
                      ),
                      AppTextView(
                        strings.reconnectNetworkGame,
                        fontWeight: AppFontWeight.number,
                        fontSize: 16,
                        color: AppColors.onBackground,
                        textAlign: TextAlign.center,
                        padding: const EdgeInsets.only(top: 8),
                      ),
                      if (showRetry) ...[
                        const SizedBox(height: 12),
                        GameButton(
                          label: strings.reconnect,
                          onPressed: widget.onRetry,
                          isExpanded: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

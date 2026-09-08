import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';

// Opens the native Android / iOS share sheet. Use this from any plugin
// instead of calling [SharePlus] directly.
abstract final class AppShare {
  static Future<void> shareText(
    String text, {
    String? title,
    String? subject,
    BuildContext? context,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: trimmed,
          title: title,
          subject: subject,
          sharePositionOrigin: _origin(context),
        ),
      );
    } catch (error) {
      AppLogger.log('AppShare.shareText failed — $error');
    }
  }

  // iOS (especially iPad) needs a non-zero popover origin.
  static Rect _origin(BuildContext? context) {
    if (context != null && context.mounted) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
}

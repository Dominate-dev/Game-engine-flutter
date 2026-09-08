import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_logger.dart';

abstract final class AppEmail {
  static Future<void> openEmail(
    String? emailAddress, {
    String? subject,
  }) async {
    final address = emailAddress?.trim() ?? '';
    if (address.isEmpty) {
      return;
    }

    final resolvedSubject =
        (subject == null || subject.trim().isEmpty) ? deviceSubject : subject;
    final uri = Uri.parse(
      'mailto:$address?subject=${Uri.encodeComponent(resolvedSubject)}',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        AppLogger.log('AppEmail.openEmail could not launch $uri');
      }
    } catch (error) {
      AppLogger.log('AppEmail.openEmail failed — $error');
    }
  }

  // Report subject: `Android` or `Ios` from the current device.
  static String get deviceSubject {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'Ios';
      case TargetPlatform.android:
        return 'Android';
      default:
        return defaultTargetPlatform.name;
    }
  }
}

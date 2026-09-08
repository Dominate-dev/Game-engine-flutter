import 'package:flutter/foundation.dart';

import '../security/security_generator.dart';
import '../storage/shared_prefs_service.dart';

/// Builds global headers applied to every API request (native NetworkModule +
/// AppBaseInterceptor parity).
class ApiHeadersBuilder {
  ApiHeadersBuilder(this._prefs);

  final SharedPrefsService _prefs;

  /// The stored auth token, or `''` when there is none.
  ///
  /// The same value [buildGlobalHeaders] already reads below — exposed so a
  /// caller that only needs the token (the hub upgrade) can read it from the
  /// builder it was already given, instead of being handed a second
  /// SharedPrefs reference.
  String get authToken => _prefs.getToken() ?? '';

  Future<Map<String, String>> buildGlobalHeaders({String? authToken}) async {
    final deviceId = await _prefs.getOrCreateDeviceId();
    final userId = _prefs.getUserId();
    final requestToken = getRequestToken(userId: userId);

    final token = authToken ?? _prefs.getToken() ?? '';

    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept-Language': _prefs.getLanguage(),
      'Request-Token': requestToken,
      'device-id': deviceId,
      'device-name': _deviceName,
      'X-Timezone': _formatTimezoneOffset(DateTime.now().timeZoneOffset),
    };
  }

  /// Native: `SecurityGenerator.encryptDataRSA(userId.toString())` where
  /// userId is 0 before login.
  String getRequestToken({int? userId}) {
    final id = userId ?? _prefs.getUserId();
    return SecurityGenerator.encryptDataRSA(id.toString());
  }

  String get _deviceName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }

  String _formatTimezoneOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }
}

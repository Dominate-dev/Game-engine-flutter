import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';
import 'shared_prefs_service_impl.dart';

/// Injected prefs API. Features use this type — never [SharedPreferences].
///
/// ```dart
/// final prefs = ref.read(sharedPrefsProvider);
///
/// await prefs.setToken(value: 'textAAA');
/// final token = prefs.getToken();
///
/// await prefs.setJson('profile', response.toJson());
/// final profile = prefs.getJson('profile');
/// ```
abstract class SharedPrefsService {
  static Future<SharedPrefsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsServiceImpl(prefs);
  }

  String? getString(String key);
  Future<bool> setString(String key, String value);
  bool? getBool(String key);
  Future<bool> setBool(String key, bool value);
  int? getInt(String key);
  Future<bool> setInt(String key, int value);
  Map<String, dynamic>? getJson(String key);
  Future<bool> setJson(String key, Map<String, dynamic> value);
  Future<bool> remove(String key);
  Future<bool> clear();

  String? getToken({String key = PrefsKeys.token});
  Future<bool> setToken({
    String key = PrefsKeys.token,
    required String value,
  });
  Future<bool> clearToken({String key = PrefsKeys.token});

  String? getRefreshToken({String key = PrefsKeys.refreshToken});
  Future<bool> setRefreshToken({
    String key = PrefsKeys.refreshToken,
    required String value,
  });

  int getUserId({String key = PrefsKeys.userId});
  Future<bool> setUserId({
    String key = PrefsKeys.userId,
    required String value,
  });

  String getSocialMediaId({String key = PrefsKeys.socialMediaId});
  Future<bool> setSocialMediaId({
    String key = PrefsKeys.socialMediaId,
    required String value,
  });

  String getLanguage({String key = PrefsKeys.language});
  Future<bool> setLanguage({
    String key = PrefsKeys.language,
    required String value,
  });

  String? getDeviceId({String key = PrefsKeys.deviceId});
  Future<bool> setDeviceId({
    String key = PrefsKeys.deviceId,
    required String value,
  });
  Future<String> getOrCreateDeviceId({String key = PrefsKeys.deviceId});

  Future<void> clearAuth();
}

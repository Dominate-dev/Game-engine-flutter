import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_language.dart';
import 'prefs_keys.dart';
import 'shared_prefs_service.dart';

class SharedPrefsServiceImpl implements SharedPrefsService {
  SharedPrefsServiceImpl(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Map<String, dynamic>? getJson(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  @override
  Future<bool> setJson(String key, Map<String, dynamic> value) =>
      setString(key, jsonEncode(value));

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> clear() => _prefs.clear();

  @override
  String? getToken({String key = PrefsKeys.token}) => getString(key);

  @override
  Future<bool> setToken({
    String key = PrefsKeys.token,
    required String value,
  }) =>
      setString(key, value);

  @override
  Future<bool> clearToken({String key = PrefsKeys.token}) => remove(key);

  @override
  String? getRefreshToken({String key = PrefsKeys.refreshToken}) =>
      getString(key);

  @override
  Future<bool> setRefreshToken({
    String key = PrefsKeys.refreshToken,
    required String value,
  }) =>
      setString(key, value);

  @override
  int getUserId({String key = PrefsKeys.userId}) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    return int.tryParse(raw) ?? 0;
  }

  @override
  Future<bool> setUserId({
    String key = PrefsKeys.userId,
    required String value,
  }) =>
      setString(key, value);

  @override
  String getSocialMediaId({String key = PrefsKeys.socialMediaId}) =>
      getString(key) ?? '';

  @override
  Future<bool> setSocialMediaId({
    String key = PrefsKeys.socialMediaId,
    required String value,
  }) =>
      setString(key, value);

  @override
  String getLanguage({String key = PrefsKeys.language}) =>
      getString(key) ?? AppLanguage.english;

  @override
  Future<bool> setLanguage({
    String key = PrefsKeys.language,
    required String value,
  }) =>
      setString(key, value);

  @override
  String? getDeviceId({String key = PrefsKeys.deviceId}) => getString(key);

  @override
  Future<bool> setDeviceId({
    String key = PrefsKeys.deviceId,
    required String value,
  }) =>
      setString(key, value);

  @override
  Future<String> getOrCreateDeviceId({String key = PrefsKeys.deviceId}) async {
    final existing = getDeviceId(key: key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final deviceId = _generateDeviceId();
    await setDeviceId(key: key, value: deviceId);
    return deviceId;
  }

  @override
  Future<void> clearAuth() async {
    await clearToken();
    await remove(PrefsKeys.refreshToken);
    await remove(PrefsKeys.userId);
    await remove(PrefsKeys.socialMediaId);
  }

  String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'flutter-$timestamp-$random';
  }
}

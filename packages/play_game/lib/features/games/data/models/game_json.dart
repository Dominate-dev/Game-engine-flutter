import 'package:coreapp/coreapp.dart';

abstract final class GameJson {
  static String string(Map<String, dynamic> json, String key) =>
      JsonValue.field(json, key)?.toString() ?? '';

  static String? stringOrNull(Map<String, dynamic> json, String key) {
    final value = JsonValue.field(json, key);
    if (value == null) {
      return null;
    }
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int integer(Map<String, dynamic> json, String key) =>
      JsonValue.parseInt(JsonValue.field(json, key)) ?? 0;

  static int? integerOrNull(Map<String, dynamic> json, String key) =>
      JsonValue.parseInt(JsonValue.field(json, key));

  static double decimal(Map<String, dynamic> json, String key) =>
      JsonValue.parseDouble(JsonValue.field(json, key)) ?? 0;

  static bool boolean(Map<String, dynamic> json, String key) =>
      JsonValue.parseBool(JsonValue.field(json, key)) ?? false;

  static bool? booleanOrNull(Map<String, dynamic> json, String key) =>
      JsonValue.parseBool(JsonValue.field(json, key));

  static Map<String, dynamic>? mapOrNull(
    Map<String, dynamic> json,
    String key,
  ) {
    final raw = JsonValue.field(json, key);
    if (raw is! Map) {
      return null;
    }
    return JsonValue.asMap(raw);
  }

  static List<T>? listOrNull<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic> json) mapper,
  ) {
    final raw = JsonValue.field(json, key);
    if (raw is! List) {
      return null;
    }
    return raw.map((item) => mapper(JsonValue.asMap(item))).toList();
  }

  static List<T> list<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic> json) mapper,
  ) {
    return listOrNull(json, key, mapper) ?? <T>[];
  }
}

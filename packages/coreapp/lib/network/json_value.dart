abstract final class JsonValue {
  static int? parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return int.tryParse(value.toString());
  }

  static double? parseDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return double.tryParse(value.toString());
  }

  static bool? parseBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value.toString().trim().toLowerCase();
    return switch (text) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
  }

  // Reads [camel] or PascalCase [camel] from REST / SignalR payloads.
  static Object? field(Map<String, dynamic> json, String camel) {
    if (json.containsKey(camel)) {
      return json[camel];
    }
    if (camel.isEmpty) {
      return null;
    }
    final pascal = '${camel[0].toUpperCase()}${camel.substring(1)}';
    if (json.containsKey(pascal)) {
      return json[pascal];
    }
    final lower = camel.toLowerCase();
    for (final entry in json.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  static bool hasField(Map<String, dynamic> json, String camel) {
    if (json.containsKey(camel)) {
      return true;
    }
    if (camel.isEmpty) {
      return false;
    }
    final pascal = '${camel[0].toUpperCase()}${camel.substring(1)}';
    if (json.containsKey(pascal)) {
      return true;
    }
    final lower = camel.toLowerCase();
    return json.keys.any((key) => key.toLowerCase() == lower);
  }

  static Map<String, dynamic> asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }
}

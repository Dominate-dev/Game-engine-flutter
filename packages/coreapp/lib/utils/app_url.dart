// Shared http(s) URL checks — use instead of repeating `startsWith('http')`.
abstract final class AppUrl {
  static bool isHttp(String? value) => httpOrNull(value) != null;

  static String? httpOrNull(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty) {
      return null;
    }
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url;
    }
    return null;
  }
}

import 'dart:developer' as developer;

/// Single logger for API, SignalR, and app diagnostics.
abstract final class AppLogger {
  static const signalR = 'SignalR';
  static const api = 'ApiNetwork';
  static const audio = 'Audio';

  /// Every call site's message is prefixed with a `[HH:mm:ss.mmm]` timestamp
  /// here, centrally — so no individual `AppLogger.log(...)` call needs to
  /// add its own.
  static void log(String message, {String name = 'App'}) {
    developer.log('${formatTimestamp(DateTime.now())} $message', name: name);
  }

  /// `[HH:mm:ss.mmm]`, local time, millisecond precision — enough to compare
  /// two log lines (e.g. a dialog and a countdown tick) in the right order.
  static String formatTimestamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '[${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${three(time.millisecond)}]';
  }
}

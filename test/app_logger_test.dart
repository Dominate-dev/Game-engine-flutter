import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// AppLogger.log() itself writes through dart:developer, which is silent
// under `flutter test` (no VM service listener attached) — there is nothing
// to capture. What is testable, and what actually changed, is the timestamp
// every call is now centrally prefixed with.

void main() {
  group('AppLogger.formatTimestamp', () {
    test('zero-pads hours, minutes, seconds and milliseconds', () {
      final time = DateTime(2026, 1, 1, 7, 2, 14, 120);
      expect(AppLogger.formatTimestamp(time), '[07:02:14.120]');
    });

    test('matches the requested example exactly', () {
      final time = DateTime(2026, 1, 1, 17, 2, 14, 120);
      expect(AppLogger.formatTimestamp(time), '[17:02:14.120]');
    });

    test('midnight and single-digit milliseconds still pad to 3 digits', () {
      final time = DateTime(2026, 1, 1, 0, 0, 0, 5);
      expect(AppLogger.formatTimestamp(time), '[00:00:00.005]');
    });

    test('does not roll into the next unit at the top of the range', () {
      final time = DateTime(2026, 1, 1, 23, 59, 59, 999);
      expect(AppLogger.formatTimestamp(time), '[23:59:59.999]');
    });
  });
}

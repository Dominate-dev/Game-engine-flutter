import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// Guards the --dart-define environment wiring (F1).
//
// These assert invariants the client relies on, not any backend contract.
// Run the override variant with:
//
//   flutter test test/api_endpoints_test.dart \
//     --dart-define=API_BASE_URL=https://example.invalid \
//     --dart-define=SIGNALR_HUB_URL=https://example.invalid/GameHub

void main() {
  group('ApiEndpoints', () {
    test('baseUrl is a usable https origin', () {
      expect(ApiEndpoints.baseUrl, isNotEmpty);
      expect(ApiEndpoints.baseUrl, startsWith('https://'));
    });

    test('baseUrl has no trailing slash', () {
      // The domain media-URL helpers concatenate a leading-slash path directly
      // onto baseUrl, so a trailing slash would produce a double slash.
      expect(ApiEndpoints.baseUrl, isNot(endsWith('/')));
    });

    test('signalRHubUrl is a usable https url', () {
      expect(ApiEndpoints.signalRHubUrl, isNotEmpty);
      expect(ApiEndpoints.signalRHubUrl, startsWith('https://'));
    });

    test('login is a path relative to baseUrl, not an absolute url', () {
      expect(ApiEndpoints.login, startsWith('/'));
      expect(ApiEndpoints.login, isNot(startsWith('http')));
    });

    test('the two endpoints are independently configurable', () {
      // Separate defines, so they are not required to share a host.
      expect(ApiEndpoints.baseUrl, isNotEmpty);
      expect(ApiEndpoints.signalRHubUrl, isNotEmpty);
    });

    // Catches the deployment footgun of overriding one define but not the
    // other, which would point REST and the hub at different environments.
    test('environment is configured consistently — both defines, or neither',
        () {
      final baseIsDefault = ApiEndpoints.baseUrl == ApiEndpoints.baseUrlDebug;
      final hubIsDefault =
          ApiEndpoints.signalRHubUrl == ApiEndpoints.baseUrlHubDebug;

      expect(
        baseIsDefault,
        hubIsDefault,
        reason: 'Half-configured build. Set BOTH API_BASE_URL and '
            'SIGNALR_HUB_URL, or neither.',
      );
    });
  });
}

// Generic, game-agnostic endpoints — REST base URL, SignalR hub URL, auth.
// Game-specific endpoints (e.g. All-In-One's `/api/AllInOne/*`) belong in
// that game plugin's own constants, not here.
class ApiEndpoints {
  ApiEndpoints._();

  static const baseUrlDebug = 'https://api-v2.tahadialthalatheen.com';
  static const baseUrlHubDebug =
      'https://api-v2.tahadialthalatheen.com/GameHub';

  // Resolved at compile time from --dart-define; falls back to the test
  // backend. Kept `const` so the pure media-URL helpers in the domain layer
  // can still read them. Set both defines or neither.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: baseUrlDebug,
  );

  static const signalRHubUrl = String.fromEnvironment(
    'SIGNALR_HUB_URL',
    defaultValue: baseUrlHubDebug,
  );

  static const login = '/api/Users/Login';
  static const refreshToken = '/api/Users/RefreshToken';
}

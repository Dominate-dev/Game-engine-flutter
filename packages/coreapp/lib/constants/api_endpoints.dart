// Generic, game-agnostic endpoints — REST base URL, SignalR hub URL, auth.
// Game-specific endpoints (e.g. All-In-One's `/api/AllInOne/*`) belong in
// that game plugin's own constants, not here.
class ApiEndpoints {
  ApiEndpoints._();

  static const baseUrlDebug = 'https://api-v2.tahadialthalatheen.com';
  static const baseUrlHubDebug =
      'https://api-v2.tahadialthalatheen.com/GameHub';

  // Built in from --dart-define; falls back to production. Set both defines
  // or neither.
  static const compiledBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: baseUrlDebug,
  );

  static const compiledHubUrl = String.fromEnvironment(
    'SIGNALR_HUB_URL',
    defaultValue: baseUrlHubDebug,
  );

  // The server the native host is signed in to, when it says so. Its token is
  // only valid there, so a host address always wins over the built-in one.
  static String? _hostBaseUrl;

  static String get baseUrl => _hostBaseUrl ?? compiledBaseUrl;

  static String get signalRHubUrl =>
      _hostBaseUrl == null ? compiledHubUrl : '$_hostBaseUrl/GameHub';

  /// Points REST and the hub at [address] (an https origin such as
  /// `https://api-test.example.com`). Null, empty or non-https restores the
  /// built-in server. Returns whether the effective address changed.
  static bool useServer(String? address) {
    final previous = baseUrl;
    final trimmed = (address ?? '').trim();
    final uri = Uri.tryParse(trimmed);
    final valid = trimmed.isNotEmpty && uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
    _hostBaseUrl = valid ? trimmed.replaceAll(RegExp(r'/+$'), '') : null;
    return baseUrl != previous;
  }

  static const login = '/api/Users/Login';
  static const refreshToken = '/api/Users/RefreshToken';
}

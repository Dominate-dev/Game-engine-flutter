import 'package:http/http.dart';
import 'package:http/io_client.dart';

import '../network/api_exception.dart';
import '../network/api_headers_builder.dart';
import '../network/network_info.dart';
import '../utils/app_logger.dart';

/// HTTP client for SignalR that mirrors native global headers on every request,
/// including the WebSocket upgrade (GET) and negotiate (POST).
///
/// Native [WebSocketHubConnectionP2] sends `Authorization: Bearer {jwt}` plus
/// Request-Token, device-id, etc. signalr_core only puts the token in the
/// WebSocket query string by default, which this server rejects (close 1002).
class SignalRHttpClient extends BaseClient {
  SignalRHttpClient({
    required ApiHeadersBuilder headersBuilder,
    required Future<String> Function() tokenProvider,
    NetworkInfo? networkInfo,
    Future<String?> Function()? obtainRefreshedAccessToken,
    Client? inner,
  })  : _headersBuilder = headersBuilder,
        _tokenProvider = tokenProvider,
        _networkInfo = networkInfo,
        _obtainRefreshedAccessToken = obtainRefreshedAccessToken,
        _inner = inner ?? IOClient();

  final ApiHeadersBuilder _headersBuilder;
  final Future<String> Function() _tokenProvider;
  final NetworkInfo? _networkInfo;

  /// P1a: the same refresh mechanism REST uses (one shared
  /// `AuthTokenRefresher`), or null when refresh is not wired — in which
  /// case a 401 propagates exactly as it did before.
  final Future<String?> Function()? _obtainRefreshedAccessToken;

  final Client _inner;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final networkInfo = _networkInfo;
    if (networkInfo != null && !networkInfo.isOnline) {
      throw const NoInternetException();
    }

    final token = await _tokenProvider();
    final response = await _sendWith(request, token);

    if (response.statusCode != 401) {
      return response;
    }

    return _retryAfterRefresh(request, response);
  }

  /// P1a: the hub's own upgrade came back 401, so the stored access token is
  /// the thing the server rejected. Refresh through the shared REST refresh
  /// flow — never through the hub itself — then replay the upgrade once with
  /// the new token. A refresh that yields nothing leaves the original 401
  /// untouched for signalr_core to handle exactly as before.
  Future<StreamedResponse> _retryAfterRefresh(
    BaseRequest request,
    StreamedResponse unauthorized,
  ) async {
    final refresh = _obtainRefreshedAccessToken;
    if (refresh == null || request is! Request) {
      return unauthorized;
    }

    AppLogger.log('[hub] upgrade rejected (401) — attempting token refresh');

    String? refreshedToken;
    try {
      refreshedToken = await refresh();
    } catch (_) {
      refreshedToken = null;
    }

    if (refreshedToken == null || refreshedToken.isEmpty) {
      AppLogger.log('[hub] refresh unavailable — 401 left as-is');
      return unauthorized;
    }

    // Only discarded once the retry is certain, so a returned 401 still
    // carries its body for the caller.
    await unauthorized.stream.drain<void>();

    AppLogger.log('[hub] token refreshed — retrying upgrade once');
    return _sendWith(_copyOf(request), refreshedToken);
  }

  Future<StreamedResponse> _sendWith(BaseRequest request, String token) async {
    final normalized = _stripBearerPrefix(token);
    final globalHeaders = await _headersBuilder.buildGlobalHeaders(
      authToken: normalized,
    );

    for (final entry in globalHeaders.entries) {
      request.headers[entry.key] = entry.value;
    }

    AppLogger.log(
      '[hub] ${request.method} ${request.url.path} — '
      'Authorization: ${normalized.isNotEmpty}, '
      'Request-Token: ${globalHeaders.containsKey('Request-Token')}',
    );

    return _inner.send(request);
  }

  /// A sent [Request] is finalized and cannot be re-sent, so the retry needs
  /// its own copy. Headers are carried over because signalr_core sets the
  /// WebSocket upgrade headers (`Sec-WebSocket-Key` and friends) on it;
  /// [_sendWith] then overwrites the auth/global ones.
  static Request _copyOf(Request original) {
    return Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..headers.addAll(original.headers)
      ..bodyBytes = original.bodyBytes;
  }

  @override
  void close() {
    _inner.close();
  }

  static String _stripBearerPrefix(String token) {
    if (token.startsWith('Bearer ')) {
      return token.substring(7);
    }
    return token;
  }
}

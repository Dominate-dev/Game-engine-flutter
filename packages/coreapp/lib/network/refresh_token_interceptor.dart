import 'package:dio/dio.dart';

/// Retries a request once with a freshly obtained access token after a 401.
///
/// [obtainRefreshedAccessToken] owns the entire refresh contract — reading
/// the stored refresh token, calling the refresh endpoint, persisting the
/// result via the existing storage mechanism, and clearing the stale
/// session on failure. It returns the new access token on success, or
/// `null` when no refresh was possible or it failed; either way this
/// interceptor then just lets the original 401 propagate normally.
///
/// Concurrent 401s share the same in-flight refresh rather than each
/// starting their own.
class RefreshTokenInterceptor extends Interceptor {
  RefreshTokenInterceptor({
    required Dio dio,
    required Future<String?> Function() obtainRefreshedAccessToken,
  })  : _dio = dio,
        _obtainRefreshedAccessToken = obtainRefreshedAccessToken;

  /// Set on the refresh call's own request so a 401 from it is never itself
  /// retried — that would recurse into refreshing the refresh call.
  static const isRefreshCallKey = 'refreshTokenInterceptor.isRefreshCall';

  static const _retriedKey = 'refreshTokenInterceptor.retried';

  final Dio _dio;
  final Future<String?> Function() _obtainRefreshedAccessToken;

  Future<String?>? _pendingRefresh;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final eligible = err.response?.statusCode == 401 &&
        options.extra[isRefreshCallKey] != true &&
        options.extra[_retriedKey] != true;

    if (!eligible) {
      handler.next(err);
      return;
    }

    String? newToken;
    try {
      newToken = await _refreshOnce();
    } catch (_) {
      newToken = null;
    }

    if (newToken == null || newToken.isEmpty) {
      handler.next(err);
      return;
    }

    // Marked before the retry, not after — if the retried call also comes
    // back 401 (e.g. the refreshed token is itself rejected), this flag is
    // what stops a second refresh attempt from being made for it.
    options.extra[_retriedKey] = true;

    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshOnce() {
    final pending = _pendingRefresh;
    if (pending != null) {
      return pending;
    }
    final future = _obtainRefreshedAccessToken();
    _pendingRefresh = future;
    future.whenComplete(() {
      if (identical(_pendingRefresh, future)) {
        _pendingRefresh = null;
      }
    });
    return future;
  }
}

import 'package:dio/dio.dart';

import '../l10n/app_strings.dart';
import 'api_headers_builder.dart';

/// Dio interceptor mirroring native [AppBaseInterceptor] global headers.
class AppBaseInterceptor extends Interceptor {
  AppBaseInterceptor({
    required ApiHeadersBuilder headersBuilder,
    required String? Function() tokenProvider,
  })  : _headersBuilder = headersBuilder,
        _tokenProvider = tokenProvider;

  final ApiHeadersBuilder _headersBuilder;
  final String? Function() _tokenProvider;

  /// Set on a request's `extra` to send a specific token instead of the
  /// one `tokenProvider` supplies — used only by the refresh-token call
  /// itself, which must authenticate with the refresh token, not the
  /// (expired) access token.
  static const authTokenOverrideKey = 'appBaseInterceptor.authTokenOverride';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final tokenOverride = options.extra[authTokenOverrideKey] as String?;
      final globalHeaders = await _headersBuilder.buildGlobalHeaders(
        authToken: tokenOverride ?? _tokenProvider(),
      );
      options.headers.addAll(globalHeaders);
      handler.next(options);
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
          message: '${AppStrings.current.failedToBuildHeaders}: $error',
        ),
      );
    }
  }
}

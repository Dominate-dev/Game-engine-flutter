import 'package:chucker_flutter/chucker_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api_headers_builder.dart';
import 'app_base_interceptor.dart';
import 'connectivity_interceptor.dart';
import 'network_info.dart';
import 'refresh_token_interceptor.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    required ApiHeadersBuilder headersBuilder,
    String? Function()? tokenProvider,
    NetworkInfo? networkInfo,
    bool enableChucker = kDebugMode,
    bool enableLogging = kDebugMode,
    Future<String?> Function()? obtainRefreshedAccessToken,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 60),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        ) {
    if (networkInfo != null) {
      _dio.interceptors.add(ConnectivityInterceptor(networkInfo));
    }

    _dio.interceptors.add(
      AppBaseInterceptor(
        headersBuilder: headersBuilder,
        tokenProvider: tokenProvider ?? () => null,
      ),
    );

    // N2: absent by default (e.g. every existing test's ApiClient subclass
    // never reaches Dio at all) — only the production client wires this in.
    if (obtainRefreshedAccessToken != null) {
      _dio.interceptors.add(
        RefreshTokenInterceptor(
          dio: _dio,
          obtainRefreshedAccessToken: obtainRefreshedAccessToken,
        ),
      );
    }

    // Debug only: logs the Authorization header and full request/response
    // bodies, including the login body. Must never run in a release build.
    if (enableLogging) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          compact: true,
        ),
      );
    }

    if (enableChucker) {
      _dio.interceptors.add(ChuckerDioInterceptor());
    }
  }

  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    // N2: used only by the refresh-token call itself — see
    // AppBaseInterceptor.authTokenOverrideKey / RefreshTokenInterceptor.
    String? authTokenOverride,
    bool isAuthRefreshCall = false,
  }) =>
      _dio.get<T>(
        path,
        queryParameters: query,
        options: (authTokenOverride == null && !isAuthRefreshCall)
            ? null
            : Options(
                extra: {
                  if (authTokenOverride != null)
                    AppBaseInterceptor.authTokenOverrideKey: authTokenOverride,
                  if (isAuthRefreshCall)
                    RefreshTokenInterceptor.isRefreshCallKey: true,
                },
              ),
      );

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
  }) =>
      _dio.post<T>(path, data: data);

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
  }) =>
      _dio.put<T>(path, data: data);

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
  }) =>
      _dio.delete<T>(path, data: data);
}

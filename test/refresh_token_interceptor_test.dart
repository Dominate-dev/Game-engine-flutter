import 'dart:async';
import 'dart:typed_data';

import 'package:coreapp/coreapp.dart';
import 'package:coreapp/network/app_base_interceptor.dart';
import 'package:coreapp/network/refresh_token_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// N2 — RefreshTokenInterceptor, combined with the real AppBaseInterceptor
// (the same pair ApiClient wires together in production). Driven through a
// real Dio instance with a fake HttpClientAdapter — no mock-adapter
// dependency needed, Dio already exposes a settable httpClientAdapter for
// exactly this. AuthTokenRefresher's own "clear auth on failure" contract is
// covered separately in auth_token_refresher_test.dart; here the refresh
// callback is a plain fake, since this file is only about the retry
// mechanics.

class _RecordedRequest {
  const _RecordedRequest(this.path, this.headers);

  final String path;
  final Map<String, dynamic> headers;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final List<_RecordedRequest> requests = [];

  /// Returns (statusCode, body) for the given request and its 0-based call
  /// index (across every path this adapter has seen).
  final (int, Map<String, dynamic>) Function(
    RequestOptions options,
    int callIndex,
  ) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // A snapshot, not a live reference — the retry mutates the SAME
    // RequestOptions.headers map in place, which would otherwise make an
    // earlier recorded entry appear to change after the fact.
    requests.add(
      _RecordedRequest(options.path, Map<String, dynamic>.from(options.headers)),
    );
    final (statusCode, body) = respond(options, requests.length - 1);
    return ResponseBody.fromString(
      '{${body.entries.map((e) => '"${e.key}":${_jsonValue(e.value)}').join(',')}}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  String _jsonValue(Object? value) =>
      value is String ? '"$value"' : value.toString();

  @override
  void close({bool force = false}) {}
}

void main() {
  late SharedPrefsService prefs;
  late Dio dio;
  late _FakeAdapter adapter;

  Future<void> setUpDio({
    required Future<String?> Function() obtainRefreshedAccessToken,
    required (int, Map<String, dynamic>) Function(RequestOptions, int)
        respond,
  }) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPrefsService.init();
    await prefs.setToken(value: 'old-token');
    await prefs.setRefreshToken(value: 'old-refresh');

    dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
    adapter = _FakeAdapter(respond);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      AppBaseInterceptor(
        headersBuilder: ApiHeadersBuilder(prefs),
        tokenProvider: () => prefs.getToken(),
      ),
    );
    dio.interceptors.add(
      RefreshTokenInterceptor(
        dio: dio,
        obtainRefreshedAccessToken: obtainRefreshedAccessToken,
      ),
    );
  }

  test(
    '1. a 401 triggers a refresh, then the original request is retried and '
    'succeeds',
    () async {
      var refreshCalls = 0;
      await setUpDio(
        obtainRefreshedAccessToken: () async {
          refreshCalls++;
          await prefs.setToken(value: 'new-token');
          return 'new-token';
        },
        respond: (options, callIndex) => callIndex == 0
            ? (401, {'succeeded': false})
            : (200, {'succeeded': true, 'data': 'ok'}),
      );

      final response = await dio.get<Map<String, dynamic>>('/protected');

      expect(response.statusCode, 200);
      expect(response.data?['data'], 'ok');
      expect(refreshCalls, 1);
      expect(adapter.requests, hasLength(2), reason: 'original + one retry');
    },
  );

  test(
    '2. the retried request actually uses the new token, not the old one',
    () async {
      await setUpDio(
        obtainRefreshedAccessToken: () async {
          await prefs.setToken(value: 'new-token');
          return 'new-token';
        },
        respond: (options, callIndex) =>
            callIndex == 0 ? (401, {'succeeded': false}) : (200, {'succeeded': true}),
      );

      await dio.get<Map<String, dynamic>>('/protected');

      expect(adapter.requests[0].headers['Authorization'], 'Bearer old-token');
      expect(adapter.requests[1].headers['Authorization'], 'Bearer new-token');
    },
  );

  test(
    '3. a refresh failure (callback returns null) does not retry, and does '
    'not loop',
    () async {
      var refreshCalls = 0;
      await setUpDio(
        obtainRefreshedAccessToken: () async {
          refreshCalls++;
          return null;
        },
        respond: (options, callIndex) => (401, {'succeeded': false}),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCalls, 1, reason: 'never retried, so never asked twice');
      expect(adapter.requests, hasLength(1), reason: 'no retry was attempted');
    },
  );

  test(
    '4. a missing refresh token (callback returns null immediately) does '
    'not cause an infinite retry',
    () async {
      var refreshCalls = 0;
      await setUpDio(
        obtainRefreshedAccessToken: () async {
          refreshCalls++;
          return null; // AuthTokenRefresher's own shape for "no usable token"
        },
        respond: (options, callIndex) => (401, {'succeeded': false}),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCalls, 1);
      expect(adapter.requests, hasLength(1));
    },
  );

  test(
    '5. a non-401 failure is never sent through the refresh path at all',
    () async {
      var refreshCalls = 0;
      await setUpDio(
        obtainRefreshedAccessToken: () async {
          refreshCalls++;
          return 'new-token';
        },
        respond: (options, callIndex) => (500, {'succeeded': false}),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/protected'),
        throwsA(
          isA<DioException>()
              .having((e) => e.response?.statusCode, 'statusCode', 500),
        ),
      );

      expect(refreshCalls, 0);
      expect(adapter.requests, hasLength(1));
    },
  );

  test(
    '6. concurrent 401s share a single refresh instead of each starting '
    'their own',
    () async {
      // Calls RefreshTokenInterceptor.onError directly, twice, back to
      // back — deterministic proof of the dedup itself, independent of
      // however Dio happens to interleave two real in-flight requests.
      var refreshCalls = 0;
      final refreshCompleter = Completer<String?>();
      await setUpDio(
        obtainRefreshedAccessToken: () {
          refreshCalls++;
          return refreshCompleter.future;
        },
        respond: (options, callIndex) => (200, {'succeeded': true}),
      );
      final interceptor =
          dio.interceptors.whereType<RefreshTokenInterceptor>().single;

      DioException error(String path) {
        final options = RequestOptions(path: path, method: 'GET');
        return DioException(
          requestOptions: options,
          response: Response<dynamic>(requestOptions: options, statusCode: 401),
        );
      }

      final futureA = interceptor.onError(error('/a'), ErrorInterceptorHandler());
      final futureB = interceptor.onError(error('/b'), ErrorInterceptorHandler());

      await prefs.setToken(value: 'new-token');
      refreshCompleter.complete('new-token');
      await Future.wait([futureA, futureB]);

      expect(refreshCalls, 1, reason: 'exactly one refresh for both 401s');
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coreapp/coreapp.dart';
import 'package:coreapp/features/auth/data/services/auth_token_refresher.dart';
import 'package:coreapp/signalr/signalr_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

// P1a — SignalR access-token refresh.
//
// The hub does NOT use signalr_core's accessTokenFactory: negotiate would
// append ?access_token= to the WebSocket URL, which this server rejects
// (close 1002 — see signalr_service.dart). The token reaches the hub through
// SignalRHttpClient instead, which signalr_core's own
// web_socket_channel_io.dart drives via `client.send(request)` for the
// upgrade GET. That makes send() the one place a hub 401 is observable, and
// therefore where the refresh belongs.
//
// The refresh itself goes through the same shared AuthTokenRefresher the
// REST interceptor uses (N2) — never back through the hub, so there is no
// recursion and only one refresh mechanism.

class _FakeInnerClient extends BaseClient {
  _FakeInnerClient(this.respond);

  final List<BaseRequest> requests = [];

  /// Status code for the given request and its 0-based call index.
  final int Function(BaseRequest request, int callIndex) respond;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final index = requests.length;
    requests.add(request);
    final statusCode = respond(request, index);
    return StreamedResponse(
      Stream.value(utf8.encode('{}')),
      statusCode,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  int refreshCalls = 0;
  String? lastRefreshTokenUsed;
  late Future<Result<AuthSession>> Function(String refreshToken) onRefresh;

  @override
  Future<Result<AuthSession>> login(LoginParams params) async =>
      throw UnimplementedError('not used by P1a');

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    refreshCalls++;
    lastRefreshTokenUsed = refreshToken;
    return onRefresh(refreshToken);
  }
}

/// The upgrade request signalr_core actually builds — see
/// signalr_core's web_socket_channel_io.dart.
Request _upgradeRequest() => Request('GET', Uri.parse('https://test.local/GameHub'))
  ..headers.addAll({
    'Connection': 'Upgrade',
    'Upgrade': 'websocket',
    'Sec-WebSocket-Key': 'nonce',
    'Sec-WebSocket-Version': '13',
  });

String? _authOf(BaseRequest request) => request.headers['Authorization'];

void main() {
  late SharedPrefsService prefs;
  late _FakeAuthRepository repository;
  late AuthTokenRefresher refresher;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPrefsService.init();
    await prefs.setToken(value: 'old-token');
    await prefs.setRefreshToken(value: 'old-refresh');
    repository = _FakeAuthRepository();
    refresher = AuthTokenRefresher(repository: repository, prefs: prefs);
  });

  SignalRHttpClient clientWith(_FakeInnerClient inner) => SignalRHttpClient(
        headersBuilder: ApiHeadersBuilder(prefs),
        tokenProvider: () async => prefs.getToken() ?? '',
        obtainRefreshedAccessToken: refresher.call,
        inner: inner,
      );

  test(
    '1. a valid token is used as-is — the upgrade succeeds and nothing is '
    'refreshed',
    () async {
      final inner = _FakeInnerClient((request, index) => 101);

      final response = await clientWith(inner).send(_upgradeRequest());

      expect(response.statusCode, 101);
      expect(inner.requests, hasLength(1));
      expect(_authOf(inner.requests.single), 'Bearer old-token');
      expect(repository.refreshCalls, 0);
    },
  );

  test(
    '2. a 401 upgrade refreshes and retries once, and the retry carries the '
    'new token',
    () async {
      repository.onRefresh = (_) async => Result.success(
            const AuthSession(
              token: 'new-token',
              refreshToken: 'new-refresh',
              userId: '47',
            ),
          );
      final inner = _FakeInnerClient(
        (request, index) => index == 0 ? 401 : 101,
      );

      final response = await clientWith(inner).send(_upgradeRequest());

      expect(response.statusCode, 101, reason: 'the retry is what is returned');
      expect(inner.requests, hasLength(2), reason: 'original + one retry');
      expect(_authOf(inner.requests[0]), 'Bearer old-token');
      expect(_authOf(inner.requests[1]), 'Bearer new-token');
      expect(repository.refreshCalls, 1);
      expect(repository.lastRefreshTokenUsed, 'old-refresh');
    },
  );

  test(
    '3. the refreshed session is persisted through the existing storage '
    'mechanism',
    () async {
      repository.onRefresh = (_) async => Result.success(
            const AuthSession(
              token: 'new-token',
              refreshToken: 'new-refresh',
              userId: '47',
            ),
          );
      final inner = _FakeInnerClient(
        (request, index) => index == 0 ? 401 : 101,
      );

      await clientWith(inner).send(_upgradeRequest());

      expect(prefs.getToken(), 'new-token');
      expect(prefs.getRefreshToken(), 'new-refresh');
      expect(prefs.getUserId(), 47);
    },
  );

  test(
    '4. concurrent hub 401s share one refresh',
    () async {
      final gate = Completer<Result<AuthSession>>();
      repository.onRefresh = (_) => gate.future;
      final inner = _FakeInnerClient(
        // Both upgrades 401; both retries succeed.
        (request, index) => index < 2 ? 401 : 101,
      );
      final client = clientWith(inner);

      final first = client.send(_upgradeRequest());
      final second = client.send(_upgradeRequest());
      await Future<void>.delayed(Duration.zero);
      gate.complete(
        Result.success(const AuthSession(token: 'new-token')),
      );

      final responses = await Future.wait([first, second]);

      expect(
        repository.refreshCalls,
        1,
        reason: 'the shared AuthTokenRefresher coordinates both',
      );
      expect(responses[0].statusCode, 101);
      expect(responses[1].statusCode, 101);
    },
  );

  test(
    '5. a missing refresh token does not retry, and clears the stored auth',
    () async {
      await prefs.clearAuth();
      await prefs.setToken(value: 'old-token');
      // No refresh token stored.
      final inner = _FakeInnerClient((request, index) => 401);

      final response = await clientWith(inner).send(_upgradeRequest());

      expect(response.statusCode, 401, reason: 'the original 401 is returned');
      expect(inner.requests, hasLength(1), reason: 'no retry');
      expect(repository.refreshCalls, 0);
      expect(prefs.getToken(), isNull);
    },
  );

  test(
    '6. a failed refresh does not retry, and clears the stored auth',
    () async {
      repository.onRefresh = (_) async => Result.failure(UnauthorizedFailure());
      final inner = _FakeInnerClient((request, index) => 401);

      final response = await clientWith(inner).send(_upgradeRequest());

      expect(response.statusCode, 401);
      expect(inner.requests, hasLength(1), reason: 'no retry');
      expect(repository.refreshCalls, 1);
      expect(prefs.getToken(), isNull);
      expect(prefs.getRefreshToken(), isNull);
    },
  );

  test(
    '7. a retry that is itself rejected is not refreshed again — one retry '
    'only, no loop',
    () async {
      repository.onRefresh = (_) async => Result.success(
            const AuthSession(token: 'new-token'),
          );
      final inner = _FakeInnerClient((request, index) => 401);

      final response = await clientWith(inner).send(_upgradeRequest());

      expect(response.statusCode, 401);
      expect(inner.requests, hasLength(2), reason: 'original + exactly one retry');
      expect(repository.refreshCalls, 1);
    },
  );

  test(
    '8. a non-401 failure passes straight through, untouched',
    () async {
      final inner = _FakeInnerClient((request, index) => 500);

      final response = await clientWith(inner).send(_upgradeRequest());

      expect(response.statusCode, 500);
      expect(inner.requests, hasLength(1));
      expect(repository.refreshCalls, 0);
    },
  );

  test(
    '9. with no refresher wired, a 401 behaves exactly as it did before P1a',
    () async {
      final inner = _FakeInnerClient((request, index) => 401);
      final client = SignalRHttpClient(
        headersBuilder: ApiHeadersBuilder(prefs),
        tokenProvider: () async => prefs.getToken() ?? '',
        inner: inner,
      );

      final response = await client.send(_upgradeRequest());

      expect(response.statusCode, 401);
      expect(inner.requests, hasLength(1));
      expect(prefs.getToken(), 'old-token', reason: 'nothing was cleared');
    },
  );

  test(
    '10. the upgrade headers signalr_core sets are preserved on the retry',
    () async {
      repository.onRefresh = (_) async => Result.success(
            const AuthSession(token: 'new-token'),
          );
      final inner = _FakeInnerClient(
        (request, index) => index == 0 ? 401 : 101,
      );

      await clientWith(inner).send(_upgradeRequest());

      final retry = inner.requests[1];
      expect(retry.method, 'GET');
      expect(retry.url.path, '/GameHub');
      expect(retry.headers['Upgrade'], 'websocket');
      expect(retry.headers['Sec-WebSocket-Key'], 'nonce');
      expect(retry.headers['Sec-WebSocket-Version'], '13');
    },
  );

  test(
    '11. no credential-shaped value is interpolated into any log call',
    () async {
      // Requirement 6 is about what reaches the logs, and AppLogger has no
      // seam to capture (SEC1b). This asserts it at the source instead, on
      // the one file that both holds tokens and logs.
      final source = File(
        'packages/coreapp/lib/signalr/signalr_http_client.dart',
      ).readAsStringSync();

      final logCalls = RegExp(r'AppLogger\.log\(([\s\S]*?)\);')
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toList();

      expect(logCalls, isNotEmpty, reason: 'sanity — the file does log');

      // A credential name may only be interpolated through a non-revealing
      // accessor. Bare `$token` / `${token}` would print the value itself.
      const safeAccessors = {'.isNotEmpty', '.isEmpty', '.length'};
      final interpolation =
          RegExp(r'\$\{?(token|normalized|refreshedToken)([A-Za-z0-9_.]*)');

      for (final call in logCalls) {
        for (final match in interpolation.allMatches(call)) {
          final suffix = match.group(2)!;
          if (suffix.isNotEmpty && !suffix.startsWith('.')) {
            continue; // a longer identifier, e.g. tokenProvider — not the value
          }
          expect(
            safeAccessors.contains(suffix),
            isTrue,
            reason: 'log interpolates the credential value itself '
                '(`${match.group(0)}`) in: $call',
          );
        }
      }
    },
  );
}

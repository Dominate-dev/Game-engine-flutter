import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:coreapp/features/auth/data/services/auth_token_refresher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// N2 — AuthTokenRefresher: the "get me a valid access token, or clear the
// stale session" policy consumed by RefreshTokenInterceptor. Exercised here
// directly against a fake AuthRepository — no HTTP/Dio needed, since
// AuthRemoteDataSourceImpl.refresh()'s own request/parse contract is already
// covered separately in remote_datasources_test.dart.

class _FakeAuthRepository implements AuthRepository {
  int refreshCalls = 0;
  String? lastRefreshTokenUsed;
  late Result<AuthSession> Function(String refreshToken) onRefresh;

  /// Set instead of [onRefresh] when a test needs to hold the refresh open.
  Future<Result<AuthSession>> Function(String refreshToken)? onRefreshAsync;

  @override
  Future<Result<AuthSession>> login(LoginParams params) async =>
      throw UnimplementedError('not used by AuthTokenRefresher');

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    refreshCalls++;
    lastRefreshTokenUsed = refreshToken;
    final async = onRefreshAsync;
    if (async != null) {
      return async(refreshToken);
    }
    return Future.value(onRefresh(refreshToken));
  }
}

void main() {
  late SharedPrefsService prefs;
  late _FakeAuthRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPrefsService.init();
    repository = _FakeAuthRepository();
  });

  AuthTokenRefresher refresher() =>
      AuthTokenRefresher(repository: repository, prefs: prefs);

  test(
    'a missing refresh token clears auth and returns null without calling '
    'the repository',
    () async {
      await prefs.setToken(value: 'stale-token');
      // No refresh token was ever stored.

      final token = await refresher().call();

      expect(token, isNull);
      expect(repository.refreshCalls, 0);
      expect(prefs.getToken(), isNull);
    },
  );

  test(
    'an empty refresh token is treated the same as a missing one',
    () async {
      await prefs.setToken(value: 'stale-token');
      await prefs.setRefreshToken(value: '');

      final token = await refresher().call();

      expect(token, isNull);
      expect(repository.refreshCalls, 0);
      expect(prefs.getToken(), isNull);
    },
  );

  test(
    'a successful refresh persists the new session and returns the new '
    'access token',
    () async {
      await prefs.setToken(value: 'old-token');
      await prefs.setRefreshToken(value: 'old-refresh');
      repository.onRefresh = (refreshToken) => Result.success(
            const AuthSession(
              token: 'new-token',
              refreshToken: 'new-refresh',
              userId: '47',
            ),
          );

      final token = await refresher().call();

      expect(token, 'new-token');
      expect(
        repository.lastRefreshTokenUsed,
        'old-refresh',
        reason: 'the stored refresh token is what gets sent',
      );
      expect(prefs.getToken(), 'new-token');
      expect(prefs.getRefreshToken(), 'new-refresh');
      expect(prefs.getUserId(), 47);
    },
  );

  test(
    'a refresh that reports failure clears the cached auth and returns null',
    () async {
      await prefs.setToken(value: 'old-token');
      await prefs.setRefreshToken(value: 'old-refresh');
      repository.onRefresh = (_) => Result.failure(UnauthorizedFailure());

      final token = await refresher().call();

      expect(token, isNull);
      expect(prefs.getToken(), isNull);
      expect(prefs.getRefreshToken(), isNull);
    },
  );

  test(
    'P1a: concurrent callers share one refresh — this is what makes REST '
    'and SignalR one mechanism rather than two',
    () async {
      await prefs.setToken(value: 'old-token');
      await prefs.setRefreshToken(value: 'old-refresh');
      final gate = Completer<Result<AuthSession>>();
      repository.onRefreshAsync = (_) => gate.future;

      final shared = refresher();
      // Stand-ins for the REST interceptor and the SignalR upgrade client,
      // both holding the same instance (as authTokenRefresherProvider gives
      // them) and both hitting a 401 before either refresh completes.
      final fromRest = shared.call();
      final fromHub = shared.call();
      await Future<void>.delayed(Duration.zero);
      gate.complete(
        Result.success(const AuthSession(token: 'new-token')),
      );

      final tokens = await Future.wait([fromRest, fromHub]);

      expect(repository.refreshCalls, 1);
      expect(tokens, ['new-token', 'new-token']);
    },
  );

  test(
    'the in-flight guard is released, so a later 401 can refresh again',
    () async {
      await prefs.setToken(value: 'old-token');
      await prefs.setRefreshToken(value: 'old-refresh');
      repository.onRefresh = (_) => Result.success(
            const AuthSession(token: 'new-token', refreshToken: 'r2'),
          );
      final shared = refresher();

      expect(await shared.call(), 'new-token');
      expect(await shared.call(), 'new-token');

      expect(repository.refreshCalls, 2, reason: 'sequential, not concurrent');
    },
  );

  test(
    'a refresh that succeeds but carries an empty token is treated as a '
    'failure and clears auth',
    () async {
      await prefs.setToken(value: 'old-token');
      await prefs.setRefreshToken(value: 'old-refresh');
      repository.onRefresh = (_) => Result.success(
            const AuthSession(token: ''),
          );

      final token = await refresher().call();

      expect(token, isNull);
      expect(prefs.getToken(), isNull);
    },
  );
}

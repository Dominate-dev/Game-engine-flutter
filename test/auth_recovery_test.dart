import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coreapp/coreapp.dart';
import 'package:coreapp/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:coreapp/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:coreapp/features/auth/data/services/auth_token_refresher.dart';
import 'package:coreapp/network/app_base_interceptor.dart';
import 'package:coreapp/network/refresh_token_interceptor.dart';
import 'package:coreapp/signalr/signalr_http_client.dart';
import 'package:dio/dio.dart'
    show
        BaseOptions,
        Dio,
        DioException,
        Headers,
        HttpClientAdapter,
        Options,
        RequestOptions,
        Response,
        ResponseBody;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_core/signalr_core.dart'
    show
        ClosedCallback,
        HubConnection,
        HubConnectionState,
        JsonHubProtocol,
        MethodInvocationFunc,
        ReconnectedCallback,
        ReconnectingCallback;

// Authentication recovery after token expiry.
//
// A native host hands the engine an access token and a socialMediaId, never a
// refresh token. The overnight failure was:
//
//   expired token -> 401 -> no refresh token -> clearAuth() -> empty Bearer
//     -> SignalR `failed` with no retry -> stuck connection overlay
//
// The refresher now falls back to the existing LoginUseCase with the stored
// socialMediaId — the request native's own auto-login sends for a social
// account (userName and password empty) — before giving up.

const _url = 'ws://fake.test/hub';
const _socialMediaId = 'sm-1';

Result<AuthSession> _session(
  String token, {
  String? refreshToken,
  String? userId,
}) =>
    Result.success(
      AuthSession(token: token, refreshToken: refreshToken, userId: userId),
    );

class _FakeAuthRepository implements AuthRepository {
  int refreshCalls = 0;
  int loginCalls = 0;
  final loginParams = <LoginParams>[];

  Future<Result<AuthSession>> Function(String refreshToken) onRefresh =
      (_) async => Result.failure(UnauthorizedFailure());
  Future<Result<AuthSession>> Function(LoginParams params) onLogin =
      (_) async => _session('new-token');

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    refreshCalls++;
    return onRefresh(refreshToken);
  }

  @override
  Future<Result<AuthSession>> login(LoginParams params) {
    loginCalls++;
    loginParams.add(params);
    return onLogin(params);
  }
}

/// ApiClient's own Dio wiring (AppBaseInterceptor, then
/// RefreshTokenInterceptor) over a scripted adapter, so the real login
/// datasource runs through the same interceptors a REST call does.
class _DioApiClient extends ApiClient {
  _DioApiClient(this.dio, ApiHeadersBuilder headersBuilder)
      : super(
          baseUrl: 'https://test.local',
          headersBuilder: headersBuilder,
          enableChucker: false,
          enableLogging: false,
        );

  final Dio dio;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    String? authTokenOverride,
    bool isAuthRefreshCall = false,
  }) =>
      dio.get<T>(
        path,
        queryParameters: query,
        options: Options(
          extra: {
            if (authTokenOverride != null)
              AppBaseInterceptor.authTokenOverrideKey: authTokenOverride,
            if (isAuthRefreshCall) RefreshTokenInterceptor.isRefreshCallKey: true,
          },
        ),
      );

  @override
  Future<Response<T>> post<T>(String path, {dynamic data}) =>
      dio.post<T>(path, data: data);
}

class _Seen {
  const _Seen(this.path, this.authorization, this.data);

  final String path;
  final String? authorization;
  final Object? data;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Future<(int, Map<String, dynamic>)> Function(RequestOptions options)
      respond;
  final seen = <_Seen>[];

  int count(String path) => seen.where((s) => s.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(
      _Seen(
        options.path,
        options.headers['Authorization']?.toString(),
        options.data,
      ),
    );
    final (status, body) = await respond(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RestChain {
  _RestChain(this.client, this.adapter, this.refresher);

  final _DioApiClient client;
  final _Adapter adapter;
  final AuthTokenRefresher refresher;
}

/// The production REST wiring, with only the socket replaced.
_RestChain _restChain(SharedPrefsService prefs, _Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
  dio.httpClientAdapter = adapter;
  final headers = ApiHeadersBuilder(prefs);
  late final AuthTokenRefresher refresher;
  dio.interceptors
    ..add(
      AppBaseInterceptor(headersBuilder: headers, tokenProvider: prefs.getToken),
    )
    ..add(
      RefreshTokenInterceptor(
        dio: dio,
        obtainRefreshedAccessToken: () => refresher.call(),
      ),
    );
  final client = _DioApiClient(dio, headers);
  refresher = AuthTokenRefresher(
    repository: AuthRepositoryImpl(AuthRemoteDataSourceImpl(client)),
    prefs: prefs,
  );
  return _RestChain(client, adapter, refresher);
}

Map<String, dynamic> _loginEnvelope(String token) => {
      'succeeded': true,
      'data': {'token': token},
    };

const _protected = '/api/protected';

/// The hub's WebSocket upgrade, answering 101 only to [validToken].
class _HubServer extends http.BaseClient {
  _HubServer(this.validToken);

  String validToken;
  final authorizations = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final auth = request.headers['Authorization'];
    authorizations.add(auth);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      auth == 'Bearer $validToken' ? 101 : 401,
      request: request,
    );
  }
}

http.Request _upgradeRequest(String url) => http.Request('GET', Uri.parse(url))
  ..headers.addAll({
    'Connection': 'Upgrade',
    'Upgrade': 'websocket',
    'Sec-WebSocket-Key': 'nonce',
    'Sec-WebSocket-Version': '13',
  });

/// A hub whose start() performs its upgrade through the real
/// SignalRHttpClient, exactly where production observes a hub 401.
class _UpgradingHub extends HubConnection {
  _UpgradingHub(this._client, this._url) : super(protocol: JsonHubProtocol());

  final SignalRHttpClient _client;
  final String _url;
  final invoked = <String>[];
  HubConnectionState _state = HubConnectionState.disconnected;

  @override
  HubConnectionState? get state => _state;

  @override
  String? get connectionId => 'fake';

  @override
  Future<void>? start() async {
    final response = await _client.send(_upgradeRequest(_url));
    await response.stream.drain<void>();
    if (response.statusCode != 101) {
      throw Exception('upgrade rejected (${response.statusCode})');
    }
    _state = HubConnectionState.connected;
  }

  @override
  Future<void> stop() async => _state = HubConnectionState.disconnected;

  @override
  Future<dynamic> invoke(String methodName, {List<dynamic>? args}) async {
    invoked.add(methodName);
    return null;
  }

  @override
  void on(String methodName, MethodInvocationFunc newMethod) {}

  @override
  void off(String methodName, {MethodInvocationFunc? method}) {}

  @override
  void onclose(ClosedCallback callback) {}

  @override
  void onreconnecting(ReconnectingCallback callback) {}

  @override
  void onreconnected(ReconnectedCallback callback) {}

  int count(String method) => invoked.where((m) => m == method).length;
}

class _Hub {
  _Hub(this.prefs, this.repository, this.refresher, this.server, this.service,
      this.hubs);

  final SharedPrefsService prefs;
  final _FakeAuthRepository repository;
  final AuthTokenRefresher refresher;
  final _HubServer server;
  final SignalRService service;
  final List<_UpgradingHub> hubs;

  int count(String method) =>
      hubs.fold(0, (sum, hub) => sum + hub.count(method));
}

/// The real SignalRService and refresher; the hub upgrade is the only fake.
_Hub _hubHarness(SharedPrefsService prefs) {
  final repository = _FakeAuthRepository();
  final refresher = AuthTokenRefresher(repository: repository, prefs: prefs);
  final server = _HubServer('new-token');
  final hubs = <_UpgradingHub>[];
  final service = SignalRService(
    headersBuilder: ApiHeadersBuilder(prefs),
    obtainRefreshedAccessToken: refresher.call,
    hubConnectionFactory: (url, tokenFactory) {
      final hub = _UpgradingHub(
        SignalRHttpClient(
          headersBuilder: ApiHeadersBuilder(prefs),
          tokenProvider: tokenFactory,
          obtainRefreshedAccessToken: refresher.call,
          inner: server,
        ),
        url,
      );
      hubs.add(hub);
      return hub;
    },
  );
  return _Hub(prefs, repository, refresher, server, service, hubs);
}

class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(const StickerPage(items: [], pageIndex: 0, pageSize: 20));

  @override
  Future<Result<bool>> payStickerGroup(int id) async => Result.success(true);
}

class _FakeNetworkInfo implements NetworkInfo {
  @override
  bool get isOnline => true;
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();
  @override
  void dispose() {}
}

class _FakeAudioService extends AudioService {
  @override
  Future<void> start(
    String asset, {
    AudioSourceType type = AudioSourceType.sfx,
    String? package,
    bool? loop,
    double? volume,
  }) async {}

  @override
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {}

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

const _expiredConfig = GameEngineConfig(
  token: 'expired',
  userId: 47,
  socialMediaId: _socialMediaId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPrefsService> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPrefsService.init();
  }

  const expiredSession = <String, Object>{
    'auth_token': 'expired',
    'social_media_id': _socialMediaId,
    'user_id': '47',
    'app_language': AppLanguage.english,
  };

  group('AuthTokenRefresher', () {
    late SharedPrefsService prefs;
    late _FakeAuthRepository repository;
    late AuthTokenRefresher refresher;

    Future<void> setUpWith(Map<String, Object> values) async {
      prefs = await prefsWith(values);
      repository = _FakeAuthRepository();
      refresher = AuthTokenRefresher(repository: repository, prefs: prefs);
    }

    test('a stored refresh token is used, and login is not', () async {
      await setUpWith({...expiredSession, 'refresh_token': 'r1'});
      repository.onRefresh = (_) async => _session('refreshed');

      expect(await refresher.call(), 'refreshed');
      expect(repository.refreshCalls, 1);
      expect(repository.loginCalls, 0);
    });

    test('no refresh token: the existing login runs once, with the stored '
        'socialMediaId', () async {
      await setUpWith(expiredSession);

      expect(await refresher.call(), 'new-token');
      expect(repository.refreshCalls, 0);
      expect(repository.loginCalls, 1);
      expect(
        repository.loginParams.single,
        const LoginParams(
          userName: '',
          password: '',
          socialMediaId: _socialMediaId,
        ),
      );
    });

    test('a successful fallback login stores the new token and keeps the '
        'socialMediaId and userId', () async {
      await setUpWith(expiredSession);

      await refresher.call();

      expect(prefs.getToken(), 'new-token');
      expect(prefs.getSocialMediaId(), _socialMediaId);
      expect(prefs.getUserId(), 47);
    });

    test('a successful fallback login does not clear auth — the refresh token '
        'it returns is kept for the next 401', () async {
      await setUpWith(expiredSession);
      repository.onLogin = (_) async =>
          _session('new-token', refreshToken: 'r2', userId: '47');

      await refresher.call();

      expect(prefs.getRefreshToken(), 'r2');
      expect(prefs.getSocialMediaId(), _socialMediaId,
          reason: 'clearAuth() would have removed it');

      repository.onRefresh = (_) async => _session('from-refresh');
      expect(await refresher.call(), 'from-refresh');
      expect(repository.loginCalls, 1, reason: 'the refresh flow took over');
    });

    test('a failed refresh falls back to the login before anything is '
        'cleared', () async {
      await setUpWith({...expiredSession, 'refresh_token': 'r1'});
      repository.onRefresh = (_) async => Result.failure(UnauthorizedFailure());

      expect(await refresher.call(), 'new-token');
      expect(repository.refreshCalls, 1);
      expect(repository.loginCalls, 1);
      expect(prefs.getSocialMediaId(), _socialMediaId);
      expect(prefs.getUserId(), 47);
    });

    test('a failed fallback login ends cleanly: one attempt, null, and the '
        'existing clear', () async {
      await setUpWith({...expiredSession, 'refresh_token': 'r1'});
      repository.onLogin = (_) async => Result.failure(UnauthorizedFailure());

      expect(await refresher.call(), isNull);
      expect(repository.refreshCalls, 1);
      expect(repository.loginCalls, 1, reason: 'no retry loop');
      expect(prefs.getToken(), isNull);
      expect(prefs.getRefreshToken(), isNull);
    });

    test('no socialMediaId keeps the existing failure: no login, auth '
        'cleared', () async {
      await setUpWith({'auth_token': 'expired', 'user_id': '47'});

      expect(await refresher.call(), isNull);
      expect(repository.loginCalls, 0);
      expect(prefs.getToken(), isNull);
    });

    test('a blank socialMediaId is no socialMediaId', () async {
      await setUpWith({'auth_token': 'expired', 'social_media_id': '   '});

      expect(await refresher.call(), isNull);
      expect(repository.loginCalls, 0);
    });

    test('a login that succeeds with an empty token is a failure', () async {
      await setUpWith(expiredSession);
      repository.onLogin = (_) async => _session('');

      expect(await refresher.call(), isNull);
      expect(repository.loginCalls, 1);
      expect(prefs.getToken(), isNull);
    });

    test('a login session without a userId leaves the stored one', () async {
      await setUpWith(expiredSession);
      repository.onLogin = (_) async => _session('new-token');

      await refresher.call();

      expect(prefs.getUserId(), 47);
    });

    test('REST and SignalR 401s together share one login', () async {
      await setUpWith(expiredSession);
      final gate = Completer<Result<AuthSession>>();
      repository.onLogin = (_) => gate.future;

      final fromRest = refresher.call();
      final fromHub = refresher.call();
      await Future<void>.delayed(Duration.zero);
      gate.complete(_session('new-token'));

      expect(await Future.wait([fromRest, fromHub]), ['new-token', 'new-token']);
      expect(repository.loginCalls, 1);
    });
  });

  group('REST: the real interceptor chain', () {
    test('a 401 recovers through the fallback login and is retried once with '
        'the new token', () async {
      final prefs = await prefsWith(expiredSession);
      final chain = _restChain(
        prefs,
        _Adapter((options) async {
          if (options.path == ApiEndpoints.login) {
            return (200, _loginEnvelope('new-token'));
          }
          return options.headers['Authorization'] == 'Bearer new-token'
              ? (200, <String, dynamic>{'ok': true})
              : (401, <String, dynamic>{});
        }),
      );

      final response = await chain.client.get<Map<String, dynamic>>(_protected);

      expect(response.statusCode, 200);
      expect(chain.adapter.seen.map((s) => s.path).toList(),
          [_protected, ApiEndpoints.login, _protected]);
      expect(chain.adapter.seen.last.authorization, 'Bearer new-token');
      expect(chain.adapter.seen[1].data, {
        'userName': '',
        'password': '',
        'socialMediaId': _socialMediaId,
      });
      expect(prefs.getToken(), 'new-token');
    });

    test('a 401 on the fallback login itself cannot wait on its own refresh',
        () async {
      final prefs = await prefsWith(expiredSession);
      final chain = _restChain(
        prefs,
        _Adapter((options) async => (401, <String, dynamic>{})),
      );

      await expectLater(
        chain.client
            .get<Map<String, dynamic>>(_protected)
            .timeout(const Duration(seconds: 5)),
        throwsA(
          isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 401),
        ),
      );
      expect(chain.adapter.count(ApiEndpoints.login), 1);
      expect(chain.adapter.count(_protected), 1, reason: 'no retry, no loop');
      expect(prefs.getToken(), isNull, reason: 'the existing failure path');
    });
  });

  group('SignalR', () {
    test('the upgrade 401 recovers through the fallback login and is retried '
        'with the new token', () async {
      final prefs = await prefsWith(expiredSession);
      final repository = _FakeAuthRepository();
      final refresher =
          AuthTokenRefresher(repository: repository, prefs: prefs);
      final server = _HubServer('new-token');
      final client = SignalRHttpClient(
        headersBuilder: ApiHeadersBuilder(prefs),
        tokenProvider: () async => prefs.getToken() ?? '',
        obtainRefreshedAccessToken: refresher.call,
        inner: server,
      );

      final response = await client.send(_upgradeRequest(_url));

      expect(response.statusCode, 101);
      expect(server.authorizations, ['Bearer expired', 'Bearer new-token']);
      expect(repository.loginCalls, 1);
    });

    test('an expired token connects after recovery: one recovery, one '
        'CheckPlayerGame, one JoinRandomGame', () async {
      final prefs = await prefsWith(expiredSession);
      final h = _hubHarness(prefs);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(h.service),
        ],
      );
      addTearDown(h.service.dispose);
      addTearDown(container.dispose);
      final session = container.listen(gameControllerProvider, (_, __) {});
      addTearDown(session.close);
      var announced = 0;
      final recovered = h.service.recoveredStream.listen((_) => announced++);
      addTearDown(recovered.cancel);

      final controller = container.read(gameControllerProvider.notifier);
      controller.enterWaiting();
      await controller.onWaitingShown();
      expect(h.count(PlayGameHubEvents.joinRandomGame), 0,
          reason: 'sanity: the join waits for a connected hub');

      await h.service.connect(
        url: _url,
        accessTokenFactory: () async => prefs.getToken() ?? '',
      );
      await pumpEventQueue();

      expect(h.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(h.server.authorizations, ['Bearer expired', 'Bearer new-token']);
      expect(h.repository.loginCalls, 1);
      expect(h.hubs, hasLength(1));
      expect(announced, 1);
      expect(h.count(PlayGameHubEvents.checkPlayerGame), 1);
      expect(h.count(PlayGameHubEvents.joinRandomGame), 1);
    });

    test('FAILED with no way to get a token does not retry endlessly', () async {
      final prefs = await prefsWith({'auth_token': 'expired'});
      final h = _hubHarness(prefs);
      addTearDown(h.service.dispose);

      fakeAsync((async) {
        unawaited(
          h.service.connect(
            url: _url,
            accessTokenFactory: () async => prefs.getToken() ?? '',
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 10));

        expect(h.service.checkConnectionStatus(), SignalRStatus.failed);
        expect(h.hubs, hasLength(1),
            reason: 'the one backoff retry met an empty token and stopped');
        expect(h.server.authorizations, ['Bearer expired']);
        expect(h.repository.loginCalls, 0);
      });
    });

    test('FAILED recovers once the host supplies a token', () async {
      final prefs = await prefsWith({'app_language': AppLanguage.english});
      final h = _hubHarness(prefs);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(h.service),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        ],
      );
      addTearDown(h.service.dispose);
      addTearDown(container.dispose);
      final session = container.listen(gameControllerProvider, (_, __) {});
      addTearDown(session.close);
      var announced = 0;
      final recovered = h.service.recoveredStream.listen((_) => announced++);
      addTearDown(recovered.cancel);
      final engine = GameEngine(container: container);
      addTearDown(engine.dispose);

      await engine.initialize(const GameEngineConfig(token: ''));
      await engine.connectHub();
      expect(h.service.checkConnectionStatus(), SignalRStatus.failed,
          reason: 'sanity: no token, no connection');

      await engine.updateConfig(const GameEngineConfig(token: 'new-token'));
      await pumpEventQueue();

      expect(h.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(h.server.authorizations, ['Bearer new-token']);
      expect(announced, 1);
      expect(h.count(PlayGameHubEvents.checkPlayerGame), 1);
    });

    test('a config without a token leaves a failed hub alone', () async {
      final prefs = await prefsWith({'app_language': AppLanguage.english});
      final h = _hubHarness(prefs);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(h.service),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        ],
      );
      addTearDown(h.service.dispose);
      addTearDown(container.dispose);
      final engine = GameEngine(container: container);
      addTearDown(engine.dispose);

      await engine.initialize(const GameEngineConfig(token: ''));
      await engine.connectHub();
      await engine.updateConfig(const GameEngineConfig(token: ''));
      await pumpEventQueue();

      expect(h.service.checkConnectionStatus(), SignalRStatus.failed);
      expect(h.hubs, isEmpty);
    });

    test('simultaneous REST and SignalR 401s log in once', () async {
      final prefs = await prefsWith(expiredSession);
      final gate = Completer<void>();
      final chain = _restChain(
        prefs,
        _Adapter((options) async {
          if (options.path == ApiEndpoints.login) {
            await gate.future;
            return (200, _loginEnvelope('new-token'));
          }
          return options.headers['Authorization'] == 'Bearer new-token'
              ? (200, <String, dynamic>{'ok': true})
              : (401, <String, dynamic>{});
        }),
      );
      final server = _HubServer('new-token');
      final hubClient = SignalRHttpClient(
        headersBuilder: ApiHeadersBuilder(prefs),
        tokenProvider: () async => prefs.getToken() ?? '',
        obtainRefreshedAccessToken: chain.refresher.call,
        inner: server,
      );

      final rest = chain.client.get<Map<String, dynamic>>(_protected);
      final hub = hubClient.send(_upgradeRequest(_url));
      await pumpEventQueue();
      gate.complete();

      expect((await rest).statusCode, 200);
      expect((await hub).statusCode, 101);
      expect(chain.adapter.count(ApiEndpoints.login), 1);
      expect(server.authorizations.last, 'Bearer new-token');
    });
  });

  group('Engine and game entry', () {
    late _Hub h;
    late GameEngine engine;
    late ProviderContainer container;

    Future<void> pumpEngine(WidgetTester tester) async {
      final prefs = await prefsWith({'app_language': AppLanguage.english});
      h = _hubHarness(prefs);
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(h.service),
          stickersRepositoryProvider
              .overrideWithValue(_FakeStickersRepository()),
          audioServiceProvider.overrideWithValue(_FakeAudioService()),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
          hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
      );
      addTearDown(h.service.dispose);
      addTearDown(container.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      engine = GameEngine(
        container: container,
        host: PlayGameEngineHost(
          navigatorKey: navigatorKey,
          container: container,
        ),
      );
      addTearDown(engine.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('host')),
          ),
        ),
      );
      await tester.pump();
      await engine.initialize(_expiredConfig);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('initialize with an expired token + socialMediaId, then '
        'connectHub: recovered and connected', (tester) async {
      await pumpEngine(tester);

      await engine.connectHub();

      expect(h.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(engine.connectionState, GameEngineConnectionState.connected);
      expect(h.repository.loginCalls, 1);
      expect(h.server.authorizations, ['Bearer expired', 'Bearer new-token']);
      expect(h.prefs.getToken(), 'new-token');
      expect(h.prefs.getSocialMediaId(), _socialMediaId);
      expect(h.prefs.getUserId(), 47);
    });

    testWidgets('Random Game starts after the recovery', (tester) async {
      await pumpEngine(tester);

      final entry = engine.joinRandomGame();
      await settle(tester);
      await entry;

      expect(h.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(h.repository.loginCalls, 1);
      expect(h.count(PlayGameHubEvents.checkPlayerGame), 1);
      expect(h.count(PlayGameHubEvents.joinRandomGame), 1);
    });

    testWidgets('Create Private starts after the recovery', (tester) async {
      await pumpEngine(tester);

      final entry = engine.createPrivateGame(const [7]);
      await settle(tester);
      await entry;

      expect(h.repository.loginCalls, 1);
      expect(h.count(PlayGameHubEvents.createPrivateGame), 1);
      expect(h.count(PlayGameHubEvents.joinRandomGame), 0);
    });

    testWidgets('Join Private starts after the recovery, without duplicate '
        'entry commands', (tester) async {
      await pumpEngine(tester);

      final entry = engine.joinPrivateGame('ABC123');
      await settle(tester);
      await entry;

      expect(h.repository.loginCalls, 1);
      expect(h.count(PlayGameHubEvents.joinPrivateGame), 1);
      expect(h.count(PlayGameHubEvents.createPrivateGame), 0);
      expect(h.count(PlayGameHubEvents.joinRandomGame), 0);
    });
  });
}

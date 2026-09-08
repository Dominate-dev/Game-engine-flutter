import 'package:coreapp/coreapp.dart';
import 'package:coreapp/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/features/games/data/datasources/game_remote_datasource.dart';
import 'package:play_game/features/profile/data/datasources/profile_remote_datasource.dart';
import 'package:play_game/features/stickers/data/datasources/stickers_remote_datasource.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// T-COV — the remote datasources had no tests at all.
// (Originally four; GamesRemoteDataSourceImpl was deleted under M3 — the
// exitFromAllGames slice had no callers anywhere in the app.)
//
// The seam is the one already used for the other concrete network class: a
// test-local subclass. Every datasource takes its ApiClient by constructor, so
// overriding get/post/put/delete intercepts the call before Dio is reached —
// no interface and no production change is needed.
//
// What this seam can and cannot see: the method, path, query and body are all
// observable, because they are ApiClient's own parameters. Headers are NOT —
// they are applied by AppBaseInterceptor inside Dio, below the override, so
// nothing here asserts on them.

class _Call {
  const _Call(
    this.method,
    this.path, {
    this.query,
    this.data,
    this.authTokenOverride,
    this.isAuthRefreshCall = false,
  });

  final String method;
  final String path;
  final Map<String, dynamic>? query;
  final dynamic data;
  final String? authTokenOverride;
  final bool isAuthRefreshCall;
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(ApiHeadersBuilder headersBuilder)
      : super(
          // Deliberately unroutable — a call that escaped the override would
          // fail rather than reach a real backend.
          baseUrl: 'http://127.0.0.1:9/never-used',
          // Both default to kDebugMode, which is TRUE under flutter test.
          enableChucker: false,
          enableLogging: false,
          headersBuilder: headersBuilder,
        );

  final calls = <_Call>[];

  /// The decoded envelope the next call returns.
  Object? body;
  int statusCode = 200;

  /// When set, the next call throws this instead of answering.
  Object? failure;

  _Call get lastCall => calls.last;

  Future<Response<T>> _record<T>(_Call call) async {
    calls.add(call);
    final thrown = failure;
    if (thrown != null) {
      throw thrown;
    }
    return Response<T>(
      requestOptions: RequestOptions(path: call.path),
      statusCode: statusCode,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    String? authTokenOverride,
    bool isAuthRefreshCall = false,
  }) =>
      _record<T>(_Call(
        'GET',
        path,
        query: query,
        authTokenOverride: authTokenOverride,
        isAuthRefreshCall: isAuthRefreshCall,
      ));

  @override
  Future<Response<T>> post<T>(String path, {dynamic data}) =>
      _record<T>(_Call('POST', path, data: data));

  @override
  Future<Response<T>> put<T>(String path, {dynamic data}) =>
      _record<T>(_Call('PUT', path, data: data));

  @override
  Future<Response<T>> delete<T>(String path, {dynamic data}) =>
      _record<T>(_Call('DELETE', path, data: data));
}

Map<String, dynamic> _envelope({
  bool succeeded = true,
  Object? data,
  int? fullCount,
  String? message,
  Map<String, dynamic>? error,
  Map<String, dynamic> extra = const {},
}) =>
    <String, dynamic>{
      'succeeded': succeeded,
      'data': data,
      if (fullCount != null) 'fullCount': fullCount,
      if (message != null) 'message': message,
      if (error != null) 'error': error,
      ...extra,
    };

void main() {
  late _FakeApiClient client;

  setUp(() async {
    AppStrings.setLanguage(AppLanguage.english);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPrefsService.init();
    client = _FakeApiClient(ApiHeadersBuilder(prefs));
  });

  tearDown(() => AppStrings.setLanguage(AppLanguage.english));

  group('the test seam', () {
    test('a datasource call is intercepted, never dispatched', () async {
      client.body = _envelope(data: {'id': 1, 'name': 'x'});

      await ProfileRemoteDataSourceImpl(client).getPublicProfile(1);

      // Reaching Dio would mean an attempted connection to 127.0.0.1:9.
      expect(client.calls, hasLength(1));
      expect(client.lastCall.method, 'POST');
    });

    test('each datasource call is recorded once, in order', () async {
      client.body = _envelope(data: {'id': 1, 'name': 'x'});
      await ProfileRemoteDataSourceImpl(client).getPublicProfile(1);
      client.body = _envelope(data: <Object?>[]);
      await StickersRemoteDataSourceImpl(client)
          .getStickerGroups(const StickerFilterParams());

      expect(client.calls.map((c) => c.method).toList(), ['POST', 'POST']);
    });
  });

  group('AuthRemoteDataSourceImpl.login', () {
    late AuthRemoteDataSource dataSource;

    setUp(() => dataSource = AuthRemoteDataSourceImpl(client));

    test('posts the credentials to the login endpoint', () async {
      client.body = _envelope(data: {'token': 't'});

      await dataSource.login(
        const LoginParams(
          userName: 'me',
          password: 'pw',
          socialMediaId: 'sm',
        ),
      );

      expect(client.lastCall.method, 'POST');
      expect(client.lastCall.path, ApiEndpoints.login);
      expect(client.lastCall.data, {
        'userName': 'me',
        'password': 'pw',
        'socialMediaId': 'sm',
      });
      expect(client.lastCall.query, isNull);
    });

    test('sends an empty socialMediaId when the caller omits it', () async {
      client.body = _envelope(data: {'token': 't'});

      await dataSource
          .login(const LoginParams(userName: 'me', password: 'pw'));

      expect((client.lastCall.data as Map)['socialMediaId'], '');
    });

    test('returns the session carried in the envelope data', () async {
      client.body = _envelope(
        data: {'token': 'tok', 'refreshToken': 'ref', 'userId': 47},
      );

      final session = await dataSource
          .login(const LoginParams(userName: 'me', password: 'pw'));

      expect(session.token, 'tok');
      expect(session.refreshToken, 'ref');
      expect(session.userId, '47');
    });

    test('falls back to a root-level token when data is absent', () async {
      client.body = _envelope(
        extra: {'token': 'root', 'refreshToken': 'rr', 'id': 9},
      );

      final session = await dataSource
          .login(const LoginParams(userName: 'me', password: 'pw'));

      expect(session.token, 'root');
      expect(session.refreshToken, 'rr');
      expect(session.userId, '9');
    });

    test('accepts a bare string token as the envelope data', () async {
      client.body = _envelope(data: 'plain-token');

      final session = await dataSource
          .login(const LoginParams(userName: 'me', password: 'pw'));

      expect(session.token, 'plain-token');
      expect(session.refreshToken, isNull);
    });

    test('throws ApiException when the envelope reports failure', () async {
      client.body = _envelope(
        succeeded: false,
        error: {'message': 'Bad credentials', 'code': 401},
      );

      await expectLater(
        dataSource.login(const LoginParams(userName: 'me', password: 'pw')),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Bad credentials')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws when a successful envelope carries no token', () async {
      client.body = _envelope(data: {'refreshToken': 'ref'});

      await expectLater(
        dataSource.login(const LoginParams(userName: 'me', password: 'pw')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            AppStrings.current.loginMissingToken,
          ),
        ),
      );
    });

    test('does not swallow a transport failure', () async {
      client.failure = DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.login),
        message: 'connection refused',
      );

      await expectLater(
        dataSource.login(const LoginParams(userName: 'me', password: 'pw')),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('AuthRemoteDataSourceImpl.refresh (N2)', () {
    late AuthRemoteDataSource dataSource;

    setUp(() => dataSource = AuthRemoteDataSourceImpl(client));

    test('gets the refresh endpoint, authenticated with the refresh token',
        () async {
      client.body = _envelope(data: {'token': 'new-tok'});

      await dataSource.refresh('the-refresh-token');

      expect(client.lastCall.method, 'GET');
      expect(client.lastCall.path, ApiEndpoints.refreshToken);
      expect(client.lastCall.authTokenOverride, 'the-refresh-token');
      expect(client.lastCall.isAuthRefreshCall, isTrue);
    });

    test('returns the session carried in the envelope, same as login',
        () async {
      client.body = _envelope(
        data: {'token': 'new-tok', 'refreshToken': 'new-ref', 'userId': 47},
      );

      final session = await dataSource.refresh('old-refresh-token');

      expect(session.token, 'new-tok');
      expect(session.refreshToken, 'new-ref');
      expect(session.userId, '47');
    });

    test('throws ApiException when the envelope reports failure', () async {
      client.body = _envelope(
        succeeded: false,
        error: {'message': 'Refresh token expired', 'code': 401},
      );

      await expectLater(
        dataSource.refresh('expired-refresh-token'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Refresh token expired')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws when a successful envelope carries no token', () async {
      client.body = _envelope();

      await expectLater(
        dataSource.refresh('the-refresh-token'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ProfileRemoteDataSourceImpl.getPublicProfile', () {
    late ProfileRemoteDataSource dataSource;

    setUp(() => dataSource = ProfileRemoteDataSourceImpl(client));

    test('posts the public-profile endpoint for the id', () async {
      client.body = _envelope(data: {'id': 47});

      await dataSource.getPublicProfile(47);

      // The route is POST-only: a GET is answered `405 Method Not Allowed`
      // with `Allow: POST`, on both the v2 and test backends.
      expect(client.lastCall.method, 'POST');
      expect(client.lastCall.path, '/api/Users/PublicPorfile/47');
      expect(client.lastCall.path, PlayGameEndpoints.publicProfile(47));
      expect(client.lastCall.query, isNull);
      expect(client.lastCall.data, isNull, reason: 'the id is in the path');
    });

    test('maps the envelope data into a UserProfile', () async {
      client.body = _envelope(
        data: {
          'id': 47,
          'name': 'Hassan',
          'image': 'a.png',
          'cover': 'b.png',
          'level': 3,
          'levelName': 'Pro',
          'xp': 120,
          'coins': 50,
          'diamonds': 5,
          'categories': [
            {'id': 1, 'name': 'Sports', 'path': 'c.png', 'isActive': true},
          ],
        },
      );

      final profile = await dataSource.getPublicProfile(47);

      expect(profile.id, 47);
      expect(profile.name, 'Hassan');
      expect(profile.imagePath, 'a.png');
      expect(profile.coverPath, 'b.png');
      expect(profile.level, 3);
      expect(profile.levelTitle, 'Pro');
      expect(profile.xp, 120);
      expect(profile.coins, 50);
      expect(profile.diamonds, 5);
      expect(profile.categories, hasLength(1));
      expect(profile.categories.single.name, 'Sports');
      expect(profile.categories.single.isActive, isTrue);
    });

    test('reads the alternate key spellings the backend also sends', () async {
      client.body = _envelope(
        data: {
          'userId': '9',
          'userName': 'Alt',
          'profileImage': 'p.png',
          'levelNumber': 2,
          'points': 30,
          'gold': 7,
          'jawaher': 4,
        },
      );

      final profile = await dataSource.getPublicProfile(9);

      expect(profile.id, 9);
      expect(profile.name, 'Alt');
      expect(profile.imagePath, 'p.png');
      expect(profile.level, 2);
      expect(profile.xp, 30);
      expect(profile.coins, 7);
      expect(profile.diamonds, 4);
    });

    test('yields an empty profile when the envelope carries no data', () async {
      client.body = _envelope();

      final profile = await dataSource.getPublicProfile(1);

      expect(profile.id, 0);
      expect(profile.name, '');
      expect(profile.categories, isEmpty);
    });

    test('throws ApiException when the envelope reports failure', () async {
      client.body = _envelope(
        succeeded: false,
        error: {'message': 'No such user', 'code': 404},
      );

      await expectLater(
        dataSource.getPublicProfile(1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'No such user')
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('GameRemoteDataSourceImpl.generateUrl', () {
    late GameRemoteDataSource dataSource;

    setUp(() => dataSource = GameRemoteDataSourceImpl(client));

    test('gets api/Home/GenerateURL with exactly type and code', () async {
      client.body = _envelope(data: 'https://example.test/g/4821');

      await dataSource.generateUrl(type: 2, code: '4821');

      expect(client.lastCall.method, 'GET');
      expect(client.lastCall.path, PlayGameEndpoints.generateUrl);
      expect(client.lastCall.path, '/api/Home/GenerateURL');
      expect(client.lastCall.query, {'type': 2, 'code': '4821'});
      expect(client.lastCall.query, hasLength(2),
          reason: 'no extra query parameter is invented');
    });

    test('unwraps the scalar String envelope', () async {
      client.body = _envelope(data: 'https://example.test/g/4821');

      final url = await dataSource.generateUrl(type: 2, code: '4821');

      expect(url, 'https://example.test/g/4821');
    });

    test('passes the code through verbatim', () async {
      client.body = _envelope(data: 'x');

      await dataSource.generateUrl(type: 2, code: 'AB-99');

      expect(client.lastCall.query?['code'], 'AB-99');
    });

    test('a failed envelope raises the standard ApiException', () async {
      client.body = _envelope(
        succeeded: false,
        error: {'message': 'Game not found', 'code': 404},
      );

      await expectLater(
        dataSource.generateUrl(type: 2, code: '4821'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Game not found')
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('StickersRemoteDataSourceImpl.getStickerGroups', () {
    late StickersRemoteDataSource dataSource;

    setUp(() => dataSource = StickersRemoteDataSourceImpl(client));

    test('posts the filter body to the sticker-groups endpoint', () async {
      client.body = _envelope(data: <Object?>[]);

      await dataSource.getStickerGroups(
        const StickerFilterParams(canUse: true, pageIndex: 2, pageSize: 30),
      );

      expect(client.lastCall.method, 'POST');
      expect(client.lastCall.path, PlayGameEndpoints.stickerGroupsFilter);
      expect(client.lastCall.data, {
        'data': {'canUse': true},
        'pageIndex': 2,
        'pageSize': 30,
      });
    });

    test('maps a list payload into a page that echoes the request', () async {
      client.body = _envelope(
        fullCount: 41,
        data: [
          {
            'id': 1,
            'name': 'Pack',
            'path': 's.png',
            'price': 10,
            'isActive': true,
            'type': 2,
            'isUserOrderAssetss': true,
            'canUse': true,
            'assetss': [
              {'id': 11, 'name': 'One', 'path': 'o.png'},
            ],
          },
        ],
      );

      final page = await dataSource.getStickerGroups(
        const StickerFilterParams(pageIndex: 1, pageSize: 20),
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.id, 1);
      expect(page.items.single.name, 'Pack');
      expect(page.items.single.price, 10);
      expect(page.items.single.isUserOrderAssets, isTrue);
      expect(page.items.single.assets.single.id, 11);
      expect(page.pageIndex, 1, reason: 'echoed from the request');
      expect(page.pageSize, 20, reason: 'echoed from the request');
      expect(page.fullCount, 41, reason: 'carried from the envelope');
    });

    test('returns an empty page when data is not a list', () async {
      client.body = _envelope(data: {'unexpected': true});

      final page = await dataSource
          .getStickerGroups(const StickerFilterParams(pageIndex: 3));

      expect(page.items, isEmpty);
      expect(page.pageIndex, 3);
      expect(page.fullCount, isNull);
    });

    test('throws ApiException when the envelope reports failure', () async {
      client.body = _envelope(succeeded: false, message: 'Filter rejected');

      await expectLater(
        dataSource.getStickerGroups(const StickerFilterParams()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Filter rejected'),
        ),
      );
    });
  });

  group('StickersRemoteDataSourceImpl.payStickerGroup', () {
    late StickersRemoteDataSource dataSource;

    setUp(() => dataSource = StickersRemoteDataSourceImpl(client));

    test('gets the pay endpoint for the id', () async {
      client.body = _envelope(data: true);

      await dataSource.payStickerGroup(8);

      expect(client.lastCall.method, 'GET');
      expect(client.lastCall.path, '/api/Assetss/StickersGroups/8/Pay');
      expect(client.lastCall.path, PlayGameEndpoints.payStickerGroup(8));
      expect(client.lastCall.query, isNull);
    });

    test('completes without a value on success', () async {
      client.body = _envelope();

      await expectLater(dataSource.payStickerGroup(8), completes);
    });

    test('throws ApiException when the envelope reports failure', () async {
      client.body = _envelope(
        succeeded: false,
        error: {'message': 'Not enough coins', 'code': 402},
      );

      await expectLater(
        dataSource.payStickerGroup(8),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Not enough coins')
              .having((e) => e.statusCode, 'statusCode', 402),
        ),
      );
    });
  });
}

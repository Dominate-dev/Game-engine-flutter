import 'package:coreapp/coreapp.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// T-COV — BaseRepository.guard.
//
// Every repository call in the app goes through this one method, and it is
// the only place a thrown exception becomes a typed Failure. The registry
// recorded it as *partly* covered: `failure_message_test.dart` drives the
// final catch-all, which leaves the ApiException, NoInternetException and
// DioException arms — and every DioExceptionType — unexercised.
//
// Pure logic with no backend: `guard` takes a callback, so every branch is
// reachable by throwing the exception the real Dio/ApiClient layer would
// throw. Nothing here invents a backend contract; the exception types and
// their fields are the repository's own.

/// The mixin has no standalone implementation, so tests need a host — the
/// same one `failure_message_test.dart` already uses.
class _Repo with BaseRepository {
  Future<Result<T>> run<T>(Future<T> Function() action) => guard(action);
}

/// Fails a `Result` open: returns the failure, or fails the test with the
/// success value rather than throwing an opaque cast error.
Failure failureOf<T>(Result<T> result) => result.when(
      success: (value) {
        fail('expected a failure, got success: $value');
      },
      failure: (failure) => failure,
    );

DioException _dio(
  DioExceptionType type, {
  Response<dynamic>? response,
  Object? error,
  String? message,
}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: response,
      error: error,
      message: message,
    );

Response<dynamic> _response(dynamic data, {int? statusCode}) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/x'),
      data: data,
      statusCode: statusCode,
    );

void main() {
  late _Repo repo;

  setUp(() {
    AppStrings.setLanguage(AppLanguage.english);
    repo = _Repo();
  });

  group('the success path', () {
    test('a value is carried through as a success', () async {
      final result = await repo.run<int>(() async => 42);
      expect(result.when(success: (v) => v, failure: (_) => -1), 42);
    });

    test('a null value is still a success, not a failure', () async {
      final result = await repo.run<String?>(() async => null);
      expect(
        result.when(success: (v) => 'success:$v', failure: (f) => 'failure'),
        'success:null',
      );
    });
  });

  group('ApiException maps by status code', () {
    test('401 becomes UnauthorizedFailure and keeps its message', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw const ApiException(
            message: 'token expired',
            statusCode: 401,
          ),
        ),
      );

      expect(failure, isA<UnauthorizedFailure>());
      expect(failure.message, 'token expired');
    });

    test('any other status becomes ServerFailure, carrying the code',
        () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw const ApiException(
            message: 'boom',
            statusCode: 500,
          ),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'boom');
      expect(failure.statusCode, 500);
    });

    test('a null status code is a ServerFailure, not an Unauthorized one',
        () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw const ApiException(message: 'no code'),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.statusCode, isNull);
    });
  });

  group('NoInternetException', () {
    test('thrown directly, becomes NoInternetFailure', () async {
      final failure = failureOf(
        await repo.run<void>(() async => throw const NoInternetException()),
      );
      expect(failure, isA<NoInternetFailure>());
    });

    test('wrapped inside a DioException, still NoInternetFailure', () async {
      // The ApiClient wraps its connectivity guard this way, so this arm is
      // reached in production before the type switch below ever runs.
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            error: const NoInternetException(),
          ),
        ),
      );
      expect(
        failure,
        isA<NoInternetFailure>(),
        reason: 'the wrapped cause wins over the DioExceptionType',
      );
    });
  });

  group('DioException maps by type', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
    ]) {
      test('$type becomes TimeoutFailure', () async {
        final failure = failureOf(await repo.run<void>(() async => throw _dio(type)));
        expect(failure, isA<TimeoutFailure>());
      });
    }

    test('connectionError becomes NoInternetFailure', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(DioExceptionType.connectionError),
        ),
      );
      expect(failure, isA<NoInternetFailure>());
    });

    for (final type in [
      DioExceptionType.cancel,
      DioExceptionType.badCertificate,
      DioExceptionType.unknown,
    ]) {
      test('$type becomes UnknownFailure carrying the Dio message', () async {
        final failure = failureOf(
          await repo.run<void>(
            () async => throw _dio(type, message: 'dio said no'),
          ),
        );
        expect(failure, isA<UnknownFailure>());
        expect(failure.message, 'dio said no');
      });
    }

    test('an unknown type with no message falls back to the localized '
        'unknown-error string', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(DioExceptionType.unknown),
        ),
      );
      expect(failure.message, AppStrings.current.unknownError);
    });
  });

  group('DioException badResponse reads the API envelope', () {
    test('an unsuccessful envelope is mapped through ApiException, so a 401 '
        'in the body becomes UnauthorizedFailure', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response(
              {
                'succeeded': false,
                'error': {'code': 401, 'message': 'session gone'},
              },
              statusCode: 500,
            ),
          ),
        ),
      );

      expect(
        failure,
        isA<UnauthorizedFailure>(),
        reason: "the envelope's own statusCode wins over the HTTP one",
      );
      expect(failure.message, 'session gone');
    });

    test('an unsuccessful envelope with a non-401 code becomes ServerFailure',
        () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response(
              {
                'succeeded': false,
                'error': {'code': 400, 'message': 'bad request'},
              },
            ),
          ),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'bad request');
      expect(failure.statusCode, 400);
    });

    test('an envelope with no statusCode falls back to the HTTP status',
        () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response(
              {'succeeded': false, 'message': 'nope'},
              statusCode: 403,
            ),
          ),
        ),
      );

      expect(failure.statusCode, 403);
    });

    test('a *successful* envelope skips the ApiException mapping and falls '
        'through to the status/message handling', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response(
              {'succeeded': true, 'message': 'odd but successful'},
              statusCode: 500,
            ),
          ),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'odd but successful');
      expect(failure.statusCode, 500);
    });

    test('a bare 401 with no envelope becomes UnauthorizedFailure', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response('not a map', statusCode: 401),
          ),
        ),
      );

      expect(failure, isA<UnauthorizedFailure>());
    });

    test('a non-map body falls back to the localized short server error',
        () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response('<html>500</html>', statusCode: 502),
          ),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.message, AppStrings.current.serverErrorShort);
      expect(failure.statusCode, 502);
    });

    test('a null response falls back the same way', () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(DioExceptionType.badResponse),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.message, AppStrings.current.serverErrorShort);
      expect(failure.statusCode, isNull);
    });

    test('a map body with no envelope keys still yields its message',
        () async {
      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response({'message': 'plain message'}, statusCode: 500),
          ),
        ),
      );

      expect(failure.message, 'plain message');
    });
  });

  group('the catch-all', () {
    test('an arbitrary error becomes UnknownFailure carrying its cause',
        () async {
      final failure = failureOf(
        await repo.run<void>(() async => throw StateError('unexpected')),
      );

      expect(failure, isA<UnknownFailure>());
      expect(failure.cause, contains('unexpected'));
    });

    test('a synchronous throw inside the callback is caught too', () async {
      final failure = failureOf(
        await repo.run<void>(() => throw ArgumentError('sync')),
      );
      expect(failure, isA<UnknownFailure>());
    });
  });

  group('localization is read at failure time, not at import time', () {
    test('the Arabic fallback message is used when Arabic is set', () async {
      AppStrings.setLanguage(AppLanguage.arabic);
      final arabic = AppStrings.current.serverErrorShort;

      final failure = failureOf(
        await repo.run<void>(
          () async => throw _dio(
            DioExceptionType.badResponse,
            response: _response('not a map', statusCode: 500),
          ),
        ),
      );

      expect(failure.message, arabic);
      AppStrings.setLanguage(AppLanguage.english);
      expect(
        arabic,
        isNot(AppStrings.current.serverErrorShort),
        reason: 'sanity — the two locales differ, so the check above is real',
      );
    });
  });
}

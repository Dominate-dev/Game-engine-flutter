import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// E2 — a raw exception must never reach Failure.message, which is what the
// error dialog renders. The raw text stays available to logging as `cause`.

const _typeError =
    "type 'Null' is not a subtype of type 'String' in type cast";

void main() {
  setUp(() => AppStrings.setLanguage(AppLanguage.english));
  tearDown(() => AppStrings.setLanguage(AppLanguage.english));

  group('UnknownFailure user-facing message', () {
    test('defaults to the localized unknownError in English', () {
      expect(UnknownFailure().message, AppStrings.current.unknownError);
      expect(UnknownFailure().message, 'An unknown error occurred');
    });

    test('defaults to the localized unknownError in Arabic', () {
      AppStrings.setLanguage(AppLanguage.arabic);
      expect(UnknownFailure().message, AppStrings.current.unknownError);
      expect(UnknownFailure().message, 'حدث خطأ غير معروف');
    });

    test('a raw exception passed as cause never becomes the message', () {
      final failure = UnknownFailure(cause: _typeError);
      expect(failure.message, 'An unknown error occurred');
      expect(failure.message, isNot(contains('type ')));
      expect(failure.message, isNot(contains('subtype')));
    });

    test('the same holds in Arabic', () {
      AppStrings.setLanguage(AppLanguage.arabic);
      final failure = UnknownFailure(cause: _typeError);
      expect(failure.message, 'حدث خطأ غير معروف');
      expect(failure.message, isNot(contains('subtype')));
    });
  });

  group('diagnostics are preserved separately', () {
    test('cause carries the raw exception verbatim', () {
      expect(UnknownFailure(cause: _typeError).cause, _typeError);
    });

    test('cause is null when none was supplied', () {
      expect(UnknownFailure().cause, isNull);
      expect(NoInternetFailure().cause, isNull);
      expect(ServerFailure().cause, isNull);
      expect(TimeoutFailure().cause, isNull);
      expect(UnauthorizedFailure().cause, isNull);
    });

    test('message and cause are independent', () {
      final failure = UnknownFailure(cause: _typeError);
      expect(failure.cause, isNot(failure.message));
    });
  });

  group('existing Failure API is preserved', () {
    test('an explicit message still wins, for deliberate copy', () {
      expect(UnknownFailure(message: 'Hub connect failed').message,
          'Hub connect failed');
    });

    test('the other subclasses keep their localized defaults', () {
      expect(NoInternetFailure().message, AppStrings.current.noInternet);
      expect(ServerFailure().message, AppStrings.current.serverError);
      expect(TimeoutFailure().message, AppStrings.current.requestTimedOut);
      expect(UnauthorizedFailure().message, AppStrings.current.unauthorized);
    });

    test('statusCode still flows through', () {
      expect(UnauthorizedFailure().statusCode, 401);
      expect(ServerFailure(statusCode: 500).statusCode, 500);
      expect(UnknownFailure(cause: _typeError, statusCode: 418).statusCode, 418);
    });
  });

  // Exercises the catch-all in BaseRepository.guard itself, which is the site
  // that used to put e.toString() into the user-facing message.
  group('BaseRepository.guard catch-all', () {
    final repo = _Repo();

    test('an unexpected exception yields the localized message', () async {
      final result = await repo.run<String>(() => throw TypeError());
      final failure = result.failureOrNull!;

      expect(failure.message, AppStrings.current.unknownError);
      expect(failure.message, isNot(contains('TypeError')));
      expect(failure.message, isNot(contains('subtype')));
    });

    test('the raw exception is kept as cause for logging', () async {
      final result =
          await repo.run<String>(() => throw StateError('boom detail'));
      final failure = result.failureOrNull!;

      expect(failure.cause, isNotNull);
      expect(failure.cause, contains('boom detail'));
      expect(failure.message, isNot(contains('boom detail')));
    });

    test('a successful action is unaffected', () async {
      final result = await repo.run<String>(() async => 'ok');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'ok');
    });
  });
}

class _Repo with BaseRepository {
  Future<Result<T>> run<T>(Future<T> Function() action) => guard(action);
}

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// T-COV — ApiResponse is the envelope every API result passes through, and
// had no tests.
//
// Only behaviour the implementation clearly intends is asserted here. Three
// edges are deliberately NOT pinned because nothing in the repository shows
// they were considered; they are reported instead:
//   - the envelope's own keys are read raw, so they are case-sensitive while
//     the rest of the codebase reads JSON through JsonValue's tolerant lookup;
//   - `succeeded` accepts only a real `true`, not JsonValue's bool coercion;
//   - with no `fromJsonT`, `data` is an unchecked `as T?` cast.

void main() {
  setUp(() => AppStrings.setLanguage(AppLanguage.english));
  tearDown(() => AppStrings.setLanguage(AppLanguage.english));

  group('succeeded', () {
    test('is true only for a real true', () {
      expect(ApiResponse<void>.fromJson({'succeeded': true}).succeeded, isTrue);
    });

    test('is false for false, null and a missing key', () {
      expect(
        ApiResponse<void>.fromJson({'succeeded': false}).succeeded,
        isFalse,
      );
      expect(
        ApiResponse<void>.fromJson({'succeeded': null}).succeeded,
        isFalse,
      );
      expect(
        ApiResponse<void>.fromJson(<String, dynamic>{}).succeeded,
        isFalse,
      );
    });
  });

  group('data', () {
    test('is mapped through fromJsonT when one is given', () {
      final response = ApiResponse<int>.fromJson(
        {'data': '47'},
        fromJsonT: (raw) => int.parse(raw! as String),
      );
      expect(response.data, 47);
    });

    test('fromJsonT receives the raw value untouched', () {
      Object? seen;
      ApiResponse<String>.fromJson(
        {'data': <String, dynamic>{'id': 1}},
        fromJsonT: (raw) {
          seen = raw;
          return 'ok';
        },
      );
      expect(seen, <String, dynamic>{'id': 1});
    });

    test('a null data is null and fromJsonT is not called', () {
      var called = false;
      final response = ApiResponse<String>.fromJson(
        {'data': null},
        fromJsonT: (_) {
          called = true;
          return 'unreachable';
        },
      );
      expect(response.data, isNull);
      expect(called, isFalse);
    });

    test('a missing data key is null', () {
      expect(ApiResponse<String>.fromJson(<String, dynamic>{}).data, isNull);
    });

    test('without fromJsonT a matching raw value passes through', () {
      expect(ApiResponse<String>.fromJson({'data': 'raw'}).data, 'raw');
      expect(ApiResponse<int>.fromJson({'data': 7}).data, 7);
    });
  });

  group('fullCount', () {
    test('parses through JsonValue, so a numeric string works', () {
      expect(ApiResponse<void>.fromJson({'fullCount': 12}).fullCount, 12);
      expect(ApiResponse<void>.fromJson({'fullCount': '12'}).fullCount, 12);
    });

    test('is null when absent, null or unparseable', () {
      expect(
        ApiResponse<void>.fromJson(<String, dynamic>{}).fullCount,
        isNull,
      );
      expect(
        ApiResponse<void>.fromJson({'fullCount': null}).fullCount,
        isNull,
      );
      expect(
        ApiResponse<void>.fromJson({'fullCount': 'many'}).fullCount,
        isNull,
      );
    });
  });

  group('message', () {
    test('a string is kept', () {
      expect(ApiResponse<void>.fromJson({'message': 'hi'}).message, 'hi');
    });

    test('a non-string is stringified rather than dropped', () {
      expect(ApiResponse<void>.fromJson({'message': 42}).message, '42');
    });

    test('is null when absent or null', () {
      expect(ApiResponse<void>.fromJson(<String, dynamic>{}).message, isNull);
      expect(ApiResponse<void>.fromJson({'message': null}).message, isNull);
    });
  });

  group('error', () {
    test('a map becomes an ApiErrorModel', () {
      final response = ApiResponse<void>.fromJson({
        'error': {'message': 'bad', 'code': 400},
      });
      expect(response.error, isA<ApiErrorModel>());
      expect(response.error!.message, 'bad');
      expect(response.error!.code, 400);
    });

    test('a loosely typed map is accepted', () {
      final response = ApiResponse<void>.fromJson({
        'error': <dynamic, dynamic>{'message': 'bad', 'code': '401'},
      });
      expect(response.error!.message, 'bad');
      expect(response.error!.code, 401, reason: 'code goes through parseInt');
    });

    test('is null when absent, null, or not a map', () {
      expect(ApiResponse<void>.fromJson(<String, dynamic>{}).error, isNull);
      expect(ApiResponse<void>.fromJson({'error': null}).error, isNull);
      expect(ApiResponse<void>.fromJson({'error': 'boom'}).error, isNull);
    });
  });

  group('displayMessage', () {
    test('prefers the error message', () {
      final response = ApiResponse<void>.fromJson({
        'message': 'envelope',
        'error': {'message': 'from error'},
      });
      expect(response.displayMessage, 'from error');
    });

    test('falls back to the envelope message', () {
      final response = ApiResponse<void>.fromJson({'message': 'envelope'});
      expect(response.displayMessage, 'envelope');
    });

    test('skips a blank error message and uses the envelope one', () {
      final response = ApiResponse<void>.fromJson({
        'message': 'envelope',
        'error': {'message': '   '},
      });
      expect(response.displayMessage, 'envelope');
    });

    test('falls back to the localized default when both are blank', () {
      final response = ApiResponse<void>.fromJson({'message': '  '});
      expect(response.displayMessage, AppStrings.current.requestFailed);
      expect(response.displayMessage, 'Request failed');
    });

    test('falls back to the localized default when both are absent', () {
      expect(
        ApiResponse<void>.fromJson(<String, dynamic>{}).displayMessage,
        'Request failed',
      );
    });

    test('the default follows the app language', () {
      AppStrings.setLanguage(AppLanguage.arabic);
      expect(
        ApiResponse<void>.fromJson(<String, dynamic>{}).displayMessage,
        'فشل الطلب',
      );
    });

    test('the returned message is trimmed, while the raw field is not', () {
      final response = ApiResponse<void>.fromJson({'message': '  hi  '});
      expect(response.displayMessage, 'hi');
      expect(response.message, '  hi  ');
    });

    test('an error message is trimmed the same way', () {
      final response = ApiResponse<void>.fromJson({
        'error': {'message': '  bad  '},
      });
      expect(response.displayMessage, 'bad');
    });
  });

  group('statusCode', () {
    test('comes from the error code', () {
      final response = ApiResponse<void>.fromJson({
        'error': {'code': 404},
      });
      expect(response.statusCode, 404);
    });

    test('is null with no error or no code', () {
      expect(
        ApiResponse<void>.fromJson(<String, dynamic>{}).statusCode,
        isNull,
      );
      expect(
        ApiResponse<void>.fromJson({'error': {'message': 'x'}}).statusCode,
        isNull,
      );
    });
  });

  group('equality', () {
    test('two envelopes with the same fields are equal', () {
      final a = ApiResponse<String>.fromJson({
        'data': 'x',
        'succeeded': true,
        'fullCount': 2,
        'message': 'm',
      });
      final b = ApiResponse<String>.fromJson({
        'data': 'x',
        'succeeded': true,
        'fullCount': 2,
        'message': 'm',
      });
      expect(a, b);
    });

    test('a differing field breaks equality', () {
      final a = ApiResponse<String>.fromJson({'data': 'x', 'succeeded': true});
      final b = ApiResponse<String>.fromJson({'data': 'y', 'succeeded': true});
      expect(a, isNot(b));
    });
  });
}

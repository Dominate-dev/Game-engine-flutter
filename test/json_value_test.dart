import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// T-COV — JsonValue is pure Dart with 87 call sites and had no tests. Every
// hub payload read and every model parse goes through it.
//
// These assert the coercions the codebase actually relies on. Where the
// implementation has an edge nothing in the repository justifies as
// deliberate, it is left untested and reported instead of being pinned.

void main() {
  group('parseInt', () {
    test('null yields null', () {
      expect(JsonValue.parseInt(null), isNull);
    });

    test('an int passes through', () {
      expect(JsonValue.parseInt(0), 0);
      expect(JsonValue.parseInt(47), 47);
      expect(JsonValue.parseInt(-3), -3);
    });

    test('a positive double truncates toward zero', () {
      expect(JsonValue.parseInt(10.0), 10);
      expect(JsonValue.parseInt(10.5), 10);
      expect(JsonValue.parseInt(10.999), 10);
    });

    test('a numeric string parses', () {
      expect(JsonValue.parseInt('47'), 47);
      expect(JsonValue.parseInt('-3'), -3);
      expect(JsonValue.parseInt('0'), 0);
    });

    test('a non-numeric string yields null rather than throwing', () {
      expect(JsonValue.parseInt('timeout'), isNull);
      expect(JsonValue.parseInt(''), isNull);
      expect(JsonValue.parseInt('ALLOW_ALL'), isNull);
    });

    test('a decimal string yields null — int.tryParse does not truncate', () {
      expect(JsonValue.parseInt('10.5'), isNull);
    });

    test('a non-numeric type yields null rather than throwing', () {
      expect(JsonValue.parseInt(true), isNull);
      expect(JsonValue.parseInt(<int>[1]), isNull);
      expect(JsonValue.parseInt(<String, dynamic>{}), isNull);
    });
  });

  group('parseDouble', () {
    test('null yields null', () {
      expect(JsonValue.parseDouble(null), isNull);
    });

    test('a double passes through with its fraction intact', () {
      expect(JsonValue.parseDouble(10.999), 10.999);
      expect(JsonValue.parseDouble(0.0), 0.0);
      expect(JsonValue.parseDouble(-2.5), -2.5);
    });

    test('an int widens', () {
      expect(JsonValue.parseDouble(30), 30.0);
      expect(JsonValue.parseDouble(0), 0.0);
    });

    test('a numeric string parses, fraction preserved', () {
      expect(JsonValue.parseDouble('10.999'), 10.999);
      expect(JsonValue.parseDouble('30'), 30.0);
    });

    test('a non-numeric string or type yields null', () {
      expect(JsonValue.parseDouble('soon'), isNull);
      expect(JsonValue.parseDouble(''), isNull);
      expect(JsonValue.parseDouble(true), isNull);
      expect(JsonValue.parseDouble(<int>[1]), isNull);
    });
  });

  group('parseBool', () {
    test('null yields null', () {
      expect(JsonValue.parseBool(null), isNull);
    });

    test('a bool passes through', () {
      expect(JsonValue.parseBool(true), isTrue);
      expect(JsonValue.parseBool(false), isFalse);
    });

    test('a number is false only at zero', () {
      expect(JsonValue.parseBool(0), isFalse);
      expect(JsonValue.parseBool(0.0), isFalse);
      expect(JsonValue.parseBool(1), isTrue);
      expect(JsonValue.parseBool(-1), isTrue);
      expect(JsonValue.parseBool(0.5), isTrue);
    });

    test('the accepted strings are true/1 and false/0', () {
      expect(JsonValue.parseBool('true'), isTrue);
      expect(JsonValue.parseBool('1'), isTrue);
      expect(JsonValue.parseBool('false'), isFalse);
      expect(JsonValue.parseBool('0'), isFalse);
    });

    test('string matching ignores case and surrounding whitespace', () {
      expect(JsonValue.parseBool('TRUE'), isTrue);
      expect(JsonValue.parseBool('  True  '), isTrue);
      expect(JsonValue.parseBool(' FALSE '), isFalse);
    });

    test('any other string yields null', () {
      expect(JsonValue.parseBool('yes'), isNull);
      expect(JsonValue.parseBool(''), isNull);
      expect(JsonValue.parseBool('2'), isNull);
    });
  });

  // The case tolerance W-5 and W-6 depend on: a hub payload may deliver
  // `type` as `Type`, and answer text as `AnswerText`.
  group('field — key resolution', () {
    test('an exact camelCase key wins', () {
      expect(JsonValue.field({'type': 1}, 'type'), 1);
    });

    test('a PascalCase key resolves', () {
      expect(JsonValue.field({'Type': 2}, 'type'), 2);
      expect(JsonValue.field({'AnswerText': 'a'}, 'answerText'), 'a');
    });

    test('any casing resolves through the fallback scan', () {
      expect(JsonValue.field({'TYPE': 3}, 'type'), 3);
      expect(JsonValue.field({'tYpE': 4}, 'type'), 4);
      expect(JsonValue.field({'ANSWERTEXT': 'b'}, 'answerText'), 'b');
    });

    test('the exact key is preferred over a differently cased one', () {
      expect(JsonValue.field({'type': 1, 'Type': 2}, 'type'), 1);
    });

    test('a missing key yields null', () {
      expect(JsonValue.field({'other': 1}, 'type'), isNull);
      expect(JsonValue.field(<String, dynamic>{}, 'type'), isNull);
    });

    test('a present key holding null yields null — use hasField to tell', () {
      expect(JsonValue.field({'type': null}, 'type'), isNull);
      expect(JsonValue.hasField({'type': null}, 'type'), isTrue);
    });

    test('an empty key name resolves only an exactly empty key', () {
      expect(JsonValue.field({'': 9}, ''), 9);
      expect(JsonValue.field({'type': 1}, ''), isNull);
    });

    test('falsey and empty values are returned, not swallowed', () {
      expect(JsonValue.field({'a': 0}, 'a'), 0);
      expect(JsonValue.field({'a': false}, 'a'), false);
      expect(JsonValue.field({'a': ''}, 'a'), '');
    });
  });

  group('hasField', () {
    test('matches exact, PascalCase and any other casing', () {
      expect(JsonValue.hasField({'players': <dynamic>[]}, 'players'), isTrue);
      expect(JsonValue.hasField({'Players': <dynamic>[]}, 'players'), isTrue);
      expect(JsonValue.hasField({'PLAYERS': <dynamic>[]}, 'players'), isTrue);
    });

    test('a key present with a null value still counts as present', () {
      expect(JsonValue.hasField({'currentTurn': null}, 'currentTurn'), isTrue);
    });

    test('a missing key is false', () {
      expect(JsonValue.hasField({'other': 1}, 'players'), isFalse);
      expect(JsonValue.hasField(<String, dynamic>{}, 'players'), isFalse);
    });

    test('an empty key name matches only an exactly empty key', () {
      expect(JsonValue.hasField({'': 1}, ''), isTrue);
      expect(JsonValue.hasField({'a': 1}, ''), isFalse);
    });

    test('agrees with field for every present key', () {
      const json = <String, dynamic>{'Status': 3};
      expect(JsonValue.hasField(json, 'status'), isTrue);
      expect(JsonValue.field(json, 'status'), 3);
    });
  });

  group('asMap', () {
    test('a Map<String, dynamic> is returned as the same instance', () {
      final json = <String, dynamic>{'a': 1};
      expect(identical(JsonValue.asMap(json), json), isTrue);
    });

    test('a loosely typed map is copied into a typed one', () {
      final loose = <dynamic, dynamic>{'a': 1, 'b': 'two'};
      final result = JsonValue.asMap(loose);

      expect(result, <String, dynamic>{'a': 1, 'b': 'two'});
      expect(result, isA<Map<String, dynamic>>());
      expect(identical(result, loose), isFalse);
    });

    test('null and non-map values yield an empty map, never a throw', () {
      expect(JsonValue.asMap(null), isEmpty);
      expect(JsonValue.asMap('not a map'), isEmpty);
      expect(JsonValue.asMap(47), isEmpty);
      expect(JsonValue.asMap(<int>[1, 2]), isEmpty);
    });

    test('the empty-map result is mutable and independent per call', () {
      final first = JsonValue.asMap(null)..['x'] = 1;
      expect(JsonValue.asMap(null), isEmpty, reason: 'no shared instance');
      expect(first, {'x': 1});
    });
  });
}

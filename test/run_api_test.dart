import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// E4 — runApi must not cast the sealed Result, and a screen callback that
// throws must not escape into the caller's async context. The API call
// already succeeded, so a callback failure is diagnostic only.

class _TestPage extends ConsumerStatefulWidget {
  const _TestPage();

  @override
  ConsumerState<_TestPage> createState() => _TestPageState();
}

class _TestPageState extends BaseState<_TestPage> {
  // Keeps the test off networkInfoProvider, which starts real plugin streams.
  @override
  bool get handleInternetConnection => false;

  bool online = true;

  @override
  Future<bool> checkInternetConnection() async => online;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late ProviderContainer container;

  Future<_TestPageState> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPrefsService.init();
    container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _TestPage()),
      ),
    );
    return tester.state<_TestPageState>(find.byType(_TestPage));
  }

  bool loaderVisible() => container.read(loaderVisibleProvider).isVisible;

  group('success path', () {
    testWidgets('a non-null result reaches onSuccess and is returned',
        (tester) async {
      final state = await pumpPage(tester);
      String? received;

      final returned = await state.runApi<String>(
        () async => Result.success('ok'),
        error: ErrorType.none,
        onSuccess: (data) => received = data,
      );
      await tester.pump();

      expect(received, 'ok');
      expect(returned, 'ok');
    });

    testWidgets('a null result with a nullable T needs no cast',
        (tester) async {
      final state = await pumpPage(tester);
      var called = false;
      Object? received = 'sentinel';

      await state.runApi<String?>(
        () async => Result<String?>.success(null),
        error: ErrorType.none,
        onSuccess: (data) {
          called = true;
          received = data;
        },
      );
      await tester.pump();

      expect(called, isTrue);
      expect(received, isNull);
    });

    testWidgets('a missing onSuccess is fine', (tester) async {
      final state = await pumpPage(tester);
      final returned =
          await state.runApi<int>(() async => Result.success(7),
              error: ErrorType.none);
      expect(returned, 7);
    });
  });

  group('onSuccess that throws', () {
    testWidgets('does not escape runApi', (tester) async {
      final state = await pumpPage(tester);

      // Pre-fix this rethrows out of runApi and fails the test.
      final returned = await state.runApi<String>(
        () async => Result.success('ok'),
        error: ErrorType.none,
        onSuccess: (_) => throw StateError('callback blew up'),
      );
      await tester.pump();

      expect(returned, 'ok');
    });

    testWidgets('an async onSuccess that throws also does not escape',
        (tester) async {
      final state = await pumpPage(tester);

      final returned = await state.runApi<String>(
        () async => Result.success('ok'),
        error: ErrorType.none,
        // No Future.delayed here: flutter_test only advances its clock on
        // pump, and the body is blocked awaiting runApi.
        onSuccess: (_) async => throw StateError('async callback blew up'),
      );
      await tester.pump();

      expect(returned, 'ok');
    });

    testWidgets('shows no error dialog — the request itself succeeded',
        (tester) async {
      final state = await pumpPage(tester);

      await state.runApi<String>(
        () async => Result.success('ok'),
        onSuccess: (_) => throw StateError('callback blew up'),
      );
      await tester.pump();

      expect(find.text('callback blew up'), findsNothing);
      expect(find.text(AppStrings.current.confirm), findsNothing);
    });

    testWidgets('does not invoke onError', (tester) async {
      final state = await pumpPage(tester);
      var onErrorCalls = 0;

      await state.runApi<String>(
        () async => Result.success('ok'),
        error: ErrorType.none,
        onSuccess: (_) => throw StateError('callback blew up'),
        onError: (_) => onErrorCalls++,
      );
      await tester.pump();

      expect(onErrorCalls, 0);
    });

    testWidgets('leaves the loader cleared', (tester) async {
      final state = await pumpPage(tester);
      expect(loaderVisible(), isFalse);

      await state.runApi<String>(
        () async => Result.success('ok'),
        error: ErrorType.none,
        onSuccess: (_) => throw StateError('callback blew up'),
      );
      await tester.pump();

      expect(loaderVisible(), isFalse);
    });
  });

  group('failure path is unchanged', () {
    testWidgets('a failed Result still routes through _fail', (tester) async {
      final state = await pumpPage(tester);
      Failure? seen;

      final returned = await state.runApi<String>(
        () async => Result.failure(ServerFailure(message: 'boom')),
        error: ErrorType.none,
        onError: (failure) => seen = failure,
      );
      await tester.pump();

      expect(returned, isNull);
      expect(seen, isA<ServerFailure>());
      expect(seen!.message, 'boom');
    });

    testWidgets('onSuccess is not called on failure', (tester) async {
      final state = await pumpPage(tester);
      var successCalls = 0;

      await state.runApi<String>(
        () async => Result.failure(ServerFailure(message: 'boom')),
        error: ErrorType.none,
        onSuccess: (_) => successCalls++,
      );
      await tester.pump();

      expect(successCalls, 0);
    });

    testWidgets('offline short-circuits to a no-internet failure',
        (tester) async {
      final state = await pumpPage(tester)
        ..online = false;
      Failure? seen;

      final returned = await state.runApi<String>(
        () async => Result.success('never reached'),
        error: ErrorType.none,
        onError: (failure) => seen = failure,
      );
      await tester.pump();

      expect(returned, isNull);
      expect(seen, isA<NoInternetFailure>());
    });

    testWidgets('a throwing call() still becomes a failure', (tester) async {
      final state = await pumpPage(tester);
      Failure? seen;

      await state.runApi<String>(
        () async => throw StateError('call blew up'),
        error: ErrorType.none,
        onError: (failure) => seen = failure,
      );
      await tester.pump();

      // E2: the raw text is the diagnostic cause, never the message.
      expect(seen, isA<UnknownFailure>());
      expect(seen!.message, AppStrings.current.unknownError);
      expect(seen!.cause, contains('call blew up'));
      expect(loaderVisible(), isFalse);
    });
  });

  group('N2 — an UnauthorizedFailure clears the stored auth', () {
    testWidgets('the server rejecting the token stops it from being reused',
        (tester) async {
      final state = await pumpPage(tester);
      final prefs = container.read(sharedPrefsProvider);
      await prefs.setToken(value: 'stale-token');
      await prefs.setInt(PrefsKeys.userId, 47);
      expect(prefs.getToken(), 'stale-token', reason: 'sanity');

      await state.runApi<String>(
        () async => Result.failure(UnauthorizedFailure()),
        error: ErrorType.none,
      );
      await tester.pump();

      expect(prefs.getToken(), isNull);
      expect(prefs.getInt(PrefsKeys.userId), isNull);
    });

    testWidgets('a non-401 failure leaves the stored auth untouched',
        (tester) async {
      final state = await pumpPage(tester);
      final prefs = container.read(sharedPrefsProvider);
      await prefs.setToken(value: 'still-valid');

      await state.runApi<String>(
        () async => Result.failure(ServerFailure(message: 'boom')),
        error: ErrorType.none,
      );
      await tester.pump();

      expect(prefs.getToken(), 'still-valid');
    });
  });
}

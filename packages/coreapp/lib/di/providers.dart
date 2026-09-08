import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_endpoints.dart';
import '../features/auth/data/datasources/auth_remote_datasource.dart';
import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/data/services/auth_token_refresher.dart';
import '../network/api_client.dart';
import '../network/api_headers_builder.dart';
import '../network/network_info_provider.dart';
import '../storage/shared_prefs_service.dart';

/// Must be overridden in main() after `await SharedPrefsService.init()`:
///
/// ```dart
/// runApp(
///   ProviderScope(
///     overrides: [
///       sharedPrefsProvider.overrideWithValue(sharedPrefs),
///     ],
///     child: const MyApp(),
///   ),
/// );
/// ```
final sharedPrefsProvider = Provider<SharedPrefsService>((ref) {
  throw UnimplementedError(
    'sharedPrefsProvider must be overridden in main() after '
    'await SharedPrefsService.init()',
  );
});

final apiHeadersBuilderProvider = Provider<ApiHeadersBuilder>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ApiHeadersBuilder(prefs);
});

// Explicitly typed, both here and on authTokenRefresherProvider below: the
// two reference each other (one at build time, one lazily inside a closure),
// which type inference alone cannot resolve.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  final headersBuilder = ref.watch(apiHeadersBuilderProvider);
  final networkInfo = ref.watch(networkInfoProvider);

  return ApiClient(
    baseUrl: ApiEndpoints.baseUrl,
    headersBuilder: headersBuilder,
    tokenProvider: () => prefs.getToken(),
    networkInfo: networkInfo,
    // N2/P1a: `ref.read` here runs only inside a closure invoked later, on
    // an actual 401 — never during this provider's own build — which is
    // what lets authTokenRefresherProvider watch apiClientProvider without
    // a build-time cycle.
    obtainRefreshedAccessToken: () => ref.read(authTokenRefresherProvider)(),
  );
});

/// P1a: one shared refresher for every transport. Both the REST
/// `RefreshTokenInterceptor` and the SignalR upgrade client route through
/// this single instance, so its in-flight guard coordinates them — there is
/// exactly one refresh mechanism, not one per transport.
final Provider<AuthTokenRefresher> authTokenRefresherProvider =
    Provider<AuthTokenRefresher>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  final client = ref.watch(apiClientProvider);
  return AuthTokenRefresher(
    repository: AuthRepositoryImpl(AuthRemoteDataSourceImpl(client)),
    prefs: prefs,
  );
});

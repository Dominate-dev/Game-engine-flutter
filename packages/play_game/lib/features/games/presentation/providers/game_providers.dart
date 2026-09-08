import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/game_remote_datasource.dart';
import '../../data/repositories/game_repository_impl.dart';
import '../../domain/repositories/game_repository.dart';

final gameRemoteDataSourceProvider = Provider<GameRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return GameRemoteDataSourceImpl(apiClient);
});

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final dataSource = ref.watch(gameRemoteDataSourceProvider);
  return GameRepositoryImpl(dataSource);
});

/// `type` for a private game's invite link — the confirmed contract value.
///
/// It lives at the one call site rather than inside the endpoint or the
/// datasource, both of which take `type` as a parameter and assume nothing.
const privateGameLinkType = 2;

/// The invite link for the private game currently in the lobby.
///
/// [url] is only ever what the server returned; there is no locally
/// constructed fallback, so [hasUrl] is false until a request succeeds with a
/// non-blank value. [failure] carries the repository's existing [Failure] so
/// the standard error mechanism stays available to callers.
class PrivateGameLinkState {
  const PrivateGameLinkState({
    this.url,
    this.isLoading = false,
    this.failure,
  });

  final String? url;
  final bool isLoading;
  final Failure? failure;

  bool get hasUrl => url != null && url!.isNotEmpty;
}

/// Fetches and holds the invite link, one request per game code.
///
/// Provider-held rather than widget-held so it survives the lobby's rebuilds
/// — every `GameUpdated`, `PlayerReady` and phase refresh rebuilds that
/// screen, and none of them may re-issue the request.
class PrivateGameLinkNotifier extends AutoDisposeNotifier<PrivateGameLinkState> {
  /// The code a request has already been issued for. This — not a widget flag
  /// — is what makes the call happen once: rebuilds, repeated hub events and
  /// a re-entered lobby all pass the same code and are ignored.
  String? _requestedCode;

  @override
  PrivateGameLinkState build() => const PrivateGameLinkState();

  /// Requests the link for [code] unless one was already requested for it.
  ///
  /// A missing code is not an error and not a request: the lobby simply has
  /// nothing to share until `GameCreated` supplies one.
  ///
  /// A failed request is not retried. The repository has no retry policy for
  /// this call and inventing one is out of scope; the lobby keeps sharing
  /// disabled instead.
  Future<void> ensureFor(String? code) async {
    final trimmed = code?.trim() ?? '';
    if (trimmed.isEmpty || _requestedCode == trimmed) {
      return;
    }
    _requestedCode = trimmed;
    state = const PrivateGameLinkState(isLoading: true);
    final result = await ref.read(gameRepositoryProvider).generateUrl(
          type: privateGameLinkType,
          code: trimmed,
        );
    state = result.when(
      success: (url) {
        final trimmedUrl = url.trim();
        // A blank success is treated as "no link" rather than shared as an
        // empty string. Nothing is substituted for it.
        return PrivateGameLinkState(
          url: trimmedUrl.isEmpty ? null : trimmedUrl,
        );
      },
      failure: (failure) => PrivateGameLinkState(failure: failure),
    );
  }
}

final privateGameLinkProvider =
    NotifierProvider.autoDispose<PrivateGameLinkNotifier, PrivateGameLinkState>(
  PrivateGameLinkNotifier.new,
);

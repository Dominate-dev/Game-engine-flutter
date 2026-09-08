import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../base/failure.dart';
import '../../../../di/providers.dart';
import '../../domain/entities/auth_session.dart';
import 'auth_providers.dart';

/// Observable auth state — every game plugin watches this instead of
/// calling [LoginUseCase] directly, so "is logged in" / "current user" is
/// reactive across the whole app.
///
/// Bootstraps from whatever's already in [SharedPrefsService] (so a warm
/// start doesn't show a logged-out flash), then `login()`/`logout()`
/// mutate both this state and persisted storage together.
final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthSession?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final prefs = ref.watch(sharedPrefsProvider);
    final token = prefs.getToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    final userId = prefs.getUserId();
    return AuthSession(
      token: token,
      refreshToken: prefs.getRefreshToken(),
      userId: userId == 0 ? null : userId.toString(),
    );
  }

  bool get isLoggedIn => state.valueOrNull != null;

  /// Returns `null` on success, or the [Failure] on failure — callers
  /// that don't care about the reason can just check `isLoggedIn` after.
  Future<Failure?> login({
    required String userName,
    required String password,
    String socialMediaId = '',
  }) async {
    state = const AsyncLoading();

    final useCase = ref.read(loginUseCaseProvider);
    final result = await useCase(
      LoginParams(
        userName: userName,
        password: password,
        socialMediaId: socialMediaId,
      ),
    );

    if (result.isSuccess) {
      final session = result.dataOrNull!;
      await _persist(session, socialMediaId: socialMediaId);
      state = AsyncData(session);
      return null;
    }

    final failure = result.failureOrNull!;
    state = AsyncError(failure, StackTrace.current);
    return failure;
  }

  Future<void> logout() async {
    await ref.read(sharedPrefsProvider).clearAuth();
    state = const AsyncData(null);
  }

  Future<void> _persist(AuthSession session, {String socialMediaId = ''}) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setToken(value: session.token);
    if (session.refreshToken != null) {
      await prefs.setRefreshToken(value: session.refreshToken!);
    }
    if (session.userId != null) {
      await prefs.setUserId(value: session.userId!);
    }
    if (socialMediaId.trim().isNotEmpty) {
      await prefs.setSocialMediaId(value: socialMediaId.trim());
    }
  }
}

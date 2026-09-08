import '../../../../storage/shared_prefs_service.dart';
import '../../domain/repositories/auth_repository.dart';

/// N2: obtains a fresh access token using the stored refresh token, via the
/// same [AuthRepository.refresh] contract `login()` uses, persisting the
/// result (or clearing the stale session on failure) through the existing
/// [SharedPrefsService] mechanism. Used by `RefreshTokenInterceptor` to
/// recover from a 401 without any Flutter-side login UI.
class AuthTokenRefresher {
  AuthTokenRefresher({
    required AuthRepository repository,
    required SharedPrefsService prefs,
  })  : _repository = repository,
        _prefs = prefs;

  final AuthRepository _repository;
  final SharedPrefsService _prefs;

  Future<String?>? _pending;

  /// P1a: the in-flight guard lives here, not in any one caller, so a REST
  /// 401 and a SignalR upgrade 401 landing together share one refresh
  /// instead of each starting their own. A single instance is shared by
  /// both — see `authTokenRefresherProvider`.
  Future<String?> call() {
    final pending = _pending;
    if (pending != null) {
      return pending;
    }
    final future = _refresh();
    _pending = future;
    future.whenComplete(() {
      if (identical(_pending, future)) {
        _pending = null;
      }
    });
    return future;
  }

  Future<String?> _refresh() async {
    final refreshToken = _prefs.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _prefs.clearAuth();
      return null;
    }

    final result = await _repository.refresh(refreshToken);
    final session = result.dataOrNull;
    if (session == null || session.token.isEmpty) {
      await _prefs.clearAuth();
      return null;
    }

    await _prefs.setToken(value: session.token);
    if (session.refreshToken != null) {
      await _prefs.setRefreshToken(value: session.refreshToken!);
    }
    if (session.userId != null) {
      await _prefs.setUserId(value: session.userId!);
    }
    return session.token;
  }
}

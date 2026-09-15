/// Debug-only config used by the Register button on the launcher.
abstract final class DebugConfig {
  static const debugUserName = '';
  static const debugPassword = '';
  static const socialMedia = '112319659759268332039';
  // static const socialMedia = '118257441539724769068';
  // static const socialMedia = '101694257782137160947';

  /// Interest id sent with `CreatePrivateGame` from the debug launcher.
  ///
  /// TEMPORARY: the native host will pass the real interested id into
  /// `PlayGame.openPrivateGame`. It lives here, in the debug host, so the
  /// game engine itself never carries a hardcoded value.
  // static const privateGameInterestId = 1;
}

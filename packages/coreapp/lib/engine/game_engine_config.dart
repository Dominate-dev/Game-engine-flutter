import 'package:equatable/equatable.dart';

import '../constants/app_language.dart';

// Everything the native host tells the engine about the user and the app.
//
// This is the whole configuration contract. The host never sees the storage
// keys these end up under (`flutter.auth_token` and friends) — naming them is
// the engine's business, and moving one must not become a native release.
class GameEngineConfig extends Equatable {
  const GameEngineConfig({
    required this.token,
    this.userId = 0,
    this.socialMediaId = '',
    this.language = AppLanguage.english,
    this.musicEnabled = true,
    this.soundEnabled = true,
  });

  final String token;

  // The authenticated account id — the same numeric identity the game roster
  // uses for its players, and the one the engine matches the local seat on.
  // Zero means the host supplied none; it is an absence, not an account.
  //
  // Distinct from [socialMediaId], which identifies the sign-in provider
  // account and never appears in a roster. One is not a substitute for the
  // other.
  final int userId;

  final String socialMediaId;

  // Normalised to `ar` or `en` on the way in, so an unrecognised code from
  // the host falls back the same way the rest of the app already does rather
  // than reaching the string tables raw.
  final String language;

  final bool musicEnabled;
  final bool soundEnabled;

  GameEngineConfig copyWith({
    String? token,
    int? userId,
    String? socialMediaId,
    String? language,
    bool? musicEnabled,
    bool? soundEnabled,
  }) {
    return GameEngineConfig(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      socialMediaId: socialMediaId ?? this.socialMediaId,
      language: language ?? this.language,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }

  // The bridge's wire shape. Unknown keys are ignored and missing ones take
  // the defaults, so adding a field later cannot break an older host build.
  factory GameEngineConfig.fromMap(Map<Object?, Object?> map) {
    return GameEngineConfig(
      token: _string(map['token']),
      userId: _int(map['userId']),
      socialMediaId: _string(map['socialMediaId']),
      language: AppLanguage.normalize(_stringOrNull(map['language'])),
      musicEnabled: _bool(map['musicEnabled']) ?? true,
      soundEnabled: _bool(map['soundEnabled']) ?? true,
    );
  }

  Map<String, Object?> toMap() => {
        'token': token,
        'userId': userId,
        'socialMediaId': socialMediaId,
        'language': language,
        'musicEnabled': musicEnabled,
        'soundEnabled': soundEnabled,
      };

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static String? _stringOrNull(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  // Android hands an id across as an Int or a Long, iOS as an NSNumber, and a
  // host that stringifies it first is just as valid — all three land here as
  // the same account. Anything else is no id at all.
  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static bool? _bool(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true') {
      return true;
    }
    if (text == 'false') {
      return false;
    }
    return null;
  }

  @override
  List<Object?> get props =>
      [token, userId, socialMediaId, language, musicEnabled, soundEnabled];
}

import 'package:coreapp/coreapp.dart';

import '../../domain/entities/user_profile.dart';

class UserProfileModel {
  const UserProfileModel._();

  static UserProfile fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: JsonValue.parseInt(json['id'] ?? json['userId']) ?? 0,
      // `userName` is empty on real payloads; `fullName` carries the person's
      // name. Listed before it rather than after only for readability —
      // _firstString skips empties either way.
      name: _firstString(json, const [
        'name',
        'fullName',
        'userName',
        'displayName',
      ]),
      // The `*Url` fields first: the backend serves media from
      // `/api/media-storage/…`, which the bare `profileImage` name does not
      // carry, so rebuilding a URL from it produced a path that 404s. The
      // absolute URL passes through _mediaUrl untouched.
      imagePath: _firstString(json, const [
        'profileImageUrl',
        'image',
        'profileImage',
        'path',
      ]),
      coverPath: _firstString(json, const [
        'profileBackgroundUrl',
        'cover',
        'background',
        'backgroundImage',
        'profileBackground',
      ]),
      level: JsonValue.parseInt(json['level'] ?? json['levelNumber']) ?? 0,
      levelTitle: _firstString(json, const [
        'levelName',
        'levelTitle',
        'userLevelTypeTitle',
      ]),
      xp: JsonValue.parseInt(json['xp'] ?? json['points']) ?? 0,
      coins: JsonValue.parseInt(json['coins'] ?? json['gold']) ?? 0,
      diamonds: JsonValue.parseInt(
            json['diamonds'] ?? json['jewels'] ?? json['jawaher'],
          ) ??
          0,
      categories: _asInterests(json['categories'] ?? json['interests']),
    );
  }
}

class ProfileInterestModel {
  const ProfileInterestModel._();

  static ProfileInterest fromJson(Map<String, dynamic> json) {
    return ProfileInterest(
      // A category carries `title` (already localized by the backend from the
      // Accept-Language header this client sends); `name` is null on it.
      name: _firstString(json, const ['name', 'title']),
      id: JsonValue.parseInt(json['id']) ?? 0,
      // Same media-path reason as the profile images above.
      path: _firstString(json, const ['path', 'imageUrl', 'image']),
      isActive: json['isActive'] == true,
    );
  }
}

List<ProfileInterest> _asInterests(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => ProfileInterestModel.fromJson(JsonValue.asMap(item)))
      .toList();
}

String _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

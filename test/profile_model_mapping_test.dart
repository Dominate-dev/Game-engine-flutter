import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/features/profile/data/models/profile_models.dart';

// UserProfileModel against the shape the backend actually returns.
//
// Every fixture key below was taken from a live
// `POST /api/Users/PublicPorfile/{id}` response, not from the entity. The
// model had been written against guessed key names, so four fields silently
// mapped to nothing and the images were rebuilt into 404s:
//
//   name        <- `fullName`            (`userName` is empty on real data)
//   coverPath   <- `profileBackgroundUrl`(no `cover`/`background` key exists)
//   levelTitle  <- `userLevelTypeTitle`  (no `levelName`/`levelTitle` key)
//   interest    <- `title`               (a category's `name` is null)
//
// and the media URLs come ready-made from the backend under
// `/api/media-storage/…`, which the bare file name cannot reconstruct.

/// The real payload's `data` object, trimmed to the keys the model reads and
/// the ones that used to be mistaken for them.
Map<String, dynamic> _apiProfile() => {
      'id': 47,
      'userName': '',
      'fullName': 'Hassan Player',
      'profileImage': '3546c0a1b2c3d4e5f60718293a4b5c6d7e8f9012',
      'profileImageUrl':
          'https://api-v2.tahadialthalatheen.com/api/media-storage/assetss/'
              '3546c0a1b2c3d4e5f60718293a4b5c6d7e8f9012',
      'profileBackground': 'a54b1c2d3e4f5061728394a5b6c7d8e9f0a1b2c3',
      'profileBackgroundUrl':
          'https://api-v2.tahadialthalatheen.com/api/media-storage/assetss/'
              'a54b1c2d3e4f5061728394a5b6c7d8e9f0a1b2c3',
      'xp': 536,
      'coins': 276,
      'diamonds': 0,
      'level': 3,
      'userLevelTypeTitle': 'مبتدئ',
      'userLevelTypeTitleAr': 'مبتدئ',
      'userLevelTypeTitleEn': 'Beginner',
      'playerLevel': {
        'level': 3,
        'nameAr': 'مبتدئ',
        'nameEn': 'Beginner',
        'name': 'مبتدئ',
        'nextLevelXP': 1000,
      },
      'categories': [
        {
          'id': 12,
          'name': null,
          'title': 'كرة القدم',
          'titleAr': 'كرة القدم',
          'titleEn': 'Football',
          'image': '6f9a1b2c3d4e5f60718293a4b5c6d7e8',
          'imageUrl': 'https://api-v2.tahadialthalatheen.com/api/'
              'media-storage/6f9a1b2c3d4e5f60718293a4b5c6d7e8',
          'isActive': true,
        },
      ],
    };

void main() {
  group('UserProfileModel.fromJson — the real payload', () {
    test('the name comes from fullName, not the empty userName', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.name, 'Hassan Player');
      expect(profile.displayName, 'Hassan Player');
    });

    test('an empty userName is skipped rather than winning', () {
      // The bug: `userName` was consulted and `fullName` was not, so the name
      // the UI showed was ''.
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.name, isNotEmpty);
    });

    test('the level title comes from userLevelTypeTitle', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.levelTitle, 'مبتدئ');
      expect(profile.displayLevelTitle, 'مبتدئ');
    });

    test('the cover comes from profileBackgroundUrl', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.coverPath, isNotEmpty);
      expect(
        profile.backgroundImageUrl,
        'https://api-v2.tahadialthalatheen.com/api/media-storage/assetss/'
        'a54b1c2d3e4f5061728394a5b6c7d8e9f0a1b2c3',
      );
    });

    test('the avatar uses the URL the backend supplies, not a rebuilt one',
        () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(
        profile.profileImageUrl,
        'https://api-v2.tahadialthalatheen.com/api/media-storage/assetss/'
        '3546c0a1b2c3d4e5f60718293a4b5c6d7e8f9012',
        reason: 'the bare profileImage name has no /api/media-storage/ path, '
            'so a rebuilt URL 404s',
      );
      expect(profile.profileImageUrl, contains('/api/media-storage/'));
    });

    test('the numbers the UI shows are unchanged', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.id, 47);
      expect(profile.xp, 536);
      expect(profile.displayXp, '536');
      expect(profile.coins, 276);
      expect(profile.diamonds, 0);
      expect(profile.level, 3);
      expect(profile.displayLevel, '3');
    });

    test('nothing the UI reads is left empty by the mapping', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.displayName, isNotEmpty);
      expect(profile.profileImageUrl, isNotNull);
      expect(profile.backgroundImageUrl, isNotNull);
      expect(profile.displayLevelTitle, isNotEmpty);
      expect(profile.categories, isNotEmpty);
      expect(profile.categories.single.name, isNotEmpty);
      expect(profile.categories.single.imageUrl, isNotNull);
    });
  });

  group('ProfileInterestModel.fromJson — the real category shape', () {
    test('the interest name comes from title, since name is null', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.categories.single.name, 'كرة القدم');
    });

    test('the interest image uses the supplied imageUrl', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(
        profile.categories.single.imageUrl,
        'https://api-v2.tahadialthalatheen.com/api/media-storage/'
        '6f9a1b2c3d4e5f60718293a4b5c6d7e8',
      );
    });

    test('id and isActive still map as they did', () {
      final profile = UserProfileModel.fromJson(_apiProfile());

      expect(profile.categories.single.id, 12);
      expect(profile.categories.single.isActive, isTrue);
    });
  });

  group('key precedence', () {
    test('an explicit name/levelName still wins over the payload keys', () {
      final profile = UserProfileModel.fromJson({
        ..._apiProfile(),
        'name': 'Explicit Name',
        'levelName': 'Explicit Level',
      });

      expect(profile.name, 'Explicit Name');
      expect(profile.levelTitle, 'Explicit Level');
    });

    test("the backend's own media URL wins over a legacy relative key", () {
      // Deliberate: `cover`/`background` never appear on a real payload, and
      // if one ever did, a relative path rebuilt against the base URL is
      // exactly the 404 this fix removes. The absolute URL is authoritative.
      final profile = UserProfileModel.fromJson({
        ..._apiProfile(),
        'cover': '/cover.png',
      });

      expect(profile.backgroundImageUrl, contains('/api/media-storage/'));
    });

    test('a relative path is still resolved against the base URL', () {
      final profile = UserProfileModel.fromJson({
        'id': 1,
        'cover': '/cover.png',
      });

      expect(profile.backgroundImageUrl, '${ApiEndpoints.baseUrl}/cover.png');
    });

    test('a payload with none of these keys still parses to defaults', () {
      final profile = UserProfileModel.fromJson({'id': 9});

      expect(profile.id, 9);
      expect(profile.name, '');
      expect(profile.profileImageUrl, isNull);
      expect(profile.backgroundImageUrl, isNull);
      expect(profile.categories, isEmpty);
    });
  });
}

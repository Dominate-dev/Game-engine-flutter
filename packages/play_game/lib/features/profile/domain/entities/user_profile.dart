import 'package:coreapp/coreapp.dart';
import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.name,
    this.imagePath = '',
    this.coverPath = '',
    this.level = 0,
    this.levelTitle = '',
    this.xp = 0,
    this.coins = 0,
    this.diamonds = 0,
    this.categories = const [],
  });

  final int id;
  final String name;
  final String imagePath;
  final String coverPath;
  final int level;
  final String levelTitle;
  final int xp;
  final int coins;
  final int diamonds;
  final List<ProfileInterest> categories;

  String get displayName => name;

  String? get profileImageUrl => _mediaUrl(imagePath);

  String? get backgroundImageUrl => _mediaUrl(coverPath);

  String get displayLevelTitle =>
      levelTitle.trim().isNotEmpty ? levelTitle : displayLevel;

  String get displayXp => xp.toString();

  String get displayLevel => level > 0 ? level.toString() : '';

  @override
  List<Object?> get props => [id];
}

class ProfileInterest extends Equatable {
  const ProfileInterest({
    required this.id,
    required this.name,
    this.path = '',
    this.isActive = false,
  });

  final int id;
  final String name;
  final String path;
  final bool isActive;

  String? get imageUrl => _mediaUrl(path);

  @override
  List<Object?> get props => [id];
}

String? _mediaUrl(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    return '${ApiEndpoints.baseUrl}$trimmed';
  }
  return '${ApiEndpoints.baseUrl}/$trimmed';
}

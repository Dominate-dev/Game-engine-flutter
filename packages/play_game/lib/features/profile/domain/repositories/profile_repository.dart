import 'package:coreapp/coreapp.dart';

import '../entities/user_profile.dart';

abstract class ProfileRepository {
  Future<Result<UserProfile>> getPublicProfile(int id);
}

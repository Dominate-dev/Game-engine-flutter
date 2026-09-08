import 'package:coreapp/coreapp.dart';

import '../entities/user_profile.dart';
import '../repositories/profile_repository.dart';

class GetPublicProfileUseCase implements BaseUseCase<UserProfile, int> {
  const GetPublicProfileUseCase(this._repository);

  final ProfileRepository _repository;

  @override
  Future<Result<UserProfile>> call(int params) =>
      _repository.getPublicProfile(params);
}

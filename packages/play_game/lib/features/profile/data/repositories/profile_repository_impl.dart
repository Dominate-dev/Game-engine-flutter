import 'package:coreapp/coreapp.dart';

import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_datasource.dart';

class ProfileRepositoryImpl with BaseRepository implements ProfileRepository {
  const ProfileRepositoryImpl(this._remoteDataSource);

  final ProfileRemoteDataSource _remoteDataSource;

  @override
  Future<Result<UserProfile>> getPublicProfile(int id) =>
      guard(() => _remoteDataSource.getPublicProfile(id));
}

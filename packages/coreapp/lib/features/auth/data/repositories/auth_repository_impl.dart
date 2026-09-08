import '../../../../base/base_repository.dart';
import '../../../../base/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl with BaseRepository implements AuthRepository {
  const AuthRepositoryImpl(this._remoteDataSource);

  final AuthRemoteDataSource _remoteDataSource;

  @override
  Future<Result<AuthSession>> login(LoginParams params) =>
      guard(() => _remoteDataSource.login(params));

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) =>
      guard(() => _remoteDataSource.refresh(refreshToken));
}

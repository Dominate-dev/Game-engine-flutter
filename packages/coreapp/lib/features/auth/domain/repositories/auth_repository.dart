import '../../../../base/result.dart';
import '../entities/auth_session.dart';

abstract class AuthRepository {
  Future<Result<AuthSession>> login(LoginParams params);
  Future<Result<AuthSession>> refresh(String refreshToken);
}

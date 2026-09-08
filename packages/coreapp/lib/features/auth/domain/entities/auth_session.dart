import 'package:equatable/equatable.dart';

class AuthSession extends Equatable {
  const AuthSession({
    required this.token,
    this.refreshToken,
    this.userId,
  });

  final String token;
  final String? refreshToken;
  final String? userId;

  @override
  List<Object?> get props => [token, refreshToken, userId];
}

class LoginParams extends Equatable {
  const LoginParams({
    required this.userName,
    required this.password,
    this.socialMediaId = '',
  });

  final String userName;
  final String password;
  final String socialMediaId;

  @override
  List<Object?> get props => [userName, password, socialMediaId];
}

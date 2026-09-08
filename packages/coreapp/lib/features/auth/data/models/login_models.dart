class LoginRequestModel {
  const LoginRequestModel({
    required this.userName,
    required this.password,
    this.socialMediaId = '',
  });

  final String userName;
  final String password;
  final String socialMediaId;

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'password': password,
        'socialMediaId': socialMediaId,
      };
}

class LoginResponseModel {
  const LoginResponseModel({
    required this.token,
    this.refreshToken,
    this.userId,
  });

  final String token;
  final String? refreshToken;
  final String? userId;

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) {
    return LoginResponseModel(
      token: json['token']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString(),
      userId: json['userId']?.toString() ?? json['id']?.toString(),
    );
  }

  // Parses login payload from the standard API envelope (`data`) or root `token`.
  factory LoginResponseModel.fromEnvelope({
    required Object? data,
    required Map<String, dynamic> body,
  }) {
    if (data is Map) {
      return LoginResponseModel.fromJson(Map<String, dynamic>.from(data));
    }

    if (data is String && data.isNotEmpty) {
      return LoginResponseModel(token: data);
    }

    final rootToken = body['token']?.toString();
    if (rootToken != null && rootToken.isNotEmpty) {
      return LoginResponseModel(
        token: rootToken,
        refreshToken: body['refreshToken']?.toString(),
        userId: body['userId']?.toString() ?? body['id']?.toString(),
      );
    }

    return const LoginResponseModel(token: '');
  }
}

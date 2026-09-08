import '../../../../constants/api_endpoints.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../network/api_client.dart';
import '../../../../network/api_exception.dart';
import '../../../../network/api_response_handler.dart';
import '../../domain/entities/auth_session.dart';
import '../models/login_models.dart';

abstract class AuthRemoteDataSource {
  Future<AuthSession> login(LoginParams params);
  Future<AuthSession> refresh(String refreshToken);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  const AuthRemoteDataSourceImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<AuthSession> login(LoginParams params) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      data: LoginRequestModel(
        userName: params.userName,
        password: params.password,
        socialMediaId: params.socialMediaId,
      ).toJson(),
    );

    final apiResponse = ApiResponseHandler.parse<Object?>(response);
    ApiResponseHandler.ensureSuccess(apiResponse);

    final loginResponse = LoginResponseModel.fromEnvelope(
      data: apiResponse.data,
      body: ApiResponseHandler.mapBody(response),
    );

    if (loginResponse.token.isEmpty) {
      throw ApiException(message: AppStrings.current.loginMissingToken);
    }

    return AuthSession(
      token: loginResponse.token,
      refreshToken: loginResponse.refreshToken,
      userId: loginResponse.userId,
    );
  }

  // N2: same envelope contract as login() — GET api/Users/RefreshToken,
  // authenticated with the refresh token in place of the (expired) access
  // token, response parsed identically (token/refreshToken/userId).
  @override
  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.refreshToken,
      authTokenOverride: refreshToken,
      isAuthRefreshCall: true,
    );

    final apiResponse = ApiResponseHandler.parse<Object?>(response);
    ApiResponseHandler.ensureSuccess(apiResponse);

    final refreshResponse = LoginResponseModel.fromEnvelope(
      data: apiResponse.data,
      body: ApiResponseHandler.mapBody(response),
    );

    if (refreshResponse.token.isEmpty) {
      throw ApiException(message: AppStrings.current.unauthorized);
    }

    return AuthSession(
      token: refreshResponse.token,
      refreshToken: refreshResponse.refreshToken,
      userId: refreshResponse.userId,
    );
  }
}

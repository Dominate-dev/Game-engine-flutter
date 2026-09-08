import 'package:coreapp/coreapp.dart';

import '../../../../constants/play_game_endpoints.dart';
import '../../domain/entities/user_profile.dart';
import '../models/profile_models.dart';

abstract class ProfileRemoteDataSource {
  Future<UserProfile> getPublicProfile(int id);
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  const ProfileRemoteDataSourceImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<UserProfile> getPublicProfile(int id) async {
    // POST, not GET. The route accepts one method and answers a GET with
    // `405 Method Not Allowed` / `Allow: POST` — confirmed against both
    // backends. The id travels in the path, so there is no body to send.
    final response = await _apiClient.post<Map<String, dynamic>>(
      PlayGameEndpoints.publicProfile(id),
    );
    final apiResponse = ApiResponseHandler.parse<Object?>(response);
    ApiResponseHandler.ensureSuccess(apiResponse);
    return UserProfileModel.fromJson(JsonValue.asMap(apiResponse.data));
  }
}

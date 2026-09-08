import 'package:coreapp/coreapp.dart';

import '../../../../constants/play_game_endpoints.dart';

abstract class GameRemoteDataSource {
  // `GET api/Home/GenerateURL?type=…&code=…` — the shareable invite link.
  // query parameter is sent.
  Future<String> generateUrl({required int type, required String code});
}

class GameRemoteDataSourceImpl implements GameRemoteDataSource {
  const GameRemoteDataSourceImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<String> generateUrl({
    required int type,
    required String code,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      PlayGameEndpoints.generateUrl,
      query: <String, dynamic>{'type': type, 'code': code},
    );
    // The envelope wraps a bare String, not an object — `unwrap` is the
    // existing handler for a scalar `data`, and it raises the standard
    // ApiException when `succeeded` is false.
    return ApiResponseHandler.unwrap<String>(
      response,
      (data) => data?.toString() ?? '',
    );
  }
}

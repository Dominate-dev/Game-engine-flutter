import 'package:coreapp/coreapp.dart';

import '../../../../constants/play_game_endpoints.dart';
import '../../domain/entities/sticker_asset.dart';
import '../models/stickers_models.dart';

abstract class StickersRemoteDataSource {
  Future<StickerPage> getStickerGroups(StickerFilterParams params);

  Future<void> payStickerGroup(int id);
}

class StickersRemoteDataSourceImpl implements StickersRemoteDataSource {
  const StickersRemoteDataSourceImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<StickerPage> getStickerGroups(StickerFilterParams params) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      PlayGameEndpoints.stickerGroupsFilter,
      data: StickerFilterRequestModel(
        canUse: params.canUse,
        pageIndex: params.pageIndex,
        pageSize: params.pageSize,
      ).toJson(),
    );

    final apiResponse = ApiResponseHandler.parse<Object?>(response);
    ApiResponseHandler.ensureSuccess(apiResponse);

    final raw = apiResponse.data;
    final items = raw is List
        ? raw
            .map((item) => StickerAssetModel.fromJson(JsonValue.asMap(item)))
            .toList()
        : <StickerAsset>[];

    return StickerPage(
      items: items,
      pageIndex: params.pageIndex,
      pageSize: params.pageSize,
      fullCount: apiResponse.fullCount,
    );
  }

  @override
  Future<void> payStickerGroup(int id) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      PlayGameEndpoints.payStickerGroup(id),
    );
    final apiResponse = ApiResponseHandler.parse<Object?>(response);
    ApiResponseHandler.ensureSuccess(apiResponse);
  }
}

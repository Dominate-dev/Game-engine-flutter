import 'package:coreapp/coreapp.dart';

import '../../domain/entities/sticker_asset.dart';

class StickerFilterRequestModel {
  const StickerFilterRequestModel({
    this.canUse = false,
    this.pageIndex = 0,
    this.pageSize = 20,
  });

  final bool canUse;
  final int pageIndex;
  final int pageSize;

  Map<String, dynamic> toJson() => {
        'data': {'canUse': canUse},
        'pageIndex': pageIndex,
        'pageSize': pageSize,
      };
}

class StickerAssetModel {
  const StickerAssetModel._();

  static StickerAsset fromJson(Map<String, dynamic> json) {
    return StickerAsset(
      id: JsonValue.parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      price: JsonValue.parseInt(json['price']) ?? 0,
      isActive: json['isActive'] == true,
      type: JsonValue.parseInt(json['type']) ?? 0,
      isUserOrderAssets: json['isUserOrderAssetss'] == true,
      canUse: json['canUse'] == true,
      assets: _asAssets(json['assetss']),
    );
  }
}

List<StickerAsset> _asAssets(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => StickerAssetModel.fromJson(JsonValue.asMap(item)))
      .toList();
}

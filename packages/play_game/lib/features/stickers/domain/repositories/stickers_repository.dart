import 'package:coreapp/coreapp.dart';

import '../entities/sticker_asset.dart';

abstract class StickersRepository {
  Future<Result<StickerPage>> getStickerGroups(StickerFilterParams params);

  Future<Result<bool>> payStickerGroup(int id);
}

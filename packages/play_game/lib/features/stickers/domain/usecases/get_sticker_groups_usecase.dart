import 'package:coreapp/coreapp.dart';

import '../entities/sticker_asset.dart';
import '../repositories/stickers_repository.dart';

class GetStickerGroupsUseCase
    implements BaseUseCase<StickerPage, StickerFilterParams> {
  const GetStickerGroupsUseCase(this._repository);

  final StickersRepository _repository;

  @override
  Future<Result<StickerPage>> call(StickerFilterParams params) =>
      _repository.getStickerGroups(params);
}

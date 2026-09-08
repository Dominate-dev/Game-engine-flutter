import 'package:coreapp/coreapp.dart';

import '../../domain/entities/sticker_asset.dart';
import '../../domain/repositories/stickers_repository.dart';
import '../datasources/stickers_remote_datasource.dart';

class StickersRepositoryImpl with BaseRepository implements StickersRepository {
  const StickersRepositoryImpl(this._remoteDataSource);

  final StickersRemoteDataSource _remoteDataSource;

  @override
  Future<Result<StickerPage>> getStickerGroups(StickerFilterParams params) =>
      guard(() => _remoteDataSource.getStickerGroups(params));

  @override
  Future<Result<bool>> payStickerGroup(int id) =>
      guard(() async {
        await _remoteDataSource.payStickerGroup(id);
        return true;
      });
}

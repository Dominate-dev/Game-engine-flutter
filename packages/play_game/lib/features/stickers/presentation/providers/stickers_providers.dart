import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/stickers_remote_datasource.dart';
import '../../data/repositories/stickers_repository_impl.dart';
import '../../domain/entities/sticker_asset.dart';
import '../../domain/repositories/stickers_repository.dart';
import '../../domain/usecases/get_sticker_groups_usecase.dart';
import '../../domain/usecases/pay_sticker_group_usecase.dart';

final stickersRemoteDataSourceProvider =
    Provider<StickersRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return StickersRemoteDataSourceImpl(apiClient);
});

final stickersRepositoryProvider = Provider<StickersRepository>((ref) {
  final dataSource = ref.watch(stickersRemoteDataSourceProvider);
  return StickersRepositoryImpl(dataSource);
});

final getStickerGroupsUseCaseProvider = Provider<GetStickerGroupsUseCase>((ref) {
  final repository = ref.watch(stickersRepositoryProvider);
  return GetStickerGroupsUseCase(repository);
});

final payStickerGroupUseCaseProvider = Provider<PayStickerGroupUseCase>((ref) {
  final repository = ref.watch(stickersRepositoryProvider);
  return PayStickerGroupUseCase(repository);
});

// Prefetched sticker groups. Game controller loads this; the
// interaction dialog only reads it.
final stickerCatalogProvider = StateProvider<StickerCatalog?>((ref) => null);

Future<Result<StickerCatalog>> loadStickerCatalog(
  GetStickerGroupsUseCase useCase,
) async {
  const pageSize = 20;
  final owned = await useCase(
    const StickerFilterParams(canUse: true, pageSize: pageSize),
  );
  if (owned.isFailure) {
    return Result.failure(owned.failureOrNull!);
  }
  final buying = await useCase(
    const StickerFilterParams(canUse: false, pageSize: pageSize),
  );
  if (buying.isFailure) {
    return Result.failure(buying.failureOrNull!);
  }
  return Result.success(
    StickerCatalog(
      owned: owned.dataOrNull?.items ?? const [],
      buying: buying.dataOrNull?.items ?? const [],
    ),
  );
}

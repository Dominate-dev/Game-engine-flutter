import 'package:coreapp/coreapp.dart';

import '../repositories/stickers_repository.dart';

class PayStickerGroupUseCase implements BaseUseCase<bool, int> {
  const PayStickerGroupUseCase(this._repository);

  final StickersRepository _repository;

  @override
  Future<Result<bool>> call(int id) => _repository.payStickerGroup(id);
}

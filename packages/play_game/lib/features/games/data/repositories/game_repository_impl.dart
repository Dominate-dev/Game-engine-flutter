import 'package:coreapp/coreapp.dart';

import '../../domain/repositories/game_repository.dart';
import '../datasources/game_remote_datasource.dart';

class GameRepositoryImpl with BaseRepository implements GameRepository {
  const GameRepositoryImpl(this._remoteDataSource);

  final GameRemoteDataSource _remoteDataSource;

  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) =>
      guard(() => _remoteDataSource.generateUrl(type: type, code: code));
}

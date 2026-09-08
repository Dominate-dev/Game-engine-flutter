import 'package:coreapp/coreapp.dart';

abstract class GameRepository {
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  });
}

import 'result.dart';

abstract class BaseUseCase<T, Params> {
  const BaseUseCase();

  Future<Result<T>> call(Params params);
}

class NoParams {
  const NoParams();
}

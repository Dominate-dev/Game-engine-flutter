import 'package:dio/dio.dart';

import '../l10n/app_strings.dart';
import 'api_exception.dart';
import 'network_info.dart';

class ConnectivityInterceptor extends Interceptor {
  ConnectivityInterceptor(this._networkInfo);

  final NetworkInfo _networkInfo;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (!_networkInfo.isOnline) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const NoInternetException(),
          message: AppStrings.current.noInternet,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

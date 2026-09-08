import 'package:dio/dio.dart';

import '../l10n/app_strings.dart';
import '../network/api_exception.dart';
import '../network/models/api_response.dart';
import 'failure.dart';
import 'result.dart';

mixin BaseRepository {
  Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      final data = await action();
      return Result.success(data);
    } on ApiException catch (e) {
      return Result.failure(_mapApiException(e));
    } on NoInternetException {
      return Result.failure(NoInternetFailure());
    } on DioException catch (e) {
      if (e.error is NoInternetException) {
        return Result.failure(NoInternetFailure());
      }
      return Result.failure(_mapDioException(e));
    } catch (e) {
      return Result.failure(UnknownFailure(cause: e.toString()));
    }
  }

  Failure _mapApiException(ApiException e) {
    final statusCode = e.statusCode;
    if (statusCode == 401) {
      return UnauthorizedFailure(message: e.message);
    }
    return ServerFailure(message: e.message, statusCode: statusCode);
  }

  Failure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return TimeoutFailure();
      case DioExceptionType.connectionError:
        return NoInternetFailure();
      case DioExceptionType.badResponse:
        final responseData = e.response?.data;
        if (responseData is Map) {
          final apiResponse = ApiResponse<dynamic>.fromJson(
            Map<String, dynamic>.from(responseData),
          );
          if (!apiResponse.succeeded) {
            return _mapApiException(
              ApiException(
                message: apiResponse.displayMessage,
                statusCode: apiResponse.statusCode ?? e.response?.statusCode,
                error: apiResponse.error,
              ),
            );
          }
        }

        final statusCode = e.response?.statusCode;
        if (statusCode == 401) {
          return UnauthorizedFailure();
        }
        final message = responseData is Map
            ? responseData['message']?.toString() ??
                AppStrings.current.serverErrorShort
            : AppStrings.current.serverErrorShort;
        return ServerFailure(message: message, statusCode: statusCode);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return UnknownFailure(
          message: e.message ?? AppStrings.current.unknownError,
        );
    }
  }
}

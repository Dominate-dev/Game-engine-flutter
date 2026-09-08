import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'json_value.dart';
import 'models/api_response.dart';

// Parses the standard API envelope and throws [ApiException] when
// `succeeded == false`.
abstract final class ApiResponseHandler {
  static Map<String, dynamic> mapBody(Response<dynamic> response) =>
      JsonValue.asMap(response.data);

  static ApiResponse<T> parse<T>(
    Response<dynamic> response, {
    T Function(Object? json)? fromJsonT,
  }) {
    return ApiResponse.fromJson(mapBody(response), fromJsonT: fromJsonT);
  }

  static void ensureSuccess(ApiResponse<dynamic> response) {
    if (response.succeeded) {
      return;
    }

    throw ApiException(
      message: response.displayMessage,
      statusCode: response.statusCode,
      error: response.error,
    );
  }

  static T unwrap<T>(
    Response<dynamic> response,
    T Function(Object? data) mapper,
  ) {
    final apiResponse = parse<Object?>(response);
    ensureSuccess(apiResponse);
    return mapper(apiResponse.data);
  }

  static List<T> unwrapList<T>(
    Response<dynamic> response,
    T Function(Map<String, dynamic> json) itemMapper,
  ) {
    final apiResponse = parse<Object?>(response);
    ensureSuccess(apiResponse);

    final raw = apiResponse.data;
    if (raw is! List) {
      return [];
    }

    return raw
        .map(
          (item) => itemMapper(JsonValue.asMap(item)),
        )
        .toList();
  }
}

import 'package:equatable/equatable.dart';

import '../../l10n/app_strings.dart';
import '../json_value.dart';
import 'api_error_model.dart';

class ApiResponse<T> extends Equatable {
  const ApiResponse({
    this.data,
    this.fullCount,
    required this.succeeded,
    this.message,
    this.error,
  });

  final T? data;
  final int? fullCount;
  final bool succeeded;
  final String? message;
  final ApiErrorModel? error;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json, {
    T Function(Object? json)? fromJsonT,
  }) {
    final rawData = json['data'];
    T? parsedData;

    if (rawData != null && fromJsonT != null) {
      parsedData = fromJsonT(rawData);
    } else {
      parsedData = rawData as T?;
    }

    return ApiResponse<T>(
      data: parsedData,
      fullCount: JsonValue.parseInt(json['fullCount']),
      succeeded: json['succeeded'] == true,
      message: json['message']?.toString(),
      error: json['error'] is Map
          ? ApiErrorModel.fromJson(
              Map<String, dynamic>.from(json['error'] as Map),
            )
          : null,
    );
  }

  String get displayMessage {
    final errorMessage = error?.message?.trim();
    if (errorMessage != null && errorMessage.isNotEmpty) {
      return errorMessage;
    }

    final responseMessage = message?.trim();
    if (responseMessage != null && responseMessage.isNotEmpty) {
      return responseMessage;
    }

    return AppStrings.current.requestFailed;
  }

  int? get statusCode => error?.code;

  @override
  List<Object?> get props => [data, fullCount, succeeded, message, error];
}

import 'package:equatable/equatable.dart';

import '../json_value.dart';

class ApiErrorModel extends Equatable {
  const ApiErrorModel({
    this.message,
    this.stackTrace,
    this.sourceInfo,
    this.code,
  });

  final String? message;
  final String? stackTrace;
  final String? sourceInfo;
  final int? code;

  factory ApiErrorModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ApiErrorModel();
    }

    return ApiErrorModel(
      message: json['message']?.toString(),
      stackTrace: json['stackTrace']?.toString(),
      sourceInfo: json['sourceInfo']?.toString(),
      code: JsonValue.parseInt(json['code']),
    );
  }

  @override
  List<Object?> get props => [message, stackTrace, sourceInfo, code];
}

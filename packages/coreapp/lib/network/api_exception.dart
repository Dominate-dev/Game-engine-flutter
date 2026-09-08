import 'models/api_error_model.dart';

class NoInternetException implements Exception {
  const NoInternetException();
}

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.error,
  });

  final String message;
  final int? statusCode;
  final ApiErrorModel? error;

  @override
  String toString() => message;
}

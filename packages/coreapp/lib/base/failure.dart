import '../l10n/app_strings.dart';

abstract class Failure {
  const Failure({required this.message, this.statusCode, this.cause});

  final String message;
  final int? statusCode;

  // Raw diagnostic detail for logs only — never shown to the user.
  final String? cause;
}

class ServerFailure extends Failure {
  ServerFailure({
    String? message,
    super.statusCode,
  }) : super(message: message ?? AppStrings.current.serverError);
}

class NoInternetFailure extends Failure {
  NoInternetFailure({String? message})
      : super(message: message ?? AppStrings.current.noInternet);
}

class TimeoutFailure extends Failure {
  TimeoutFailure({String? message})
      : super(message: message ?? AppStrings.current.requestTimedOut);
}

class UnauthorizedFailure extends Failure {
  UnauthorizedFailure({
    String? message,
    super.statusCode = 401,
  }) : super(message: message ?? AppStrings.current.unauthorized);
}

class UnknownFailure extends Failure {
  UnknownFailure({
    String? message,
    super.statusCode,
    super.cause,
  }) : super(message: message ?? AppStrings.current.unknownError);
}

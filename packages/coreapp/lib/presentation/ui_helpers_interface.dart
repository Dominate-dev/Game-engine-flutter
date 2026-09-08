import 'dart:async';

import 'package:flutter/material.dart';

import '../base/failure.dart';
import '../base/result.dart';

enum ToastType { success, error, info, warning }

enum LoadingType { none, loader, connection }

enum ErrorType { none, dialog, toast, snack }

abstract class UIHelpersInterface {
  void showToast(String message, {ToastType type = ToastType.info});

  void showAppSnackBar(
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  });

  Future<T?> showAppDialog<T>({
    required Widget child,
    bool barrierDismissible = true,
  });

  Future<T?> showAppBottomSheet<T>({
    required Widget child,
    bool isScrollControlled = true,
    EdgeInsets? padding,
    bool showHandle = true,
    String? title,
    Color? backgroundColor,
  });

  Future<bool> checkInternetConnection();

  /// One entry point for every API call.
  ///
  /// Offline → does not call the API, returns no-internet [Failure].
  /// [loading] / [error] control UI. [onLoading], [onSuccess], [onError]
  /// are optional screen callbacks.
  Future<T?> runApi<T>(
    Future<Result<T>> Function() call, {
    LoadingType loading = LoadingType.loader,
    ErrorType error = ErrorType.dialog,
    VoidCallback? onLoading,
    FutureOr<void> Function(T data)? onSuccess,
    FutureOr<void> Function(Failure failure)? onError,
  });

  Future<bool> connectHub({
    String? url,
    bool showLoader = false,
    ErrorType error = ErrorType.dialog,
    VoidCallback? onSuccess,
    void Function(Failure failure)? onError,
  });

  Future<void> reconnectHub();

  void showLoader({String? message});

  void hideLoader();

  void showConnectionLoader();

  void hideConnectionLoader();
}

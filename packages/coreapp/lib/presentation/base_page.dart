import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_provider.dart';
import '../audio/audio_service.dart';
import '../base/failure.dart';
import '../base/result.dart';
import '../constants/api_endpoints.dart';
import '../di/providers.dart';
import '../l10n/app_strings.dart';
import '../network/network_info_provider.dart';
import '../signalr/signalr_provider.dart';
import '../signalr/signalr_status.dart';
import '../utils/app_logger.dart';
import 'base_dialog.dart';
import 'base_sheet.dart';
import 'providers/connection_loader_provider.dart';
import 'providers/loader_provider.dart';
import 'ui_helpers_interface.dart';
import 'widgets/app_text_view.dart';
import 'widgets/show_dialog_game.dart';

abstract class BaseState<T extends ConsumerStatefulWidget> extends ConsumerState<T>
    implements UIHelpersInterface {
  Widget buildPage(BuildContext context);

  /// Set `true` so this screen receives [onSignalRDisconnected] /
  bool get handleSignalRConnection => false;

  /// When `true`, a drop from online to offline shows a no-internet toast.
  bool get handleInternetConnection => true;

  /// Shared audio handle. Child screens that override [initState] must
  /// call `super.initState()` first. Do not stop music from [dispose] here.
  late final AudioService audio;

  bool _hubWasConnected = false;
  bool _sawHubDrop = false;
  bool _hubStatusSeeded = false;

  @override
  void initState() {
    super.initState();
    audio = ref.read(audioServiceProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (handleInternetConnection) {
      ref.listen<AsyncValue<bool>>(hasInternetProvider, (previous, next) {
        final wasOnline = previous?.valueOrNull;
        final isOnline = next.valueOrNull;
        if (wasOnline == true && isOnline == false) {
          _onInternetDropped();
        } else if (wasOnline == false && isOnline == true) {
          onInternetReconnected();
        }
      });
    }
    if (handleSignalRConnection) {
      ref.listen<AsyncValue<SignalRStatus>>(signalRStatusProvider, (
        previous,
        next,
      ) {
        final status = next.valueOrNull;
        if (status != null) {
          _onHubStatusChanged(status);
        }
      });
      if (!_hubStatusSeeded) {
        _hubStatusSeeded = true;
        final current =
            ref.read(signalRServiceProvider).checkConnectionStatus();
        if (current.isConnected) {
          _hubWasConnected = true;
        }
      }
    }
    return buildPage(context);
  }

  void _onInternetDropped() {
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    // The global [LoaderOverlay]'s connection loader is the single source of
    // truth for a hub drop. Losing internet while a hub session is live
    // already raises it, and this toast would be a second, competing report
    // of the same event on top of it. Screens with no hub session (the app
    // before a game is entered) keep the toast — nothing else speaks for
    // them there.
    if (_hubSessionActive) {
      return;
    }
    onInternetDisconnected();
  }

  /// A hub session exists and was not torn down on purpose.
  bool get _hubSessionActive {
    final signalR = ref.read(signalRServiceProvider);
    return signalR.checkConnectionStatus() != SignalRStatus.idle &&
        !signalR.isManuallyDisconnected;
  }

  /// Internet dropped while this screen is visible. Default: no-internet toast.
  void onInternetDisconnected() {
    showToast(AppStrings.current.noInternet, type: ToastType.error);
  }

  /// Internet is back. Override in screens that should refresh after a drop.
  void onInternetReconnected() {}

  void _onHubStatusChanged(SignalRStatus status) {
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (status.isConnected) {
      final isReconnect = _sawHubDrop;
      _hubWasConnected = true;
      _sawHubDrop = false;
      if (isReconnect) {
        onSignalRReconnected();
      }
      return;
    }

    if (_hubWasConnected) {
      _hubWasConnected = false;
      _sawHubDrop = true;
      onSignalRDisconnected();
    }
  }

  /// Hub dropped after it had been connected.
  /// The global [LoaderOverlay] already shows the connection loader.
  /// Override to run extra screen actions (pause timers, etc.).
  void onSignalRDisconnected() {}

  /// Hub is back after a drop.
  /// The global [LoaderOverlay] already hides the connection loader.
  /// Override to refresh UI/data — call `super` first if you add logic.
  void onSignalRReconnected() {}

  @override
  void showToast(String message, {ToastType type = ToastType.info}) {
    showAppSnackBar(
      message,
      type: type,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void showAppSnackBar(
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: AppTextView(message, color: Colors.white),
          backgroundColor: _colorForType(type),
          behavior: SnackBarBehavior.floating,
          duration: duration,
          margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  @override
  Future<R?> showAppDialog<R>({
    required Widget child,
    bool barrierDismissible = true,
  }) {
    // `mounted` alone is not enough: a popped route can stay mounted
    // through its exit transition, during which a queued caller can still
    // re-enter here. `isActive`, not `isCurrent`, since this screen is
    // legitimately non-current whenever a dialog (including one of its own)
    // is already open on top of it.
    if (!mounted || ModalRoute.of(context)?.isActive == false) {
      return Future<R?>.value();
    }
    return showDialog<R>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => child,
    );
  }

  Future<bool> showConfirmDialog({
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
  }) async {
    final result = await showAppDialog<bool>(
      child: ConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
      ),
    );
    return result ?? false;
  }

  @override
  Future<R?> showAppBottomSheet<R>({
    required Widget child,
    bool isScrollControlled = true,
    EdgeInsets? padding,
    bool showHandle = true,
    String? title,
    Color? backgroundColor,
  }) =>
      showModalBottomSheet<R>(
        context: context,
        isScrollControlled: isScrollControlled,
        backgroundColor: backgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => BaseSheet(
          title: title,
          padding: padding ?? const EdgeInsets.fromLTRB(20, 12, 20, 24),
          showHandle: showHandle,
          child: child,
        ),
      );

  @override
  Future<bool> checkInternetConnection() async =>
      ref.read(networkInfoProvider).isOnline;

  @override
  Future<T?> runApi<T>(
    Future<Result<T>> Function() call, {
    LoadingType loading = LoadingType.loader,
    ErrorType error = ErrorType.dialog,
    VoidCallback? onLoading,
    FutureOr<void> Function(T data)? onSuccess,
    FutureOr<void> Function(Failure failure)? onError,
  }) async {
    if (!await checkInternetConnection()) {
      return _fail<T>(NoInternetFailure(), error, onError);
    }

    onLoading?.call();
    _setLoading(loading, visible: true);
    Result<T> result;
    try {
      result = await call();
    } catch (e) {
      result = Result.failure(UnknownFailure(cause: e.toString()));
    } finally {
      _setLoading(loading, visible: false);
    }

    return result.when(
      success: (data) async {
        await _callOnSuccess<T>(data, onSuccess);
        return data;
      },
      failure: (failure) => _fail<T>(failure, error, onError),
    );
  }

  // The request already succeeded, so a throwing screen callback is a
  // diagnostic, not a user-facing API error: log it and let it stop here.
  Future<void> _callOnSuccess<T>(
    T data,
    FutureOr<void> Function(T data)? onSuccess,
  ) async {
    if (onSuccess == null) {
      return;
    }
    try {
      await onSuccess(data);
    } catch (e, stackTrace) {
      AppLogger.log(
        'onSuccess threw — $e\n$stackTrace',
        name: AppLogger.api,
      );
    }
  }

  Future<T?> _fail<T>(
    Failure failure,
    ErrorType error,
    FutureOr<void> Function(Failure failure)? onError,
  ) async {
    // N2: the server has rejected this token — stop sending it rather than
    // retrying it on every subsequent call until "Clear data" is tapped.
    // No redirect: there is no login screen to send the user to yet.
    if (failure is UnauthorizedFailure) {
      await ref.read(sharedPrefsProvider).clearAuth();
    }
    await _showError(failure, error);
    await onError?.call(failure);
    return null;
  }

  void _setLoading(LoadingType type, {required bool visible}) {
    switch (type) {
      case LoadingType.none:
        return;
      case LoadingType.loader:
        visible ? showLoader() : hideLoader();
      case LoadingType.connection:
        visible ? showConnectionLoader() : hideConnectionLoader();
    }
  }

  Future<void> _showError(Failure failure, ErrorType type) async {
    final message = failure.message.trim();
    // Log the raw cause when there is one; the message is what the user sees.
    final detail = failure.cause?.trim() ?? '';
    if (detail.isNotEmpty) {
      AppLogger.log(detail, name: AppLogger.api);
    } else if (message.isNotEmpty) {
      AppLogger.log(message, name: AppLogger.api);
    }
    if (message.isEmpty || !mounted) {
      return;
    }
    switch (type) {
      case ErrorType.none:
        return;
      case ErrorType.dialog:
        await showDialogGame(
          context,
          title: message,
          buttonText: AppStrings.current.confirm,
        );
      case ErrorType.toast:
        showToast(message, type: ToastType.error);
      case ErrorType.snack:
        showAppSnackBar(message, type: ToastType.error);
    }
  }

  @override
  Future<bool> connectHub({
    String? url,
    bool showLoader = false,
    // A1: defaults to the existing dialog presentation, so the debug
    // launcher is unchanged. An entry-path caller that must not put a modal
    // over the screen it is entering passes ErrorType.none — the service's
    // own failure/retry handling (status, backoff, ConnectionLoader) is
    // unaffected either way.
    ErrorType error = ErrorType.dialog,
    VoidCallback? onSuccess,
    void Function(Failure failure)? onError,
  }) async {
    final appStrings = AppStrings.current;
    final signalR = ref.read(signalRServiceProvider);
    final prefs = ref.read(sharedPrefsProvider);

    // Already up: nothing to report and nothing to do. This used to raise an
    // info Toast; a hub that is simply connected is not news to the player,
    // and the connection loader is the one place connection state is
    // surfaced. The early return, onSuccess and result are unchanged.
    if (signalR.isConnected) {
      onSuccess?.call();
      return true;
    }

    final connected = await runApi(
      () async {
        await signalR.connectIfNeeded(
          url: url ?? ApiEndpoints.signalRHubUrl,
          accessTokenFactory: () async => prefs.getToken() ?? '',
        );
        if (signalR.isConnected) {
          return Result.success(true);
        }
        return Result<bool>.failure(
          UnknownFailure(message: appStrings.hubConnectFailed),
        );
      },
      loading: showLoader ? LoadingType.loader : LoadingType.none,
      error: error,
      // A successful connect reports nothing to the player: the hub coming
      // up is not an event they asked about, and the connection loader
      // already covers the state that does matter. Only the caller's own
      // onSuccess runs, exactly as before. Failures are untouched — runApi's
      // `error` handling and hubConnectFailed still apply.
      onSuccess: (_) => onSuccess?.call(),
      onError: onError,
    );
    return connected == true;
  }

  @override
  Future<void> reconnectHub() =>
      ref.read(signalRServiceProvider).reconnect();

  @override
  void showLoader({String? message}) {
    ref.read(loaderVisibleProvider.notifier).show(message: message);
  }

  @override
  void hideLoader() {
    ref.read(loaderVisibleProvider.notifier).hide();
  }

  @override
  void showConnectionLoader() {
    ref.read(connectionLoaderVisibleProvider.notifier).show();
  }

  @override
  void hideConnectionLoader() {
    ref.read(connectionLoaderVisibleProvider.notifier).hide();
  }

  Color _colorForType(ToastType type) => switch (type) {
        ToastType.success => Colors.green.shade600,
        ToastType.error => Colors.red.shade600,
        ToastType.warning => Colors.orange.shade700,
        ToastType.info => Colors.blueGrey.shade700,
      };
}

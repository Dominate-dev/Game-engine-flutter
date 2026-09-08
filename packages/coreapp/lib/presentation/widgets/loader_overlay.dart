import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../signalr/signalr_provider.dart';
import '../../signalr/signalr_service.dart';
import '../../signalr/signalr_status.dart';
import '../providers/connection_loader_provider.dart';
import '../providers/loader_provider.dart';
import 'base_loader.dart';
import 'connection_loader.dart';

/// Wrap the app root with this once — e.g.:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => LoaderOverlay(child: child!),
///   home: const MyHomePage(),
/// )
/// ```
///
/// After that, any [BaseState] screen can call `showLoader()`/`hideLoader()`
/// and get a full-app overlay without managing its own loading widget.
///
/// Hub drops are owned here (not per-screen) so the connection loader
/// stays up across navigation until the hub is connected again.
class LoaderOverlay extends ConsumerStatefulWidget {
  const LoaderOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LoaderOverlay> createState() => _LoaderOverlayState();
}

class _LoaderOverlayState extends ConsumerState<LoaderOverlay> {
  /// Guards against a second Reconnect tap while one is still in flight.
  /// The service's own `_skipIfAlreadyConnected` only sees a connect once it
  /// is past its token await, so two taps in the same moment could both get
  /// through it.
  bool _reconnecting = false;

  @override
  Widget build(BuildContext context) {
    final loaderState = ref.watch(loaderVisibleProvider);
    final connectionState = ref.watch(connectionLoaderVisibleProvider);

    // Watched, not listened-to with a mirrored bool: the hub's own status is
    // the single source of truth for this loader, so the widget reads it
    // directly and rebuilds when it changes. This is the same provider the
    // previous implementation listened to — one stream, no extra listener.
    final service = ref.read(signalRServiceProvider);
    final status = ref.watch(signalRStatusProvider).valueOrNull ??
        service.checkConnectionStatus();

    final showConnection =
        connectionState.isVisible || _hubNeedsLoader(status, service);

    return Stack(
      children: [
        widget.child,
        if (loaderState.isVisible)
          Positioned.fill(
            child: BaseLoader(message: loaderState.message),
          ),
        if (showConnection)
          Positioned.fill(
            child: ConnectionLoader(
              onRetry: _reconnectHub,
            ),
          ),
      ],
    );
  }

  /// Whether a hub session exists and is not currently connected.
  ///
  /// Deliberately not gated on having been connected before: a hub that
  /// never came up is exactly as unusable as one that dropped, and the
  /// previous "only after a successful connect" rule left the very cases
  /// that need it most — a first connect that failed, or one aborted with no
  /// internet — with no loader at all.
  ///
  /// Two states are not a connection loss and stay out of the way:
  ///   * [SignalRStatus.idle] — nothing has ever tried to connect, so there
  ///     is no hub session to report on (this is the whole app before a game
  ///     is entered).
  ///   * a deliberate [SignalRService.disconnect] teardown, which reports
  ///     the same `disconnected` status a real drop does.
  ///
  /// Everything else — connecting, reconnecting, disconnected, no-internet,
  /// failed — keeps the loader up until the hub is genuinely connected.
  bool _hubNeedsLoader(SignalRStatus status, SignalRService service) {
    if (status.isConnected) {
      return false;
    }
    if (status == SignalRStatus.idle) {
      return false;
    }
    return !service.isManuallyDisconnected;
  }

  /// Performs the real hub connect, not a UI-state change.
  Future<void> _reconnectHub() async {
    if (_reconnecting) {
      return;
    }
    setState(() => _reconnecting = true);
    try {
      // Same call the automatic internet-recovery path makes: replay the
      // stored url, or fall back to the configured endpoint when a connect
      // aborted before storing one. The branch used to be duplicated here.
      await ref.read(signalRServiceProvider).recoverConnection();
    } finally {
      if (mounted) {
        setState(() => _reconnecting = false);
      }
    }
  }
}

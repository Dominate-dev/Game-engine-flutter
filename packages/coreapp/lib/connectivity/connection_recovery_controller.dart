import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../signalr/signalr_provider.dart';
import '../signalr/signalr_service.dart';
import '../utils/app_logger.dart';

typedef ConnectionRecoveredCallback = FutureOr<void> Function();

/// The missing link between "the hub reconnected" and "my game screen's
/// state is stale." [SignalRService] already re-attaches raw event
/// handlers after a drop (see `signalr_service.dart`'s `recoveredStream`),
/// but events that fired while offline are gone — a game notifier needs to
/// know "we just recovered" so it can re-fetch/re-sync its own state
/// (e.g. re-request current session/game status).
///
/// Usage in a game plugin's notifier `build()`:
///
/// ```dart
/// @override
/// MyState build() {
///   final unregister = ref
///       .read(connectionRecoveryControllerProvider)
///       .onRecovered(_resyncFromServer);
///   ref.onDispose(unregister);
///   return MyState.initial();
/// }
/// ```
class ConnectionRecoveryController {
  final _callbacks = <ConnectionRecoveredCallback>[];

  /// Registers [callback] to run every time the connection recovers.
  /// Returns a function that unregisters it — always call it from
  /// `ref.onDispose` in the caller's notifier/widget.
  VoidCallback onRecovered(ConnectionRecoveredCallback callback) {
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  Future<void> notifyRecovered() async {
    AppLogger.log(
      'ConnectionRecoveryController — notifying ${_callbacks.length} listener(s)',
    );
    // Copy first: a callback may register/unregister others mid-iteration.
    for (final callback in List<ConnectionRecoveredCallback>.of(_callbacks)) {
      try {
        await callback();
      } catch (error, stackTrace) {
        AppLogger.log(
          'ConnectionRecoveryController — listener threw: $error\n$stackTrace',
        );
      }
    }
  }
}

final connectionRecoveryControllerProvider =
    Provider<ConnectionRecoveryController>((ref) {
  final controller = ConnectionRecoveryController();
  final service = ref.watch(signalRServiceProvider);

  final subscription = service.recoveredStream.listen((_) {
    unawaited(controller.notifyRecovered());
  });

  ref.onDispose(subscription.cancel);
  return controller;
});

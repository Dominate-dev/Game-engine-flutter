import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../signalr/signalr_provider.dart';
import 'base_page.dart';

/// Hub payload helper — first SignalR argument as a JSON map, or positional
/// args such as PlayerLeft(playerId, gameId).
abstract final class HubEventPayload {
  static Map<String, dynamic>? mapFromArgs(List<Object?>? args) {
    if (args == null || args.isEmpty) {
      return null;
    }
    final map = _asMap(args.first);
    if (map != null) {
      return map;
    }
    // Use generic keys - each handler knows its own argument structure
    return {
      'arg0': args.first,
      if (args.length > 1) 'arg1': args[1],
      if (args.length > 2) 'arg2': args[2],
    };
  }

  static Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}

/// Native-style hub receive on a screen.
///
/// Override [listenHubEvents] and [onEventReceived]. Call `super.initState()`
/// first and `super.dispose()` last, same as other [BaseState] hooks.
mixin HubEventMixin<T extends ConsumerStatefulWidget> on BaseState<T> {
  final List<void Function()> _hubEventUnsubscribers = [];

  /// Event names this screen wants. Empty = no hub receive.
  List<String> get listenHubEvents => const [];

  /// Called when a [listenHubEvents] name arrives while this screen is mounted.
  /// This is the native `onEventReceived`.
  void onEventReceived(String name, Map<String, dynamic>? data) {}

  @override
  void initState() {
    super.initState();
    _bindHubEvents();
  }

  @override
  void dispose() {
    for (final unsubscribe in _hubEventUnsubscribers) {
      unsubscribe();
    }
    _hubEventUnsubscribers.clear();
    super.dispose();
  }

  void _bindHubEvents() {
    final events = listenHubEvents;
    if (events.isEmpty) {
      return;
    }
    final signalR = ref.read(signalRServiceProvider);
    for (final name in events) {
      _hubEventUnsubscribers.add(
        signalR.addEventListener(name, (args) {
          if (!mounted) {
            return;
          }
          onEventReceived(name, HubEventPayload.mapFromArgs(args));
        }),
      );
    }
  }
}

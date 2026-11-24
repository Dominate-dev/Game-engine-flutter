import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../signalr/signalr_provider.dart';
import 'base_page.dart';

/// Hub payload helper — first SignalR argument as a JSON map, or positional
/// args such as PlayerLeft(playerId, gameId).
abstract final class HubEventPayload {
  /// Key under which a map-first payload keeps the game id that came as its
  /// last argument (GameUpdated(game, gameId), NextQuestion(question, gameId)…).
  static const gameIdKey = '__gameId';

  // Game ids are server GUIDs. Player ids are numbers, so the shape alone
  // tells them apart.
  static final _gameIdPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool looksLikeGameId(Object? value) =>
      value is String && _gameIdPattern.hasMatch(value);

  static Map<String, dynamic>? mapFromArgs(List<Object?>? args) {
    if (args == null || args.isEmpty) {
      return null;
    }
    final map = _asMap(args.first);
    if (map != null) {
      if (args.length > 1 && looksLikeGameId(args.last)) {
        return {...map, gameIdKey: args.last};
      }
      return map;
    }
    // Generic keys, every argument kept: each handler knows its own argument
    // structure (CorrectAnswer has four).
    return {
      for (var i = 0; i < args.length; i++) 'arg$i': args[i],
    };
  }

  /// The game an event belongs to, when the payload says; null when it does
  /// not (GameFinished(bool), a bare player id…).
  static String? gameIdOf(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final tagged = data[gameIdKey];
    if (looksLikeGameId(tagged)) {
      return tagged as String;
    }
    // Positional payloads put the game id last.
    for (var i = data.length; i >= 0; i--) {
      final value = data['arg$i'];
      if (looksLikeGameId(value)) {
        return value as String;
      }
    }
    final gameId = data['gameId'];
    return looksLikeGameId(gameId) ? gameId as String : null;
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

import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/play_game_hub_events.dart';
import '../../domain/game_hub_event.dart';

/// App-lifetime Play hub subscriptions. Created once after the hub connects
/// (and kept across screens). Reconnect re-attaches the same handlers inside
/// [SignalRService] — this binding only re-subscribes if a listener was lost.
///
/// Screens receive events via [HubEventMixin.onEventReceived], not by
/// binding/unbinding here. Do not [unsubscribe] a name in
/// [PlayGameHubEvents.lifetimeEvents].
class PlayGameHubBindings {
  PlayGameHubBindings(this._signalR);

  final SignalRService _signalR;
  final _controller = StreamController<GameHubEvent>.broadcast();
  final _unsubscribers = <String, void Function()>{};

  GameHubEvent? lastEvent;

  Stream<GameHubEvent> get stream => _controller.stream;

  void bindAll() => bindEvents(PlayGameHubEvents.lifetimeEvents);

  void bindEvents(Iterable<String> eventNames) {
    var added = 0;
    for (final eventName in eventNames) {
      if (_unsubscribers.containsKey(eventName)) {
        continue;
      }
      _unsubscribers[eventName] = _signalR.addEventListener(
        eventName,
        (args) => _onHubEvent(eventName, args),
      );
      added++;
    }
    if (added == 0) {
      return;
    }
    _signalR.reattachEventHandlers();
    AppLogger.log(
      'PlayGameHubBindings — subscribed $added events ($eventNames)',
    );
  }

  void unbindEvents(Iterable<String> eventNames) {
    for (final eventName in eventNames) {
      _unsubscribers.remove(eventName)?.call();
    }
    AppLogger.log(
      'PlayGameHubBindings — unsubscribed $eventNames',
    );
  }

  void dispose() {
    for (final unsubscribe in _unsubscribers.values) {
      unsubscribe();
    }
    _unsubscribers.clear();
    _controller.close();
  }

  void _onHubEvent(String eventName, List<Object?>? args) {
    final event = GameHubEvent(
      name: eventName,
      data: HubEventPayload.mapFromArgs(args),
    );
    lastEvent = event;
    AppLogger.log(
      'Play hub event — $eventName | data: ${event.data}',
    );
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }
}

final playGameHubBindingsProvider = Provider<PlayGameHubBindings>((ref) {
  final signalR = ref.read(signalRServiceProvider);
  final bindings = PlayGameHubBindings(signalR);
  bindings.bindAll();

  final unregister = ref
      .read(connectionRecoveryControllerProvider)
      .onRecovered(bindings.bindAll);
  ref.onDispose(() {
    unregister();
    bindings.dispose();
  });
  return bindings;
});

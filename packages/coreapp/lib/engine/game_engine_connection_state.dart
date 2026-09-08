import '../signalr/signalr_status.dart';

// What the host is told about the hub connection.
//
// Deliberately smaller than SignalRStatus: the internal enum carries seven
// values, three of which describe *why* the engine is not connected
// (disconnectedNoInternet, failed, idle). The host acts on all three the same
// way — it is not connected, and the engine is already handling it — so they
// map onto one public value rather than becoming native branching the engine
// would then have to keep compatible forever.
enum GameEngineConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting;

  static GameEngineConnectionState fromStatus(SignalRStatus status) {
    return switch (status) {
      SignalRStatus.connected => GameEngineConnectionState.connected,
      SignalRStatus.connecting => GameEngineConnectionState.connecting,
      SignalRStatus.reconnecting => GameEngineConnectionState.reconnecting,
      // idle is "nothing has tried yet", failed is "an attempt did not land",
      // disconnectedNoInternet is a drop the service is already retrying —
      // all three are "not connected" as far as the host is concerned.
      SignalRStatus.idle ||
      SignalRStatus.failed ||
      SignalRStatus.disconnectedNoInternet ||
      SignalRStatus.disconnected =>
        GameEngineConnectionState.disconnected,
    };
  }

  // The wire name. Kept explicit rather than using `name` so a rename in Dart
  // cannot silently change what native receives.
  String get wireName => switch (this) {
        GameEngineConnectionState.disconnected => 'disconnected',
        GameEngineConnectionState.connecting => 'connecting',
        GameEngineConnectionState.connected => 'connected',
        GameEngineConnectionState.reconnecting => 'reconnecting',
      };
}

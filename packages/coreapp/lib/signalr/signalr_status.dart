enum SignalRStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  disconnectedNoInternet,
  failed,
}

extension SignalRStatusX on SignalRStatus {
  bool get isConnected => this == SignalRStatus.connected;

  bool get isBusy =>
      this == SignalRStatus.connecting || this == SignalRStatus.reconnecting;
}

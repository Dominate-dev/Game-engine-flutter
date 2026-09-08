import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Tracks reachability without pinging on every tap.
///
/// Airplane / no-interface updates instantly via [Connectivity]. Actual
/// internet is kept in a cache updated by [InternetConnection] in the
/// background so API/SignalR guards stay synchronous.
class NetworkInfo {
  NetworkInfo({
    InternetConnection? checker,
    Connectivity? connectivity,
  })  : _checker = checker ?? InternetConnection(),
        _connectivity = connectivity ?? Connectivity() {
    _internetSubscription = _checker.onStatusChange.listen((status) {
      _setConnected(status == InternetStatus.connected);
    });
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_applyConnectivity);
    unawaited(_seed());
  }

  final InternetConnection _checker;
  final Connectivity _connectivity;
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();
  StreamSubscription<InternetStatus>? _internetSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isConnected = true;
  bool _ready = false;

  /// Last known status — never waits on a network ping.
  bool get isOnline => _isConnected;

  /// Same as [isOnline]; kept as a Future for existing callers.
  Future<bool> get isConnected async => _isConnected;

  Stream<bool> get onStatusChange => _statusController.stream;

  void _setConnected(bool value) {
    if (_isConnected == value) {
      return;
    }
    _isConnected = value;
    _emitIfReady();
  }

  void _emitIfReady() {
    if (_ready && !_statusController.isClosed) {
      _statusController.add(_isConnected);
    }
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    if (_hasNoInterface(results)) {
      _setConnected(false);
    }
  }

  Future<void> _seed() async {
    final results = await _connectivity.checkConnectivity();
    if (_hasNoInterface(results)) {
      _isConnected = false;
    } else {
      _isConnected = await _checker.hasInternetAccess;
    }
    _ready = true;
    _emitIfReady();
  }

  static bool _hasNoInterface(List<ConnectivityResult> results) =>
      results.isEmpty ||
      results.every((result) => result == ConnectivityResult.none);

  void dispose() {
    _internetSubscription?.cancel();
    _internetSubscription = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _statusController.close();
  }
}

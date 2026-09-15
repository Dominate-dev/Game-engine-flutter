import 'dart:async';

import 'package:signalr_core/signalr_core.dart';

import '../constants/api_endpoints.dart';
import '../network/api_exception.dart';
import '../network/api_headers_builder.dart';
import '../network/network_info.dart';
import '../utils/app_logger.dart';
import 'signalr_http_client.dart';
import 'signalr_status.dart';

/// Builds the [HubConnection] for [url].
///
/// The one seam in this file. `connect()` used to construct the connection
/// inline, which made every path past it — `start()`, `onclose`,
/// `onreconnecting`, `onreconnected`, the reconnect backoff — reachable only
/// with a live socket. Production still gets the same builder; a test passes
/// its own so the same code runs against a fake.
///
/// [tokenFactory] is threaded through because the real builder needs it for
/// the WebSocket upgrade headers.
typedef HubConnectionFactory = HubConnection Function(
  String url,
  Future<String> Function() tokenFactory,
);

class SignalRService {
  SignalRService({
    ApiHeadersBuilder? headersBuilder,
    NetworkInfo? networkInfo,
    Future<String?> Function()? obtainRefreshedAccessToken,
    HubConnectionFactory? hubConnectionFactory,
    DateTime Function()? clock,
  })  : _headersBuilder = headersBuilder,
        _networkInfo = networkInfo,
        _obtainRefreshedAccessToken = obtainRefreshedAccessToken,
        _hubConnectionFactory = hubConnectionFactory,
        _now = clock ?? DateTime.now;

  final ApiHeadersBuilder? _headersBuilder;
  final NetworkInfo? _networkInfo;

  /// P1a: handed to [SignalRHttpClient] so an upgrade rejected with 401 can
  /// refresh through the same shared mechanism REST uses. Null leaves the
  /// pre-P1a behaviour untouched.
  final Future<String?> Function()? _obtainRefreshedAccessToken;

  /// T2 seam. Null in production, where [_buildHubConnection] falls back to
  /// the real builder below — so the shipped path is byte-for-byte what it
  /// was. A test supplies a [HubConnection] subclass instead, which is what
  /// makes start/onclose/onreconnecting/onreconnected and everything gated
  /// behind them reachable without a socket.
  final HubConnectionFactory? _hubConnectionFactory;

  // Wall clock, so time the device spent asleep still counts as silence.
  final DateTime Function() _now;
  DateTime? _lastServerMessageAt;

  HubConnection? _hubConnection;
  /// One hub dispatcher per event name. Re-attached after reconnect.
  final Map<String, void Function(List<Object?>?)> _subscribedEvents = {};
  final Map<String, List<void Function(List<Object?>?)>> _eventListeners = {};
  final Map<String, void Function()> _primaryUnsubscribers = {};
  final StreamController<SignalRStatus> _statusController =
      StreamController<SignalRStatus>.broadcast();

  /// Fires every time the hub goes from not-connected to connected (fresh
  /// connect, `onreconnected`, or a recovery after internet/app-lifecycle
  /// drop) — AFTER event handlers have been re-attached. Game plugins
  /// subscribe to this (usually via `ConnectionRecoveryController`, see
  /// `connectivity/connection_recovery_controller.dart`) to re-sync state
  /// that may have been missed while disconnected — do not rely on hub
  /// event handlers alone for that, since events fired while offline are
  /// simply lost.
  final StreamController<void> _recoveredController =
      StreamController<void>.broadcast();

  SignalRStatus _status = SignalRStatus.idle;
  String? _hubUrl;
  Future<String> Function()? _accessTokenFactory;
  Timer? _reconnectTimer;
  bool _manuallyDisconnected = false;
  bool _hasInternet = true;
  bool _isConnecting = false;
  bool _suppressAutoReconnect = false;
  bool _stoppingForNoInternet = false;

  int _retryDelayMs = 1000;
  static const _maxRetryDelayMs = 60000;

  Stream<SignalRStatus> get statusStream => _statusController.stream;

  Stream<void> get recoveredStream => _recoveredController.stream;

  /// Mirrors native [connectToHubIfNeeded] — no-op when already open or connecting.
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    if (_skipIfAlreadyConnected('connectIfNeeded()')) {
      return;
    }
    await connect(url: url, accessTokenFactory: accessTokenFactory);
  }

  Future<void> connect({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    if (_skipIfAlreadyConnected('connect()')) {
      return;
    }
    // Claimed synchronously, before any await — the same N4 pattern
    // `onWaitingShown` and `createPrivateGame` already use. This used to be
    // set further down, after `await tokenFactory()`, so two callers landing
    // together both passed the guard above and each built and started a
    // HubConnection. `_skipIfAlreadyConnected` reads this flag through
    // `hasLiveConnection`, so claiming it here is what makes the second
    // caller skip. Every early return below releases it.
    _isConnecting = true;

    final networkInfo = _networkInfo;
    if (networkInfo != null && !networkInfo.isOnline) {
      AppLogger.log('connect() aborted — no internet');
      _hasInternet = false;
      _isConnecting = false;
      _setStatus(SignalRStatus.disconnectedNoInternet);
      return;
    }

    final tokenFactory = _normalizeTokenFactory(accessTokenFactory);
    final String token;
    try {
      token = tokenFactory != null ? await tokenFactory() : '';
    } catch (error) {
      // A throwing token lookup must not leave the claim held, or every
      // later connect would be skipped as "already connecting".
      AppLogger.log('connect() aborted — token lookup failed: $error');
      _isConnecting = false;
      _setStatus(SignalRStatus.failed);
      return;
    }
    if (token.isEmpty) {
      AppLogger.log('connect() aborted — token is empty (native guard)');
      _isConnecting = false;
      _setStatus(SignalRStatus.failed);
      return;
    }

    AppLogger.log('connect() started → $url');
    AppLogger.log(
      'connect() — Bearer token ready (length: ${token.length})',
    );

    _hubUrl = url;
    _accessTokenFactory = tokenFactory;
    _manuallyDisconnected = false;
    // _isConnecting was already claimed above, before the token await.
    _setStatus(SignalRStatus.connecting);

    try {
      await _cleanupConnection();

      // The ApiHeadersBuilder guard moved into _buildHubConnection with the
      // builder it protects: it still throws the same StateError from inside
      // this same try, so production behaviour is unchanged, but a caller
      // that supplies its own connection no longer needs a headers builder
      // it will never use.
      final hub = _buildHubConnection(url, tokenFactory!);
      _hubConnection = hub;

      hub
        ..onclose((error) {
          if (!_isCurrentHub(hub, 'onclose')) {
            return;
          }
          _isConnecting = false;
          AppLogger.log(
            'Hub closed${error != null ? ' — error: $error' : ''}',
          );
          _setStatus(SignalRStatus.disconnected);
          if (!_suppressAutoReconnect && !_manuallyDisconnected) {
            _scheduleReconnect(initialDelayMs: 1000);
          }
        })
        ..onreconnecting((error) {
          if (!_isCurrentHub(hub, 'onreconnecting')) {
            return;
          }
          AppLogger.log(
            'Hub reconnecting${error != null ? ' — error: $error' : ''}',
          );
          _setStatus(SignalRStatus.reconnecting);
        })
        ..onreconnected((connectionId) {
          if (!_isCurrentHub(hub, 'onreconnected')) {
            return;
          }
          _isConnecting = false;
          _retryDelayMs = 1000;
          _heardFromServer();
          AppLogger.log('Hub reconnected — connectionId: $connectionId');
          _setStatus(SignalRStatus.connected);
          _reattachAllHandlers();
          _notifyRecovered();
        });

      await _hubConnection!.start()?.timeout(startTimeout);
      _isConnecting = false;
      _retryDelayMs = 1000;
      _heardFromServer();
      AppLogger.log(
        'Hub started — connectionId: ${_hubConnection?.connectionId}',
      );
      _setStatus(SignalRStatus.connected);
      _reattachAllHandlers();
      _notifyRecovered();
    } catch (error, stackTrace) {
      _isConnecting = false;
      AppLogger.log('connect() failed — $error');
      AppLogger.log('Stack trace: $stackTrace');
      await _cleanupConnection();
      if (error is NoInternetException) {
        _hasInternet = false;
        _setStatus(SignalRStatus.disconnectedNoInternet);
        return;
      }
      _setStatus(SignalRStatus.failed);
      _scheduleReconnect(useBackoff: true);
    }
  }

  Future<void> disconnect({
    bool manual = true,
    SignalRStatus status = SignalRStatus.disconnected,
  }) async {
    AppLogger.log('disconnect() — manual: $manual');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _manuallyDisconnected = manual;
    _suppressAutoReconnect = true;
    final hub = _hubConnection;

    try {
      await hub?.stop().timeout(stopTimeout);
    } on TimeoutException {
      AppLogger.log('disconnect() — stop timed out, connection abandoned');
    } finally {
      _suppressAutoReconnect = false;
      _isConnecting = false;
      if (identical(_hubConnection, hub)) {
        _hubConnection = null;
      }
      _setStatus(status);
    }
  }

  /// Reconnect using the last hub URL / token. No-op if already live.
  Future<void> reconnect() async {
    if (_hubUrl == null) {
      AppLogger.log('reconnect() skipped — no stored hub url');
      return;
    }
    _manuallyDisconnected = false;
    await connectIfNeeded(
      url: _hubUrl!,
      accessTokenFactory: _accessTokenFactory,
    );
  }

  /// Reconnect, falling back to the configured endpoint when no url is stored.
  ///
  /// [reconnect] replays `_hubUrl`, which [connect] assigns only after its
  /// no-internet and empty-token guards have both passed. A first connect
  /// attempted while offline therefore returns with `_hubUrl` still null, and
  /// every path gated on it — internet recovery included — had nothing to
  /// replay, leaving the session down until someone pressed Reconnect.
  ///
  /// This is the one place that fallback lives; the automatic internet-
  /// recovery paths and the connection loader's Reconnect button all route
  /// through it rather than each carrying their own copy.
  ///
  /// Deliberately does not consult [_manuallyDisconnected]: calling this *is*
  /// the request to come back up. The automatic callers check that flag
  /// before they get here, so a manual disconnect is still never undone on
  /// its own.
  Future<void> recoverConnection() async {
    // An explicit request outranks an in-flight claim.
    //
    // Every path below eventually reaches `_skipIfAlreadyConnected`, which
    // returns early whenever `hasLiveConnection` is true — and that includes
    // `connecting`/`reconnecting`. A claim left behind by an attempt that
    // never completed therefore made this method, the only thing the player
    // can actually press, do nothing at all. Discarding it first is what
    // makes the button mean something in that state.
    //
    // A genuinely connected hub is untouched: the guard is `!isConnected`,
    // so nothing is torn down, and the `reconnect()` below still skips as it
    // always did. The automatic callers never arrive here holding a live
    // claim either — `_reconnectAfterInternetRestored` returns on
    // `hasLiveConnection` before calling this — so automatic reconnect
    // behaviour is unchanged.
    if (!isConnected && hasLiveConnection) {
      AppLogger.log(
        'recoverConnection() — discarding a stale connect attempt '
        '(status: ${_status.name})',
      );
      _isConnecting = false;
      await _cleanupConnection();
    }
    if (_hubUrl != null) {
      await reconnect();
      return;
    }
    final headersBuilder = _headersBuilder;
    if (headersBuilder == null) {
      AppLogger.log('recoverConnection() skipped — no headers builder');
      return;
    }
    AppLogger.log('recoverConnection() — no stored url, using endpoint');
    _manuallyDisconnected = false;
    await connectIfNeeded(
      url: ApiEndpoints.signalRHubUrl,
      accessTokenFactory: () async => headersBuilder.authToken,
    );
  }

  /// The injected factory, or the real builder.
  ///
  /// The builder body is unchanged from when it sat inline in `connect()`.
  HubConnection _buildHubConnection(
    String url,
    Future<String> Function() tokenFactory,
  ) {
    final factory = _hubConnectionFactory;
    if (factory != null) {
      return factory(url, tokenFactory);
    }
    // connect() has already thrown if this is null; the local re-check is
    // what promotes the nullable field now that the builder lives here.
    final headersBuilder = _headersBuilder;
    if (headersBuilder == null) {
      throw StateError(
        'SignalRService requires ApiHeadersBuilder for native header parity',
      );
    }
    // Native WebSocketHubConnectionP2 sends Bearer + Request-Token + device
    // headers on the WebSocket upgrade. Do not use accessTokenFactory —
    // negotiate replaces it and adds ?access_token= to the WebSocket URL,
    // which this server rejects (close 1002). Auth + native headers come
    // from [SignalRHttpClient].
    void logging(LogLevel level, String message) =>
        AppLogger.log('[hub] $message');
    final connection = HttpConnection(
      url: url,
      options: HttpConnectionOptions(
        transport: HttpTransportType.webSockets,
        skipNegotiation: true,
        client: SignalRHttpClient(
          headersBuilder: headersBuilder,
          tokenProvider: tokenFactory,
          networkInfo: _networkInfo,
          obtainRefreshedAccessToken: _obtainRefreshedAccessToken,
        ),
        logging: logging,
      ),
    );
    // What HubConnectionBuilder.build() does with these same options, spelled
    // out so the connection's receive callback can be observed.
    final hub = HubConnection(
      connection: connection,
      logging: logging,
      protocol: JsonHubProtocol(),
      reconnectPolicy: DefaultReconnectPolicy(
        retryDelays: const [0, 2000, 5000, 10000, 15000, 30000],
      ),
    );
    // Every frame the server sends, keep-alive pings included.
    final receive = connection.onreceive;
    connection.onreceive = (data) {
      if (identical(hub, _hubConnection)) {
        _heardFromServer();
      }
      receive?.call(data);
    };
    return hub;
  }

  /// How long one `start()` may take before the attempt is abandoned.
  ///
  /// `HubConnection.start()` carries no timeout of its own, so a socket that
  /// died silently while the device slept leaves it awaiting forever. That
  /// matters beyond the one attempt: `_isConnecting` is released only after
  /// `start()` returns, and it is what `hasLiveConnection` reports, so a
  /// stalled attempt also silences [onAppResumed], the Reconnect button and
  /// [_scheduleReconnect] — all three skip while a connect looks live.
  ///
  /// Bounding it routes a stall into the existing catch below, which clears
  /// the claim, reports [SignalRStatus.failed] and schedules the usual
  /// backoff retry. No new state and no new path; the stall simply becomes a
  /// failure like any other.
  static const startTimeout = Duration(seconds: 30);

  // signalr_core 1.1.2 can leave stop() pending forever when it lands on an
  // in-flight start; past this the old connection is abandoned instead.
  static const stopTimeout = Duration(seconds: 5);

  SignalRStatus checkConnectionStatus() => _status;

  /// True after a deliberate [disconnect] teardown, until the next
  /// connect/reconnect clears it.
  ///
  /// A real drop and an intentional shutdown both report
  /// [SignalRStatus.disconnected], so status alone cannot tell them apart —
  /// this is what the connection loader uses to stay out of the way of a
  /// shutdown the app asked for.
  bool get isManuallyDisconnected => _manuallyDisconnected;

  /// True once a connect has stored a hub url, i.e. [reconnect] has
  /// something to replay. False before the first connect ever reached that
  /// point — a connect aborted on no-internet or an empty token never got
  /// far enough to store one.
  bool get hasStoredHubSession => _hubUrl != null;

  bool get isConnected =>
      _hubState == HubConnectionState.connected;

  bool get isConnecting =>
      _isConnecting ||
      _hubState == HubConnectionState.connecting ||
      _hubState == HubConnectionState.reconnecting;

  /// Socket is already up, or a connect/reconnect is in flight.
  bool get hasLiveConnection => isConnected || isConnecting;

  HubConnectionState? get _hubState => _hubConnection?.state;

  bool _skipIfAlreadyConnected(String source) {
    if (!hasLiveConnection) {
      return false;
    }
    if (isConnected && _status != SignalRStatus.connected) {
      // A live hub whose status says otherwise. This was the one transition
      // to `connected` that skipped `_reattachAllHandlers()` and
      // `_notifyRecovered()`: the Reconnect button reached it whenever the
      // popup was showing over a working connection, so the status was
      // corrected and the popup came down, but no recovery was announced —
      // `GameController.onRecovered` never sent CheckPlayerGame, and events
      // missed while the status was down stayed lost. It is a recovery, so
      // it is announced through the same stream `onreconnected` uses.
      //
      // Not while a `connect()` is still in flight: that call announces its
      // own success when `start()` returns, and announcing here as well would
      // resynchronise the game twice for one connection.
      _setStatus(SignalRStatus.connected);
      if (!_isConnecting) {
        _reattachAllHandlers();
        _notifyRecovered();
      }
    }
    AppLogger.log(
      '$source skipped — already ${isConnected ? 'connected' : 'connecting'}',
    );
    return true;
  }

  bool isSubscribed(String eventName) =>
      _subscribedEvents.containsKey(eventName);

  /// Registers [handler] for [eventName] without replacing other listeners.
  /// Returns an unregister callback — use this for screen-scoped events.
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    AppLogger.log('addEventListener() — event: $eventName');
    _connectIfSubscribeNeedsHub();

    final listeners = _eventListeners.putIfAbsent(eventName, () => []);
    listeners.add(handler);
    _ensureDispatcher(eventName);

    var removed = false;
    return () {
      if (removed) {
        return;
      }
      removed = true;
      _removeEventListener(eventName, handler);
    };
  }

  /// Duplicate-safe primary handler: replaces the previous [subscribe]
  /// listener for this event, but does not drop [addEventListener] listeners.
  void subscribe(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    AppLogger.log('subscribe() — event: $eventName');
    _primaryUnsubscribers.remove(eventName)?.call();
    _primaryUnsubscribers[eventName] = addEventListener(eventName, handler);
  }

  void unsubscribe(String eventName) {
    if (!_primaryUnsubscribers.containsKey(eventName) &&
        !_eventListeners.containsKey(eventName)) {
      AppLogger.log('unsubscribe() skipped — not subscribed: $eventName');
      return;
    }

    AppLogger.log('unsubscribe() — event: $eventName');
    _primaryUnsubscribers.remove(eventName)?.call();
  }

  void unsubscribeAll() {
    final events = {
      ..._subscribedEvents.keys,
      ..._eventListeners.keys,
      ..._primaryUnsubscribers.keys,
    };
    AppLogger.log('unsubscribeAll() — events: $events');
    _primaryUnsubscribers.clear();
    _eventListeners.clear();
    for (final eventName in events) {
      _hubConnection?.off(eventName);
    }
    _subscribedEvents.clear();
  }

  void _connectIfSubscribeNeedsHub() {
    if (!hasLiveConnection && _hubUrl != null) {
      AppLogger.log(
        'subscribe() — hub not ready, connectIfNeeded will run',
      );
      unawaited(
        connectIfNeeded(
          url: _hubUrl!,
          accessTokenFactory: _accessTokenFactory,
        ),
      );
    }
  }

  void _ensureDispatcher(String eventName) {
    if (_subscribedEvents.containsKey(eventName)) {
      return;
    }

    void dispatcher(List<Object?>? args) {
      _heardFromServer();
      AppLogger.log('Event received — $eventName | args: $args');
      final listeners = List<void Function(List<Object?>?)>.from(
        _eventListeners[eventName] ?? const [],
      );
      for (final listener in listeners) {
        listener(args);
      }
    }

    _subscribedEvents[eventName] = dispatcher;
    _hubConnection?.on(eventName, dispatcher);
    AppLogger.log(
      'Handler registered for: $eventName (hub connected: $isConnected)',
    );
  }

  void _removeEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    final listeners = _eventListeners[eventName];
    listeners?.remove(handler);
    if (listeners != null && listeners.isNotEmpty) {
      return;
    }
    _eventListeners.remove(eventName);
    _primaryUnsubscribers.remove(eventName);
    final dispatcher = _subscribedEvents.remove(eventName);
    if (dispatcher != null) {
      _hubConnection?.off(eventName, method: dispatcher);
    }
  }

  // Returns whether the call was dispatched. A disconnected hub is a
  // skip, not a throw; a drop mid-invocation still propagates as before.
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    if (!isConnected) {
      AppLogger.log(
        'invoke() skipped — not connected (method: $methodName)',
      );
      if (!hasLiveConnection && _hubUrl != null) {
        unawaited(
          connectIfNeeded(
            url: _hubUrl!,
            accessTokenFactory: _accessTokenFactory,
          ),
        );
      }
      return false;
    }

    AppLogger.log('invoke() — method: $methodName | args: $args');
    await _hubConnection!.invoke(methodName, args: args);
    AppLogger.log('invoke() completed — method: $methodName');
    return true;
  }

  void onInternetStatusChanged(bool hasInternet) {
    AppLogger.log(
      'Internet status changed — hasInternet: $hasInternet',
    );
    final hadInternet = _hasInternet;
    _hasInternet = hasInternet;

    if (!hasInternet) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(_stopHubForNoInternet());
      return;
    }

    if (hadInternet) {
      return;
    }
    _reconnectAfterInternetRestored();
  }

  void onAppResumed() {
    AppLogger.log('App resumed — status: ${_status.name}');
    if (!_manuallyDisconnected && _hubUrl != null && !hasLiveConnection) {
      AppLogger.log('App resumed — attempting reconnect');
      unawaited(reconnect());
    }
    // A socket that died while the app was away still reports connected
    // until signalr_core's own server timeout fires, and that timer may not
    // have run in the background.
    if (_serverWentSilent) {
      AppLogger.log(
        'App resumed — no server message within the server timeout, '
        'replacing the connection',
      );
      unawaited(_replaceSilentConnection());
    }
  }

  bool get _serverWentSilent {
    final hub = _hubConnection;
    final heard = _lastServerMessageAt;
    if (hub == null || heard == null || !isConnected || _isConnecting) {
      return false;
    }
    return _now().difference(heard) >
        Duration(milliseconds: hub.serverTimeoutInMilliseconds);
  }

  Future<void> _replaceSilentConnection() async {
    await _cleanupConnection();
    await reconnect();
  }

  void _heardFromServer() => _lastServerMessageAt = _now();

  void onAppPaused() {
    AppLogger.log('App paused');
  }

  Future<void> dispose() async {
    AppLogger.log('dispose()');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _statusController.close();
    await _recoveredController.close();
    await _cleanupConnection();
  }

  Future<void> _cleanupConnection() async {
    final hub = _hubConnection;
    if (hub == null) {
      return;
    }

    _suppressAutoReconnect = true;
    try {
      AppLogger.log('Cleaning up previous hub connection');
      await hub.stop().timeout(stopTimeout);
    } catch (error) {
      AppLogger.log('Cleanup error — $error');
    } finally {
      _suppressAutoReconnect = false;
      if (identical(_hubConnection, hub)) {
        _hubConnection = null;
      }
    }
  }

  bool _isCurrentHub(HubConnection hub, String event) {
    if (identical(hub, _hubConnection)) {
      return true;
    }
    AppLogger.log('$event ignored — from an abandoned hub connection');
    return false;
  }

  void _reattachAllHandlers() {
    if (_subscribedEvents.isEmpty) {
      AppLogger.log('Reattach handlers — none registered');
      return;
    }

    AppLogger.log(
      'Reattach handlers — events: ${_subscribedEvents.keys.toList()}',
    );
    for (final entry in _subscribedEvents.entries) {
      _hubConnection?.off(entry.key);
      _hubConnection?.on(entry.key, entry.value);
    }
  }

  /// Re-bind stored event dispatchers on the current hub.
  /// Safe to call after reconnect; does not add duplicate Dart listeners.
  void reattachEventHandlers() => _reattachAllHandlers();

  void _notifyRecovered() {
    if (!_recoveredController.isClosed) {
      _recoveredController.add(null);
    }
  }

  void _scheduleReconnect({
    int initialDelayMs = 5000,
    bool useBackoff = false,
  }) {
    if (_suppressAutoReconnect ||
        _manuallyDisconnected ||
        !_hasInternet ||
        _hubUrl == null ||
        hasLiveConnection) {
      AppLogger.log(
        'Reconnect skipped — suppress: $_suppressAutoReconnect, '
        'manual: $_manuallyDisconnected, internet: $_hasInternet, '
        'live: $hasLiveConnection',
      );
      return;
    }

    final delayMs = useBackoff ? _retryDelayMs : initialDelayMs;
    AppLogger.log('Scheduling reconnect in ${delayMs}ms');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      AppLogger.log('Reconnect timer fired');
      if (useBackoff && _retryDelayMs < _maxRetryDelayMs) {
        _retryDelayMs *= 2;
      }
      unawaited(reconnect());
    });
  }

  Future<void> _stopHubForNoInternet() async {
    final hub = _hubConnection;
    if (hub == null) {
      _setStatus(SignalRStatus.disconnectedNoInternet);
      return;
    }

    AppLogger.log('Internet lost — stopping hub');
    _stoppingForNoInternet = true;
    _suppressAutoReconnect = true;
    try {
      await hub.stop().timeout(stopTimeout);
    } catch (error) {
      AppLogger.log('Stop hub on no-internet — $error');
    } finally {
      _suppressAutoReconnect = false;
      _isConnecting = false;
      if (identical(_hubConnection, hub)) {
        _hubConnection = null;
      }
      _stoppingForNoInternet = false;
      _setStatus(SignalRStatus.disconnectedNoInternet);
      // The `_hubUrl != null` condition that used to sit here is now inside
      // recoverConnection(), which falls back to the endpoint instead of
      // giving up. The race this branch exists for — internet returning
      // while this stop was still running, so _reconnectAfterInternetRestored
      // bailed on _stoppingForNoInternet — is unchanged.
      if (_hasInternet && !_manuallyDisconnected) {
        AppLogger.log('Internet restored during hub stop — reconnecting');
        unawaited(recoverConnection());
      }
    }
  }

  void _reconnectAfterInternetRestored() {
    // A hub the app deliberately shut down stays shut down.
    if (_manuallyDisconnected) {
      return;
    }
    if (_stoppingForNoInternet) {
      AppLogger.log('Internet restored — waiting for hub stop to finish');
      return;
    }
    if (hasLiveConnection) {
      AppLogger.log('Internet restored — hub still live, skip reconnect');
      return;
    }
    // No `_hubUrl == null` bail: recoverConnection() falls back to the
    // configured endpoint, so a session whose first connect aborted while
    // offline now comes back on its own instead of waiting for a tap.
    AppLogger.log('Internet restored — attempting reconnect');
    unawaited(recoverConnection());
  }

  void _setStatus(SignalRStatus status) {
    if (_status != status) {
      AppLogger.log('Status: ${_status.name} → ${status.name}');
    }
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Native passes `"Bearer $token"` to WebSocketHubConnectionP2; signalr_core
  /// adds Bearer itself — strip prefix if present.
  Future<String> Function()? _normalizeTokenFactory(
    Future<String> Function()? factory,
  ) {
    if (factory == null) {
      return null;
    }

    return () async {
      final raw = await factory();
      if (raw.startsWith('Bearer ')) {
        return raw.substring(7);
      }
      return raw;
    };
  }
}

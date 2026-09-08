# Task 04 — Global SignalR Handler

Depends on: Task 00, 02 (uses `NetworkInfo`/`hasInternetProvider` for reconnect logic).

This is the most important task in the series — get this stable before moving on.

## Prompt for Cursor

```
Build ONE global SignalR handler used everywhere in the app. Never let any
other file instantiate HubConnection directly.

Inside lib/core/signalr/, create three files:

1. signalr_status.dart
   - enum SignalRStatus { idle, connecting, connected, reconnecting,
     disconnected, disconnectedNoInternet, failed }
   - extension SignalRStatusX with `isConnected` (true only when
     .connected) and `isBusy` (true for .connecting or .reconnecting)

2. signalr_service.dart
   - Class `SignalRService` (plain Dart class, no Riverpod inside it).
   - Uses package:signalr_core (HubConnectionBuilder, HubConnection,
     HttpConnectionOptions, HubConnectionState).
   - Private fields: `HubConnection? _hubConnection`,
     `Map<String, void Function(List<Object?>?)> _subscribedEvents`,
     a broadcast StreamController<SignalRStatus> for status,
     current `_status`, `_hubUrl`, `_accessTokenFactory`
     (nullable Future<String> Function()?), a reconnect Timer,
     `_manuallyDisconnected` bool, `_hasInternet` bool defaulting true.

   Public API (implement exactly these, other files depend on these
   names):

   - `Stream<SignalRStatus> get statusStream`
   - `Future<void> connect({required String url,
     Future<String> Function()? accessTokenFactory})`
     -- guard: if already connected or connecting, return immediately
        (no stacked connection attempts)
     -- build the HubConnection with
        .withAutomaticReconnect(retryDelays: [0, 2000, 5000, 10000, 15000, 30000])
     -- wire onclose -> set status disconnected + schedule a fallback
        reconnect timer
     -- wire onreconnecting -> set status reconnecting
     -- wire onreconnected -> set status connected + re-attach every
        tracked event handler (see _reattachAllHandlers below)
     -- on success: status connected, re-attach handlers
     -- on thrown error during start(): status failed, schedule reconnect
   - `Future<void> disconnect({bool manual = true})` — cancels reconnect
     timer, stops the hub, sets manuallyDisconnected flag, status
     disconnected
   - `SignalRStatus checkConnectionStatus()` — returns current status
     (do not recompute from _hubConnection.state, use the tracked field)
   - `bool get isConnected` — true only if
     `_hubConnection?.state == HubConnectionState.connected`
   - `bool isSubscribed(String eventName)` — checks
     `_subscribedEvents.containsKey`
   - `void subscribe(String eventName, void Function(List<Object?>?) handler)`
     -- if isSubscribed(eventName) is already true, call
        `_hubConnection?.off(eventName)` first so you never stack two
        listeners for the same event name
     -- store the handler in the map, then call
        `_hubConnection?.on(eventName, handler)`
     -- IMPORTANT: this must be safe to call from a widget's build/initState
        even before connect() has been called yet — just record it in the
        map, it'll get attached for real once connect() succeeds (see
        _reattachAllHandlers)
   - `void unsubscribe(String eventName)` — no-op if not subscribed,
     otherwise `off()` the hub and remove from the map
   - `void unsubscribeAll()` — off() every tracked event and clear the map
   - `void _reattachAllHandlers()` (private) — loops the map and calls
     `_hubConnection?.on(event, handler)` for each; call this after every
     successful connect and every onreconnected
   - `Future<void> invoke(String methodName, {List<Object?>? args})` — no-op
     if not connected, else `_hubConnection?.invoke(...)`
   - `void onInternetStatusChanged(bool hasInternet)` — called from outside
     whenever real internet reachability changes (see signalr_provider.dart
     below). If internet just went false: cancel reconnect timer, set
     status disconnectedNoInternet, return. If internet just came back true
     AND we weren't manually disconnected AND we have a stored _hubUrl AND
     current status isn't already connected: call connect() again with the
     stored url/tokenFactory.
   - `void onAppResumed()` — if not manually disconnected and we have a
     stored url and status isn't connected, call connect() again
   - `void onAppPaused()` — left as an empty hook (SignalR is allowed to
     drop naturally in background; override later if you want to
     force-disconnect to save battery)
   - `void dispose()` — cancel reconnect timer, close the status stream
     controller, stop the hub connection

   Private helper `_scheduleReconnect()`: if manuallyDisconnected or no
   internet or no stored url, do nothing; otherwise cancel any existing
   timer and start a new 5-second Timer that calls connect() again with
   the stored url/tokenFactory.

3. signalr_provider.dart
   - `final signalRServiceProvider = Provider<SignalRService>((ref) {...})`
     that constructs one SignalRService, subscribes to
     `ref.watch(networkInfoProvider).onStatusChange` from
     core/network/network_info_provider.dart and forwards every event into
     `service.onInternetStatusChanged`, cancels that subscription and
     disposes the service in `ref.onDispose`.
   - `final signalRStatusProvider = StreamProvider<SignalRStatus>((ref) {...})`
     that watches signalRServiceProvider and returns its statusStream —
     this is what widgets watch reactively.

Also create lib/core/utils/app_lifecycle_observer.dart:
   - `class AppLifecycleObserver extends WidgetsBindingObserver` taking a
     `SignalRService` in its constructor, overriding
     `didChangeAppLifecycleState` to call `signalRService.onAppResumed()`
     on AppLifecycleState.resumed and `signalRService.onAppPaused()` on
     .paused/.detached.

Do not add authentication requirements to connect() beyond the optional
accessTokenFactory parameter — no login flow exists yet, it may be omitted
entirely when calling connect().
```

## Acceptance criteria (test these manually)
- [ ] Calling `subscribe()` twice on the same event name never results in a handler firing twice per message
- [ ] `unsubscribe()` on an event that was never subscribed does not throw
- [ ] Killing wifi mid-session moves status to `disconnectedNoInternet`, and restoring wifi automatically reconnects without any UI code calling `connect()` again
- [ ] Backgrounding then foregrounding the app automatically resumes the connection if it had dropped
- [ ] `checkConnectionStatus()` always matches what `signalRStatusProvider` last emitted
- [ ] No file outside `core/signalr/` ever imports `package:signalr_core` directly

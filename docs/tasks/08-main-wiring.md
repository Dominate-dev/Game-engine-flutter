# Task 08 — `main.dart` Wiring

Depends on: Task 00–07.

## Prompt for Cursor

```
Create lib/main.dart:

1. `Future<void> main() async`:
   - `WidgetsFlutterBinding.ensureInitialized()`
   - `final prefs = await SharedPrefsService.init();`
   - Build a `ProviderContainer` with
     `overrides: [sharedPrefsProvider.overrideWithValue(prefs)]`
   - Register the lifecycle observer ONCE, globally:
     `final lifecycleObserver = AppLifecycleObserver(container.read(signalRServiceProvider));`
     then `WidgetsBinding.instance.addObserver(lifecycleObserver);`
   - Connect SignalR right here, at plugin/module startup — do NOT gate
     this behind a login screen, there is no auth flow yet:
     `container.read(signalRServiceProvider).connect(url: ApiEndpoints.signalRHubUrl);`
     (no accessTokenFactory argument — omit it entirely for now; leave a
     code comment noting that when auth is added later, pass
     `accessTokenFactory: () async => prefs.authToken ?? ''` into this same
     call and nothing else needs to change)
   - `runApp(UncontrolledProviderScope(container: container, child: const AppRoot()))`

2. `class AppRoot extends StatelessWidget`:
   - `MaterialApp`, `debugShowCheckedModeBanner: false`,
     `theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo)`,
     `home: const ChatPage()` (the only screen — see Task 07).

This file is the module's entry point when embedded in a native host app —
whatever native code launches the Flutter engine for this module triggers
this main(), so "connect at plugin start" is satisfied simply by connecting
here rather than after any specific user action.
```

## Acceptance criteria
- [ ] `sharedPrefsProvider` is overridden before any provider that depends on it is read
- [ ] SignalR `connect()` is called unconditionally in `main()`, not inside a widget's `initState` or behind a login gate
- [ ] `AppLifecycleObserver` is registered exactly once, using the same `SignalRService` instance the rest of the app reads via `signalRServiceProvider`
- [ ] `flutter run` (or embedding via add-to-app) launches directly into `ChatPage`

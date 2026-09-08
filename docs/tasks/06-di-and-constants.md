# Task 06 — DI Providers & Constants

Depends on: Task 00, 02, 03.

## Prompt for Cursor

```
1. Inside lib/core/constants/, create api_endpoints.dart:
   - class ApiEndpoints (private constructor `ApiEndpoints._()`) with
     static const baseUrl = 'https://api.yourapp.com' and
     static const signalRHubUrl = 'https://api.yourapp.com/hubs/notifications',
     plus placeholder endpoint paths: login = '/auth/login',
     messages = '/chat/messages'.
   - class SignalREvents (private constructor) with static const event name
     strings: onMessageReceived = 'OnMessageReceived',
     onUserOnline = 'OnUserOnline', onUserOffline = 'OnUserOffline'. Every
     subscribe()/unsubscribe() call anywhere in the app must reference
     these constants, never a raw string literal.

2. Inside lib/core/di/, create providers.dart:
   - `final sharedPrefsProvider = Provider<SharedPrefsService>((ref) {
     throw UnimplementedError(...) })` — this MUST be overridden in main()
     after `await SharedPrefsService.init()`. Document this with a comment
     showing the override example.
   - `final apiClientProvider = Provider<ApiClient>((ref) {...})` that
     reads sharedPrefsProvider and constructs an ApiClient with
     baseUrl: ApiEndpoints.baseUrl and
     tokenProvider: () => prefs.authToken (may be null, that's fine, no
     auth flow exists yet).
```

## Acceptance criteria
- [ ] `sharedPrefsProvider` throws a clear `UnimplementedError` if read before being overridden — this is intentional, don't silently default it
- [ ] No feature file hardcodes a base URL or hub URL — always through `ApiEndpoints`
- [ ] No feature file hardcodes a SignalR event name string — always through `SignalREvents`

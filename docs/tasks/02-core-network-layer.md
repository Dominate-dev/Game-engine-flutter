# Task 02 — Core Network Layer (`ApiClient`, `NetworkInfo`)

Depends on: Task 00, 01.

## Prompt for Cursor

```
Inside lib/core/network/, create:

1. api_client.dart
   - Class `ApiClient` wrapping a `Dio` instance.
   - Constructor takes `required String baseUrl` and
     `String? Function()? tokenProvider`.
   - BaseOptions: connectTimeout and receiveTimeout of 15 seconds,
     default header 'Content-Type': 'application/json'.
   - Add an InterceptorsWrapper.onRequest that calls tokenProvider(); if it
     returns a non-null non-empty string, set
     options.headers['Authorization'] = 'Bearer $token'. tokenProvider may
     be omitted entirely (no auth required yet) — guard against null.
   - Add PrettyDioLogger (package: pretty_dio_logger) with requestHeader,
     requestBody, responseBody all true, compact: true.
   - Expose thin wrapper methods: get<T>(path, {query}), post<T>(path,
     {data}), put<T>(path, {data}), delete<T>(path, {data}), all returning
     Future<Response<T>> and just delegating to the underlying dio instance.

2. network_info.dart
   - Class `NetworkInfo` using package:internet_connection_checker_plus
     (InternetConnection) — NOT connectivity_plus alone, because we need
     real ping-based reachability, not just "connected to a wifi radio".
   - `Future<bool> get isConnected` -> checker.hasInternetAccess
   - `Stream<bool> get onStatusChange` -> checker.onStatusChange mapped to
     bool (InternetStatus.connected -> true, else false)
   - `void dispose()` cancels any held subscription

3. network_info_provider.dart
   - Riverpod `Provider<NetworkInfo>` called `networkInfoProvider` that
     disposes the service via ref.onDispose.
   - Riverpod `StreamProvider<bool>` called `hasInternetProvider` that
     watches networkInfoProvider and returns its onStatusChange stream —
     this is what widgets watch reactively for connectivity banners.

Do not add authentication logic beyond the optional tokenProvider hook —
this app has no login flow yet.
```

## Acceptance criteria
- [ ] `ApiClient` never throws if `tokenProvider` is null or returns null/empty
- [ ] `NetworkInfo` uses ping-based reachability, not raw `connectivity_plus` radio state
- [ ] `hasInternetProvider` auto-disposes its subscription when no longer watched
- [ ] No hardcoded base URL inside `api_client.dart` itself — it's passed in

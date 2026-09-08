# Host Integration

What this repository provides to a native host, what the host must provide in
return, and what is genuinely undecided. Task detail: [TASKS.md](TASKS.md)
(**A1**). Gate status: [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

**Labels:** **VERIFIED** · **INFERRED** · **EXTERNAL VERIFICATION REQUIRED** —
same convention as the rest of `docs/`. Nothing below is a proposal; every
item is either read directly from the current code, or explicitly flagged as
unresolved.

---

## 1. What this repository is

This is a **Flutter add-to-app MODULE** — `pubspec.yaml`'s `module:` block
(`androidPackage`, `iosBundleIdentifier`) and the generated `.android`/`.ios`
scaffolding confirm it is built with `flutter build aar` / `flutter build
ios-framework`, not as a standalone app. It is meant to be embedded into
**existing native Android and iOS host applications**.

**The native host owns:**
- Login and the entire session/credential lifecycle (obtaining, refreshing,
  and revoking a token).
- Home and all top-level product navigation.
- The decision of when to attach a Flutter engine and which module screen to
  show.
- Release signing, obfuscation, and the production build pipeline.

**This module does not implement, and must not be asked to implement, a
production Login or Home screen.** That is a correct architectural boundary,
not a gap.

---

## 2. Session handoff — VERIFIED, already implemented

`packages/coreapp/lib/storage/prefs_keys.dart` declares the exact keys:

```dart
static const token = 'auth_token';
static const refreshToken = 'refresh_token';
static const userId = 'user_id';
static const socialMediaId = 'social_media_id';
static const deviceId = 'device_id';
```

with its own header comment: *"Native host already uses these names — do not
rename."*

`AuthNotifier.build()` (`packages/coreapp/lib/features/auth/presentation/providers/auth_notifier.dart`)
reads these on startup **before** any Flutter-side login attempt:

```dart
Future<AuthSession?> build() async {
  final prefs = ref.watch(sharedPrefsProvider);
  final token = prefs.getToken();
  if (token == null || token.isEmpty) return null;
  ...
}
```

A host that writes a valid token (and, if available, `userId`) into shared
storage under these key names **before** the module's provider tree first
reads them will have the module recognize an existing session with no
Flutter-side login UI involved at all. The module's own `login()` (via
`LoginUseCase`) exists purely as a secondary, debug-only fallback — it is
exercised only by the debug launcher's "Register" button (see §5).

### VERIFIED — storage key prefix

The module reads/writes storage through the classic `shared_preferences: ^2.2.3`
API (`SharedPreferences.getInstance()`, `shared_prefs_service_impl.dart`).

**The effective native storage key is `flutter.`-prefixed, not the raw
`PrefsKeys` name.** This is read directly from the resolved package source,
not inferred:

- The version actually resolved in this checkout is `shared_preferences-2.5.5`
  (`.dart_tool/package_config.json`).
- `shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart:22` —
  `static String _prefix = 'flutter.';`
- Every read/write path in that same file builds the key as `'$_prefix$key'`
  before it reaches the platform channel (`:172`, `:179`), and the prefix is
  applied in the shared Dart facade — **before** any platform-specific code
  runs — so it is identical on Android and iOS, not something either native
  plugin does independently.
- Nothing in this repository calls `SharedPreferences.setPrefix()` (confirmed
  by a repository-wide search) — the default `'flutter.'` prefix is in effect,
  unmodified.

**Concretely: the effective key for `PrefsKeys.token` (`'auth_token'`) is
`flutter.auth_token`** — not `auth_token`. The same applies to every other
`PrefsKeys` entry (`refresh_token` → `flutter.refresh_token`, `user_id` →
`flutter.user_id`, `social_media_id` → `flutter.social_media_id`, `device_id`
→ `flutter.device_id`).

A host writing the session must write under the **prefixed** key on the
native side (Android SharedPreferences file / iOS `NSUserDefaults`), not the
bare `PrefsKeys` string.

---

## 3. The Public Game Engine API — VERIFIED, already implemented

This is the contract the native host codes against. It lives in
`packages/coreapp/lib/engine/` and is exported from the `coreapp` barrel.

```text
Native
   ↓
MethodChannel  ('com.gameengine/public_api')
   ↓
Public Engine API  (coreapp — GameEngine)
   ↓
Internal Engine  (play_game, SignalRService, GameController, …)
```

### 3.1 `GameEngine` — `packages/coreapp/lib/engine/game_engine.dart`

```dart
class GameEngine {
  Future<void> initialize(GameEngineConfig config);
  Future<void> updateConfig(GameEngineConfig config);

  Future<void> connectHub();
  GameEngineConnectionState get connectionState;
  Stream<GameEngineConnectionState> get onConnectionStateChanged;

  Future<void> joinRandomGame();
  Future<void> createPrivateGame(List<int> interestIds);
  Future<void> joinPrivateGame(String code);
  Stream<void> get onGameExited;

  Future<void> leaveGame();
  Future<void> dispose();
}
```

Supporting read-only state, used by the engine itself and available to
Flutter-side glue: `activeConfig`, `pendingConfig`, `isGameActive`,
`isDisposed`.

**`onGameExited`** fires once each time the game route is actually removed.
All three exit paths arrive here and all three arrive **once**, because the
game has a single exit owner — `GameControllerScreen._exitGame` — and every
path funnels through it:

| Path | Reaches the owner via |
|---|---|
| Android Back / the in-game exit confirmation | the screen's own `PopScope` |
| Closing the result dialog after Game Over | `_returnToHomeAfterResult` |
| `GameEngine.leaveGame()` from native | `GameSessionHandle.leave` |

It is **not** a "game over" signal. Reaching Game Over, `RoundFinished`, or
showing the result dialog emits nothing — the match ending and the surface
going away are different events, and only the second one is the host's
business. It carries no payload: what crosses is "the game surface is gone",
and anything more would be game state crossing a boundary that exists to stop
exactly that.

The engine re-emits on its own broadcast controller rather than handing the
host's stream through, so a subscriber that attached before the game plugin
registered — the native bridge does exactly that — still sees every exit.

### 3.2 `GameEngineConfig` — everything the host tells the engine

```dart
class GameEngineConfig {
  final String token;          // required
  final int userId;            // account id; default 0 = none supplied
  final String socialMediaId;  // default ''
  final String language;       // 'ar' | 'en', normalised on the way in
  final bool musicEnabled;     // default true
  final bool soundEnabled;     // default true
}
```

`GameEngineConfig.fromMap` ignores unknown keys and defaults missing ones, so
adding a field later cannot break an older host build. `language` is passed
through `AppLanguage.normalize`, so an unrecognised code falls back to `en`
rather than reaching the string tables raw.

`userId` is the **authenticated account id** — on Android the value native
already holds in `UserPref.getId()`, and the same numeric identity the game
roster uses for its players. The engine matches the local seat on it
(`GameController._findPlayers` -> `GamePlayer.matchesHubUserId`), so the
player's own name, score and avatar depend on the host sending it. It is
written to the existing `user_id` key through the existing
`SharedPrefsService.setUserId`; there is no new key and no second identity
mechanism.

`socialMediaId` is **not** a substitute for it. That value identifies the
sign-in provider account, never appears in a roster, and matching against it
seats no player. Both are carried because both have their own purpose.

Zero — the default when the host omits the field — means *no id supplied*,
which is how `SharedPrefsService.getUserId()` already reads an absent key. A
config that omits `userId` therefore leaves any previously stored id intact
rather than clearing it, matching how the module's own login flow guards its
write.

**The host never sees a storage key.** The engine writes these to
`SharedPrefsService` under `PrefsKeys` internally; the `flutter.`-prefixed
names in §2 remain true but are no longer something native has to know when
it uses this API. §2 still applies to a host that pre-seeds a session before
the engine boots.

### 3.3 `GameEngineConnectionState`

```dart
enum GameEngineConnectionState { disconnected, connecting, connected, reconnecting }
```

Deliberately smaller than the internal `SignalRStatus`, which has seven
values. `idle`, `failed` and `disconnectedNoInternet` all map to
`disconnected`: the host acts on all three the same way — not connected, and
the engine is already handling it — so they are not exposed as native
branching the engine would then have to keep compatible.

### 3.4 What native never touches

Not reachable through this API, by design:

`SignalRService` · `GameController` · Riverpod providers · round handlers ·
lobby handlers · dialogs · `GameSessionState` · `BuildContext` ·
`NavigatorState`.

The public surface is value types, futures and one stream. Verified by
search: none of those type names appears in `game_engine.dart`,
`game_engine_channel.dart` or `game_engine_host.dart` outside comments.

### 3.5 The internal Dart navigation API — unchanged

`packages/play_game/lib/presentation/play_game_launcher.dart`:

```dart
abstract final class PlayGame {
  static Future<void> openWaiting(BuildContext context);
  static Future<void> openPrivateGame(BuildContext context,
      {required List<int> interestIds});
  static Future<void> openPrivateGameByCode(BuildContext context,
      {required String gameCode});
  static Future<void> openPlayerProfile(BuildContext context, {int? playerId});
  static Future<void> clearGameData(WidgetRef ref);
}
```

These still require a `BuildContext` and are **internal** — the engine calls
them, native does not. (An earlier revision of this document listed an
`openPrivateLobby` method; it no longer exists, and creating vs joining a
private game are two separate entries.)

`GameEngineHost` (`coreapp`) is the seam between the two packages:
`coreapp` declares it, `PlayGameEngineHost` (`play_game`) implements it with
the engine-owned navigator. `coreapp` never depends on a game plugin.

---

## 3A. The native bridge — VERIFIED, already implemented

`packages/coreapp/lib/engine/game_engine_channel.dart`. One `MethodChannel`,
both directions. No `EventChannel` and no Pigeon: state changes are pushed
over the same channel, so the native side registers one object.

**Channel name:** `com.gameengine/public_api`

### Native → Engine

| Method | Arguments | Returns |
|---|---|---|
| `initialize` | `Map` — `token`, `userId`, `socialMediaId`, `language`, `musicEnabled`, `soundEnabled` | `null` |
| `updateConfig` | same map | `null` |
| `connectHub` | none | `null` |
| `connectionState` | none | `String` — one of the four state names |
| `joinRandomGame` | none | `null` |
| `createPrivateGame` | `{'interestIds': List<int>}`, or the list directly | `null` |
| `joinPrivateGame` | `{'code': String}`, or the string directly | `null` |
| `leaveGame` | none | `null` |
| `dispose` | none | `null` |

### Engine → Native

| Method | Argument | When |
|---|---|---|
| `onEngineReady` | none | Once, when the engine is ready for commands |
| `onConnectionStateChanged` | `String` — `disconnected` \| `connecting` \| `connected` \| `reconnecting` | Every internal status change |
| `onGameExited` | none | Each time the game route is actually removed |

A push to a host that has gone away is logged, not thrown.

**`onEngineReady`** is the readiness handshake. Until native sees it, a call
can land before the Dart method-call handler is installed and come back as
`MissingPluginException`. **Native does not need to retry that exception, and
must not poll `connectionState` to infer readiness** — it waits for this
event. Sent at most once per engine, and never before the handler is
attached; the guard lives in the channel, so the ordering cannot be got wrong
by a caller. See §3E for exactly where it sits in the boot sequence.

It does **not** mean configured or connected. The host still owns
`initialize(config)` and then `connectHub()`, in that order, and the engine
does neither on its own.

**`onGameExited`** is the signal that the game surface is gone and the host
may detach, hide, or pop its Flutter container. See §3.1 for which paths emit
it and why a finished game does not.

### Errors

`PlatformException` with a stable code:

| Code | When |
|---|---|
| `bad_arguments` | non-integer or empty `interestIds`, blank `code`, non-map config |
| `engine_disposed` | any command after `dispose` |
| `engine_error` | anything else the command threw |

An unknown method name returns the standard *not implemented* reply.

`joinPrivateGame` trims the code at the boundary and refuses a blank one; the
non-blank code is forwarded to the hub as given.

---

## 3B. Configuration lifecycle — VERIFIED

```text
Outside an active game     initialize / updateConfig -> applied immediately
Inside an active game      updateConfig              -> held, not applied
                                                     -> applied on leaveGame
```

`initialize` is by definition outside a game and always applies. During a
game the running session **keeps the configuration it started with** —
`activeConfig` — and the new one is held in `pendingConfig` until the game
ends, so the next session gets it. A language flip or a muted track mid-round
is exactly the silent change this prevents.

Applying a config does three things, all through existing mechanisms:
`SharedPrefsService` for `token`/`userId`/`socialMediaId`, `AppLanguageNotifier
.setLanguage` for the language (persists, updates `AppStrings`, rebuilds the
UI), and `AudioService.setMusicEnabled`/`setSfxEnabled` for the two audio
flags. No second AudioService, no second localization system, no second
token source.

**Token:** `accessTokenFactory` reads prefs per connect attempt, so a token
set while the hub is already up is used by the **next** connect. No forced
reconnect is performed — nothing in this repository establishes that one is
required.

---

## 3C. `connectHub()` idempotency — VERIFIED

```text
connected     -> no-op
connecting    -> no-op
reconnecting  -> no-op
disconnected  -> one connection attempt
```

Concurrent calls share one in-flight future, so three simultaneous
`connectHub()` calls produce exactly one attempt. This is the outer guard;
`SignalRService`'s own `_skipIfAlreadyConnected` is untouched underneath.

**`SignalRService` remains the sole owner** of connecting, reconnecting,
recovery, backoff, connection state and app pause/resume. The public API
exposes the capability; it does not reimplement it.

---

## 3D. Game flow commands — VERIFIED

| Command | Internal entry | Hub method |
|---|---|---|
| `joinRandomGame()` | `PlayGame.openWaiting` | `JoinRandomGame` (no args) |
| `createPrivateGame(ids)` | `PlayGame.openPrivateGame` | `CreatePrivateGame([ids])` |
| `joinPrivateGame(code)` | `PlayGame.openPrivateGameByCode` | `JoinPrivateGame([code])` |

The interest ids are the host's — nothing is defaulted and no debug id is
invented. Both private dispatches are connection-gated and deferred until the
entry connect lands, retried through the existing recovery path.

**`leaveGame()`** goes through `GameControllerScreen`'s single exit owner —
the same path a Back gesture takes — producing one `LeaveGame`, one route
removal and the same cleanup. It is a no-op when no game is on screen, and it
opens no second `LeaveGame` path.

---

## 3E. Entry point, root and runtime — VERIFIED

**Entry point:** `gameEngineMain()` in `lib/engine_entry.dart`, annotated
`@pragma('vm:entry-point')`. This is what a native host targets. It is
**not** `main()`, which remains the development launcher.

```text
gameEngineMain()
   ↓ GameEngineRuntime.start()
   ↓ ProviderContainer  -> AppLifecycleObserver -> GameEngine -> GameEngineChannel
   ↓ bindTeardown(runtime.dispose) -> channel.attach()   [handler installed]
   ↓ registerHost(PlayGameEngineHost)
   ↓ runApp(runtime.buildApp())   ->  GameEngineRoot     [first frame]
   ↓ onEngineReady  ──────────────────────────────────>  native
   ↓ native: initialize(config) -> connectHub() -> a game flow
```

**Where `onEngineReady` sits, and why there.** It is fired from a post-frame
callback registered at the end of the boot sequence, so by the time native
sees it the prefs are loaded, the container is built, the method-call handler
is installed, the game-flow host is registered **and the engine navigator
exists**. That last one is why it waits for the first frame rather than firing
the moment the channel attaches: `initialize` and `connectHub` would be fine
either way, but a host that acted on the event immediately by asking for a
game flow would hit a navigator that `runApp` had not created yet. Waiting one
frame makes the event mean *every* public method is safe to call, not most of
them.

`GameEngineRuntime` owns the container, the engine, the bridge, the lifecycle
observer and the navigator key. `GameEngineRoot` is the engine's own
`MaterialApp`: the engine navigator key, the shared theme/locale/delegates,
`LoaderOverlay`, and a blank idle page. It deliberately does **not** carry
`AppTheme.navigatorKey` (null in release), the debug route observer, or
`HomeLauncherPage`.

The engine **boots idle**: no token, language, audio setting or connection is
assumed. It waits for the host's commands.

**Disposal** reverses start, in order, and is idempotent:

```text
detach bridge -> dispose GameEngine -> removeObserver -> container.dispose()
```

Container disposal disposes `signalRServiceProvider`, whose own `onDispose`
tears the hub down. **Leaving a game never disconnects the hub** — the hub is
engine-lifetime and goes only when the engine goes.

**The channel's `dispose` performs exactly this teardown, not a smaller one.**
`GameEngineRuntime` binds its own `dispose` into the bridge at start, and the
`dispose` method call runs that. The bridge has no teardown of its own to get
out of step: disposing the public `GameEngine` alone would leave the
container, the lifecycle observer and the hub running behind a bridge that had
just gone deaf. Both halves are idempotent, so a second `dispose` from native
is a no-op rather than a crash, and a native `dispose` followed by a direct
`GameEngineRuntime.dispose()` still detaches once.

After it, the method-call handler is gone, so a later command comes back as
the standard *not implemented* reply — native's own signal that the engine is
no longer there.


---

## 4. Build-time environment configuration — VERIFIED, already implemented

`packages/coreapp/lib/constants/api_endpoints.dart` resolves both the API base
URL and the SignalR hub URL from `--dart-define`:

```dart
static const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: baseUrlDebug);
static const signalRHubUrl = String.fromEnvironment('SIGNALR_HUB_URL', defaultValue: baseUrlHubDebug);
```

Whatever builds the module's `.aar` / iOS framework must pass both defines
(both-or-neither — a half-configured build is rejected, see
`test/api_endpoints_test.dart`). Add-to-app hosts do not use the `flutter
build` CLI directly for this; the equivalent is the Flutter Gradle plugin's
`dartDefines` property (Android) or the corresponding Xcode build setting
(iOS). **If the host's build step omits these, the module silently falls
back to the test backend** — this is tracked as **F1b** and is a build-pipeline
coordination fact, independent of the Login/Home question.

---

## 5. Debug harness — not the production entrypoint

`lib/main.dart`, `HomeLauncherPage`
(`lib/features/home/presentation/pages/home_launcher_page.dart`), and
`DebugConfig` (`lib/core/constants/debug_config.dart`) exist **only** to
exercise this module's screens during development and testing:

- **"Register"** calls the module's own `login()` fallback with
  `DebugConfig`'s test credentials (both empty in this repository — no real
  secret is hardcoded).
- **"Start Hub"** manually triggers `connectHub()` (see §6) — a host does not
  need a UI button for this.
- **"Play" / "Pvp" / "Player Profile"** call `PlayGame.openWaiting` /
  `openPrivateGame` / `openPlayerProfile` directly — the same internal Dart
  API the engine's own host implementation calls.

**None of this is expected to be shown to a real end user.** A native host
targets `gameEngineMain` (§3E) and gets `GameEngineRoot`, never
`HomeLauncherPage` or `AppRoot`. Both entry points coexist: the debug
launcher is unchanged and keeps working. Their continued presence is correct
for development and is not a production defect (see **P2**,
[TASKS.md](TASKS.md)).

---

## 6. SignalR connection behavior

`BaseState.connectHub()` (`packages/coreapp/lib/presentation/base_page.dart`)
already reads the token from shared storage when connecting:

```dart
await signalR.connectIfNeeded(
  url: url ?? ApiEndpoints.signalRHubUrl,
  accessTokenFactory: () async => prefs.getToken() ?? '',
);
```

This means the connection mechanism itself is already host-session-compatible
— it reads whatever token is present in storage, regardless of who wrote it.

### The GameEngine guarantees the connection on entry — VERIFIED

`GameControllerScreen` — the screen `PlayGame.openWaiting` pushes, and the
one that hosts every phase from Waiting onward — ensures a connection when
it is entered:

- **A live connection is reused.** The check is
  `SignalRService.hasLiveConnection`, which covers *connected* **and**
  *connecting*, so an existing connection is never duplicated and no second
  connect is issued while one is already in flight.
- **No live connection → the GameEngine connects**, using the existing
  `connectHub()` path (which already supplies `ApiEndpoints.signalRHubUrl`
  and the prefs-backed token).

**The host may pre-connect, but correctness no longer depends on it.**
Either way works: if the host connected first, entry reuses that
connection; if it did not, entry establishes one.

A connect that fails on entry stays silent — no modal is raised over the
screen being entered. `SignalRService`'s own handling is unchanged: it sets
`failed`, schedules its backoff retry, and a later drop still raises the
`ConnectionLoader`.

The debug launcher's "Start Hub" button still exists, but it is a dev-harness
convenience, not the mechanism production depends on.

---

## 7. Host-side decisions — now resolved on the Flutter side

Both questions that sat here are answered by the implementation:

1. **Entrypoint/routing mechanism — RESOLVED.** `gameEngineMain`
   (`@pragma('vm:entry-point')`) is the host-facing entry point, and the
   `com.gameengine/public_api` MethodChannel is how a host asks for a flow.
   See §3A and §3E. The host no longer has to choose a mechanism; it has to
   *call* one.
2. **Engine attach/detach lifecycle — RESOLVED on this side.**
   `GameEngineRuntime.dispose()` detaches the bridge, disposes the engine,
   removes the lifecycle observer and disposes the container, in that order
   and idempotently. This closes the Flutter half of **S8**. The hub is
   disconnected only by that container disposal — never by leaving a game.

What is still genuinely host-owned, and this repository must not guess at:

- Whether the host caches one `FlutterEngine` across sessions or builds a new
  one per entry, and therefore whether `dispose` is called per game or per app
  session.
- Whether the host pre-seeds a session in shared storage (§2) or configures
  through `initialize` (§3B). Both work; they are not mutually exclusive.

*(Previously resolved and recorded here for continuity: the storage key
prefix — §2 — and the connection trigger model — §6.)*

---

## 8. What this repository still needs to fix on its own

Independent of any host decision — see [TASKS.md](TASKS.md) for status:

- **SEC2** — tokens are stored in plaintext `SharedPreferences`; secure
  storage would need host-key coordination (same shared-storage keys must
  keep working).
- **E3** — no crash reporting.

**Already closed since this document was first written:**

- **SEC1a** — release/device log verification of the **SEC1** fix has been
  carried out and confirmed by the repository owner.
- **N2** — REST access-token refresh is **fully implemented**: a 401
  refreshes through `GET api/Users/RefreshToken` and the original request is
  retried once with the new token.
- **P1a** — the same refresh now covers SignalR: a 401 on the hub upgrade
  refreshes and replays the upgrade once, sharing a single in-flight refresh
  with REST rather than running a second mechanism. **Still pending external
  verification:** this path has not yet been exercised against a genuine
  server-issued 401 on the wire — worth confirming during first host
  integration. That is verification, not an implementation gap.

# Final Flutter Engine Readiness Audit

Baseline: `NATIVE_INTEGRATION_READINESS_AUDIT.md`. Contract:
[HOST_INTEGRATION.md](HOST_INTEGRATION.md). Rules:
[ENGINEERING_RULES.md](ENGINEERING_RULES.md).

**Labels:** READY · BLOCKER · NON-BLOCKING · NATIVE WORK · UNKNOWN.
Every claim below was checked against the implementation. Documentation was
not accepted as evidence for anything (§2.4).

---

## 1. Executive Summary

The Flutter side of the native integration is complete. A native host can
target `gameEngineMain`, drive the engine over one MethodChannel, and tear it
down cleanly. Nothing internal crosses the boundary.

Since the baseline audit, the four gaps it identified are closed:

| Baseline gap | Now |
|---|---|
| No native↔Dart bridge | `GameEngineChannel`, one MethodChannel, both directions |
| No native-callable API | `GameEngine` — 9 commands + state + stream |
| No host-facing entry point | `gameEngineMain`, `@pragma('vm:entry-point')` |
| S8 — container/observer never disposed | `GameEngineRuntime.dispose()`, ordered and idempotent |

**No BLOCKERS on the Flutter side.** Everything that remains is either
NATIVE WORK or NON-BLOCKING.

---

## 2. Public Engine API — READY

`packages/coreapp/lib/engine/` — seven files, exported from the `coreapp`
barrel.

| Check | Result |
|---|---|
| Lives under `packages/coreapp` | **READY** |
| Surface is value types / futures / one stream | **READY** |
| No internal leak | **READY** — `SignalRService`, `GameController`, `GameSessionState`, `BuildContext`, `NavigatorState` appear in `game_engine.dart`, `game_engine_channel.dart`, `game_engine_host.dart` **only inside comments** (grep-verified) |
| `GameEngineConfig` complete | **READY** — all five values, `fromMap`/`toMap`, unknown keys ignored, missing keys defaulted |
| Connection state API | **READY** — `connectionState` getter + `onConnectionStateChanged` broadcast stream |
| Commands wired | **READY** — all nine reach their internal implementation |

`coreapp` does **not** depend on `play_game` (grep-verified; pubspec confirms
`play_game → coreapp` only). Game flows cross via `GameEngineHost`, declared
in `coreapp` and implemented once, by `PlayGameEngineHost`.

---

## 3. Native Bridge — READY

`game_engine_channel.dart`. Channel `com.gameengine/public_api`.

| Check | Result |
|---|---|
| Channel exists and is wired | **READY** |
| Channel name documented | **READY** — `HOST_INTEGRATION.md` §3A |
| Commands map to the public API | **READY** — 9 methods, each a single call |
| Arguments validated | **READY** — non-map config, non-integer/empty `interestIds`, blank `code` all rejected |
| Errors consistent | **READY** — `bad_arguments`, `engine_disposed`, `engine_error`; unknown method → standard not-implemented |
| State notifications delivered | **READY** — `onConnectionStateChanged` pushed on the same channel; a dead host is logged, not thrown |
| Disposal safe | **READY** — `detach()` clears the handler and cancels the subscription; idempotent |
| No duplicate mechanism | **READY** — one channel, no EventChannel, no Pigeon |

No game logic in the bridge: it decodes, calls, encodes.

---

## 4. Engine Entry Point — READY

`lib/engine_entry.dart`.

| Check | Result |
|---|---|
| `gameEngineMain()` valid host entry | **READY** |
| `@pragma('vm:entry-point')` present | **READY** — line 21 |
| Boots the correct runtime | **READY** — `GameEngineRuntime.start()` |
| Registers a `GameEngineHost` | **READY** — `PlayGameEngineHost` with the runtime's navigator + container |
| Renders the engine root | **READY** — `runApp(runtime.buildApp())` → `GameEngineRoot` |
| Does not use `HomeLauncherPage` | **READY** — no reference outside a comment |
| `main()` unchanged | **READY** — `git diff` on `lib/main.dart` is **empty** |

It lives in `lib/` because that is the only place both packages are visible —
`coreapp` may not depend on a game plugin (§12.4).

---

## 5. Runtime Lifecycle — READY

`game_engine_runtime.dart`.

Owns: `ProviderContainer`, `GameEngine`, `GameEngineChannel`,
`GlobalKey<NavigatorState>`, `AppLifecycleObserver`. Start order:
container → observer → engine → bridge.

Dispose order (`:125-129`), verified line by line:

```text
detach bridge -> engine.dispose() -> removeObserver -> container.dispose()
```

| Check | Result |
|---|---|
| Ownership of all five | **READY** |
| Start/dispose ordering | **READY** — bridge first so no native call lands mid-teardown; observer before the container so no lifecycle callback reaches a disposing service |
| Idempotent disposal | **READY** — `_disposed` guard; a second call detaches nothing further |
| No leaks | **READY** — three start/dispose cycles leave no observer behind (tested behaviourally by sending real lifecycle messages) |

---

## 6. SignalR / Connection Lifecycle — READY

| Check | Result |
|---|---|
| One connection manager | **READY** — the engine has exactly **one** `connectIfNeeded` call and no state of its own |
| `connectHub()` uses the existing service | **READY** |
| connected/connecting/reconnecting do not duplicate | **READY** — each returns without touching the service |
| Concurrent calls | **READY** — one in-flight future is shared; three simultaneous calls → **one** attempt |
| Reconnect/recovery still owned by `SignalRService` | **READY** — untouched |
| Leaving a game does not disconnect | **READY** — asserted |
| Engine disposal disposes SignalR | **READY** — `container.dispose()` → `signalRServiceProvider.onDispose` → `service.dispose()` (`signalr_provider.dart:27-30`) |

---

## 7. Configuration Lifecycle — READY

All five values, each through the existing mechanism — no second source:

| Value | Mechanism |
|---|---|
| `token` | `SharedPrefsService.setToken` |
| `socialMediaId` | `SharedPrefsService.setSocialMediaId` |
| `language` | `AppLanguageNotifier.setLanguage` (persists, updates `AppStrings`, rebuilds UI) |
| `musicEnabled` | `AudioService.setMusicEnabled` |
| `soundEnabled` | `AudioService.setSfxEnabled` |

| Check | Result |
|---|---|
| Initialize applies all five | **READY** |
| Update outside a game applies | **READY** |
| Active-game snapshot preserved | **READY** — `activeConfig` unchanged, new one held in `pendingConfig` |
| Next session gets the latest | **READY** — applied on `leaveGame()` |
| No duplicate config source | **READY** — no second `AudioService` (asserted by identity), no second localization system, no second token source |
| Native needs no prefs key names | **READY** — the API owns the mapping |

The audit's read-once `AudioService` finding is closed: the setters are used,
not the constructor path.

---

## 8. Game Entry Flows — READY

| Flow | Internal entry | Hub |
|---|---|---|
| Random | `PlayGame.openWaiting` | `JoinRandomGame` |
| Create private | `PlayGame.openPrivateGame` | `CreatePrivateGame([ids])` |
| Join private | `PlayGame.openPrivateGameByCode` | `JoinPrivateGame([code])` |

| Check | Result |
|---|---|
| Native supplies no `BuildContext` | **READY** — the engine-owned navigator key supplies it internally |
| Engine owns navigation | **READY** — `navigatorKey` appears **zero** times in the engine/channel files |
| Game logic stays in `play_game` | **READY** |
| No game logic in `coreapp` | **READY** — only the abstract `GameEngineHost` |
| Interest ids are the host's | **READY** — nothing defaulted, no `[88]` invented |

---

## 9. Leave / Exit — READY

| Check | Result |
|---|---|
| Uses the single exit owner | **READY** — `GameSessionHandle` → `GameControllerScreen._exitGame` |
| No duplicate `LeaveGame` | **READY** — one invocation asserted; three repeated calls still one |
| Back/Exit unchanged | **READY** — `game_exit_lifecycle_test.dart` passes untouched |
| Cleanup correct | **READY** — same path, same `autoDispose` reset |

---

## 10. Engine Disposal — READY

Bridge detaches, engine disposes, observer removed, container disposes,
SignalR disposes, repeat is safe. Post-dispose calls throw `StateError`
rather than misbehaving, and the state stream is closed so no push can reach
a disposed host. **READY** on all seven checks.

---

## 11. Audio / Assets — READY

Nothing changed in this task; verified intact:

| Check | Result |
|---|---|
| Dialog sound mappings | **READY** — 22 `sound:` arguments across the four handlers |
| Button sounds | **READY** — `playAnswerClick` (`selectable_chip.dart:83`), `playBellRound` (`bell_round_screen.dart:207`) |
| Music lifecycle | **READY** |
| Stops on leave | **READY** — `_stopGameMusic()` in `_exitGame` |
| Stops on finish | **READY** — `_stopGameMusic()` in `_showResultDialog` |
| SFX independent | **READY** — music-only stop; win/loss SFX still play |
| No regressions | **READY** — `game_music_lifecycle_test.dart` passes |

---

## 12. Development vs Production — READY

| Check | Result |
|---|---|
| `main() → HomeLauncherPage` works | **READY** — file untouched |
| Production entry separate | **READY** — two distinct entry points |
| No debug-only navigator assumption | **READY** — `GameEngineRoot` uses the runtime's key, never `AppTheme.navigatorKey` (null in release) |
| No dev launcher leak into the engine root | **READY** — no `homeLauncherRouteObserver`, no `HomeLauncherPage` |
| No test backend in production builds | **NATIVE WORK** — see §13 |

---

## 13. Build / Release Readiness

| Item | Status |
|---|---|
| `pubspec.yaml` module block | **READY** — `androidPackage: com.example.game_engine`, `iosBundleIdentifier: com.hasanhasanat.gameEngine` |
| Melos / workspace | **NON-BLOCKING** — no `melos.yaml`; path deps only, which build fine |
| Generated files | **READY** — zero `*.g.dart` / `*.freezed.dart`; nothing to regenerate |
| Assets | **READY** — 20 audio + images/lottie declared in `coreapp/pubspec.yaml`, inherited by the module |
| `API_BASE_URL` / `SIGNALR_HUB_URL` | **NATIVE WORK — highest risk** |

**F1b, re-verified and unchanged.** `api_endpoints.dart:14-22` resolves both
URLs from `String.fromEnvironment` with `defaultValue` pointing at
`https://api-test.tahadialthalatheen.com`. An add-to-app host does not use
the `flutter build` CLI, so if the Gradle `dartDefines` / Xcode equivalent is
omitted, **the module silently ships against the test backend** with no error
and no log. This is the single highest-risk item in the whole integration and
is invisible at runtime.

`androidPackage: com.example.game_engine` is still the scaffold default —
**NON-BLOCKING**, but the native team should confirm it is what they want
before publishing an AAR.

---

## 14. Remaining Flutter Issues

| Issue | Class | Note |
|---|---|---|
| `dart:async` unused import in `win_dialog.dart` | **NON-BLOCKING** | Present in `HEAD` (commit `50882b8`), not from this work. It is the *only* analyzer warning in the repo and the reason `flutter analyze` is not 0 issues on a clean checkout — see below |
| Win Claim Rewards → `collectingRewardsSd` not wired | **NON-BLOCKING** | Approved mapping, removed externally; `_cardUi`'s `ref` parameter is now unused |
| Unfinished `///` → `//` cleanup (62 files) | **NON-BLOCKING** | Out of scope by instruction; 65 production files still hold `///` |
| `HOST_INTEGRATION.md` §5 references `DebugConfig` credentials | **NON-BLOCKING** | Accurate; both empty |
| SEC2 — plaintext token storage | **NON-BLOCKING** | Pre-existing; needs host-key coordination |
| E3 — no crash reporting | **NON-BLOCKING** | Pre-existing |
| `GameEngineRuntime` overrides parameter | **READY** | A normal Riverpod affordance, also used by its tests; not a test-only hook |

**Analyzer at the time of this audit: `No issues found!`** — the
`win_dialog.dart` warning does not appear in the current working tree run,
because the working tree carries the in-progress comment cleanup. On a clean
`HEAD` checkout it reappears. Recorded so it is not mistaken for a regression.

---

## 15. Native Integration Prerequisites

Everything below is **NATIVE WORK**. None of it is blocked by Flutter.

**Both platforms**
1. Pass `API_BASE_URL` and `SIGNALR_HUB_URL` as dart-defines (**F1b** —
   omit and you ship the test backend).
2. Target the Dart entrypoint **`gameEngineMain`**, not `main`.
3. Register a MethodChannel client on **`com.gameengine/public_api`**.
4. Call `initialize(config)` before any flow; `connectHub()` next.
5. Handle `onConnectionStateChanged` (4 states) and the three error codes.
6. Decide the engine lifecycle: cache one `FlutterEngine` or build per
   entry, and call `dispose` accordingly. **Disposing kills the hub** — that
   is correct and intended, but it means "dispose per game" would reconnect
   every time.
7. Optionally pre-seed the session under `flutter.`-prefixed keys (§2) — not
   required if using `initialize`.

**Android:** `FlutterEngine`/`FlutterEngineGroup` with
`DartEntrypoint(…, "gameEngineMain")`, `FlutterActivity`/`FlutterFragment`
hosting, Kotlin channel client, `dartDefines` via the Flutter Gradle
extension, attach/detach lifecycle.

**iOS:** `FlutterEngine(name:project:)` run with entrypoint `gameEngineMain`,
`FlutterViewController` hosting, Swift channel client, the Xcode dart-defines
equivalent, lifecycle.

**Backend (unchanged, pre-existing):** `P1a`'s hub-401 refresh has never been
exercised against a real server 401; the `WrongGameCode` payload shape is
unconfirmed and is treated as a bare signal.

---

## 16. Final Readiness Verdict

```text
Flutter Engine:
READY FOR NATIVE
```

No Flutter-side blockers. The public API, bridge, entry point, runtime
lifecycle, connection idempotency, configuration lifecycle, game flows,
leave path and disposal are all implemented and covered by tests that fail
without them.

The one item that deserves explicit attention before the first native build
is **F1b** — a silently wrong backend is far more expensive to diagnose later
than to configure now.

### Verification for this audit

| | |
|---|---|
| Files changed | `docs/HOST_INTEGRATION.md` (§3 rewritten, §3A–§3E added, §5 and §7 corrected), `docs/FINAL_FLUTTER_ENGINE_READINESS_AUDIT.md` (new) |
| Production code changed | **none** |
| Tests changed | **none** |
| Focused tests | engine API + runtime + host + exit + music — **90/90 passing** |
| Full suite | **1833 passing, 0 failing** |
| Analyzer | **No issues found!** |
| Native files touched | **none** — no Kotlin, Swift, Obj-C, Java, Gradle, Podfile or Xcode change |

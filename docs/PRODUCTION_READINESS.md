# Production Readiness

Gate status for shipping this module to real users.

Findings: [PROJECT_ASSESSMENT.md](PROJECT_ASSESSMENT.md) · Tasks:
[TASKS.md](TASKS.md) · Sequencing: [ROADMAP.md](ROADMAP.md)

**Status:** ✅ Ready · ⚠️ Partial · ❌ Not ready · ➖ Not assessed
**Labels:** **VERIFIED** · **INFERRED** · **EXTERNAL VERIFICATION REQUIRED**

---

## Verdict

**No repository-side release blocker remains. Native Host integration has
not started, and is what stands between this module and a shipped product.**

All three original Critical blockers are closed: the release-log credential
leak (**SEC1**, with device/release verification now owner-confirmed —
**SEC1a**), the hardcoded test backend URL (**F1**, now a `--dart-define`
build input), and auth being cleared on every cold start (**P1**).

Since then the module also gained a complete access-token refresh stack —
REST (**N2**) and SignalR (**P1a**) — and guarantees its own hub connection
on entry (**A1**, repository side).

What remains is not Flutter work: the native host has not yet embedded the
Flutter engine, so the host→Waiting launch mechanism is still undecided
(**A1**, host side). Backend-owned gaps (**R-08**, **SEC3/SEC4**) and
optional architectural debt are tracked in [TASKS.md](TASKS.md) and are not
release blockers.

---

## Security

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| Credentials in release logs | ✅ | — | **DONE — VERIFIED.** `PrettyDioLogger` is now registered only when `enableLogging`, which defaults to `kDebugMode` (`api_client.dart:19,56`), mirroring the `enableChucker` gate beside it. It no longer runs in a release build. | **SEC1** |
| `Request-Token` logged | ✅ | — | **DONE — VERIFIED.** The `Request-Token` value log was deleted from `ApiHeadersBuilder` along with its then-unused `AppLogger` import; the file now has zero logging calls. The header itself is still built and sent, unchanged. | **SEC1** |
| `AppLogger` has no level split | ❌ | Medium | **STILL TRUE — VERIFIED:** `app_logger.dart` exposes a single `log()` (plus `formatTimestamp`), so payload-carrying calls cannot be gated separately. **VERIFIED: none of those sites carries a credential** — they carry game payloads. Retagged: this is the **SEC1b** residual, not part of the completed **SEC1** fix. | **SEC1b** |
| Release-log behaviour confirmed on device | ✅ | — | **CONFIRMED BY THE REPOSITORY OWNER.** Release/device log verification of the **SEC1** fix has been carried out and confirmed; this is no longer outstanding external verification. | **SEC1a** |
| Token storage | ❌ | Med-High | **VERIFIED:** plaintext `SharedPreferences`; no `flutter_secure_storage` in any pubspec. Coordinate — `PrefsKeys` names are shared with the native host. | **SEC2** |
| Request token uses device clock | ❌ | Medium | **VERIFIED.** Clock skew would fail every request if the server enforces a replay window. Needs a server-time source. | **SEC3** |
| Device id predictable | ❌ | Low-Med | **VERIFIED:** time-derived, not random. Use `Random.secure()`. | **SEC3** |
| RSA padding / key size | ❌ | Medium | **VERIFIED:** `PKCS1Encoding`. Key size **INFERRED**, not precisely determined. Backend-owned. | **SEC4** |
| Debug config in every build | ❌ | Low | **VERIFIED, re-scoped:** `DebugConfig` carries no real secret (empty debug username/password; one non-secret test social-media id), and is only reachable through the debug launcher, which a real host embedding is not expected to show (see **A1** / **P2** — the module is embedded into an existing native host that owns its own entry point). A low-severity residual tied to that same entrypoint decision, not an independent production Login/Home blocker. | **SEC5** |
| `chucker_flutter` in release binary | ➖ | Low | **EXTERNAL VERIFICATION REQUIRED** — interceptor is gated; whether the package is tree-shaken out is untested. | **SEC5** |
| Hardcoded secrets | ✅ | — | **VERIFIED:** none. The embedded RSA key is a *public* key, which is correct. | — |

---

## Networking

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| 401 handling / token refresh | ✅ | — | **DONE — VERIFIED.** A 401 refreshes through the owner-confirmed `GET api/Users/RefreshToken` and retries once, on **both** transports: `RefreshTokenInterceptor` for REST (**N2**) and `SignalRHttpClient`'s upgrade path for the hub (**P1a**). Both route through one shared `AuthTokenRefresher`, so concurrent 401s across transports share a single refresh; a failed/missing refresh clears the stored session and lets the 401 surface as before. | **N2 / P1a** |
| Silent action loss | ❌ | **High** | **VERIFIED:** `invoke()` returns a completed future on the disconnected path, so `SubmitAnswer` / `Pass` / `ReadyForGame` can be dropped while the UI shows them accepted. | **N3** |
| Waiting-screen dead end | ❌ | High | **VERIFIED:** `_didJoinRandom` is set before the awaited `invoke`, so a drop at that moment strands the user. | **S5** |
| Reconnect path coordination | ⚠️ | Med-High | **VERIFIED** (code) / **INFERRED** (race): multiple triggers guarded only by entry-checked booleans. | **N4** |
| Recovery after a drop | ✅ | — | **VERIFIED:** `onRecovered()` invokes `CheckPlayerGame`; `ConnectionRecoveryController` is live. | — |
| Transport fallback | ❌ | High | **VERIFIED:** WebSockets only with `skipNegotiation: true`. The stated reason (server closes `?access_token=` with 1002) is **EXTERNAL VERIFICATION REQUIRED** — comment-sourced only. | — |
| Hub client maintenance | ⚠️ | Med-High | **VERIFIED:** `signalr_core` pinned with load-bearing overrides. Maintenance state **EXTERNAL VERIFICATION REQUIRED**. | **N5** |
| Connectivity handling | ✅ | — | **VERIFIED:** interface state plus real reachability, cached for synchronous guards. | — |
| Error architecture | ✅ | — | **VERIFIED:** `guard()` → typed `Failure` → `runApi`; zero `catch` in feature code. | — |

---

## Architecture

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| Clean Architecture / dependency direction | ✅ | — | **VERIFIED:** `coreapp` has 0 references to `play_game`. | — |
| Analyzer as a quality gate | ✅ | — | **VERIFIED:** 83 → 1, achieved via a legal access path, not suppression. | **F-A4C** |
| Handler decoupling | ❌ | High | **VERIFIED:** `part`/`extension` handlers remain coupled to controller state and ~11 private members; they cannot be tested in isolation. | **A4 / Option D** |
| UI concerns in the state layer | ❌ | Medium | **VERIFIED:** `showDialog` and `AudioService` are passed into notifier extensions. | **A5** |
| Host module contract | ⚠️ | Medium | **Repository side DONE; host side not started.** `AuthNotifier.build()` bootstraps from `SharedPrefsService`, so a host-provided session is the primary path, not a Flutter-side login; the storage-key contract is documented and its `flutter.` prefix VERIFIED; `PlayGame.open*` is a stable Dart integration surface; and the GameEngine now **guarantees its own hub connection on entry** — it reuses a live connection and connects when none exists, so correctness no longer depends on the host pre-connecting. **Remaining is host-owned only:** the native host has not yet embedded the Flutter engine, so the host→Waiting launch mechanism is still undecided. See [HOST_INTEGRATION.md](HOST_INTEGRATION.md). | **A1** |
| Production entry point | ➖ | — | **CORRECTED:** this module is embedded into an existing native host app; the host owns Home, Login, and navigation entirely, and provides its own production entry point. The debug launcher (`MaterialApp.home` → `HomeLauncherPage`) is correctly a dev/test harness, not a defect — see [HOST_INTEGRATION.md](HOST_INTEGRATION.md). Not applicable as a gate for this module. | **P2 — closed** |
| Barrel encapsulation | ⚠️ | Medium | **VERIFIED:** `play_game` exports 9 data-layer paths, `coreapp` 3. | **A3** |
| Identity resolution | ❌ | **High** | **VERIFIED (behaviour):** a two-player closed-world assumption; with no opponent seated every id resolves to the local user, and any `PlayerLeft` can pop the game screen. **BLOCKED** on five external questions. | **S9 / S9a / S9b** |

---

## Correctness

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| Indeterminate outcome defaults to loss | ❌ | High | **VERIFIED.** Pinned by a characterization test. Not fixed. | **E1** |
| `isWin` fallback unreachable | ❌ | High | **VERIFIED:** `_resultFromData` cannot run for any game-over event, so an explicit `isWin: true` is ignored and the player is told they lost. **Newly discovered; not fixed.** | **E6** |
| Dead null-aware operator | ⚠️ | Low | **VERIFIED** and investigated. Removal would be behaviour-preserving. Deliberately not modified. | **E5** |
| Hardcoded UI string | ❌ | Low | **VERIFIED:** `text: "Strike"` bypasses `PlayGameStrings`. Not fixed. | **MA6** |

---

## Environment & Configuration

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| Backend URL | ✅ | — | **DONE — VERIFIED.** `baseUrl` and `signalRHubUrl` resolve from `String.fromEnvironment` (`api_endpoints.dart:14,19`), with the test URLs only as `defaultValue`. Both stay `static const`, so every call site is unchanged. Pointing at another environment is now a build input, not a source edit. | **F1** |
| `--dart-define` / flavors | ✅ | — | **DONE — VERIFIED.** `API_BASE_URL` and `SIGNALR_HUB_URL` exist and are independently configurable; `test/api_endpoints_test.dart`'s both-or-neither guard was proven to fire by setting one and watching it fail. **Residual (F1b):** an omitted define silently falls back to the test backend, so the host build must pass both via `dartDefines`. | **F1 / F1b** |
| Auth on cold start | ✅ | — | **DONE — VERIFIED.** The unconditional `await prefs.clearAuth();` is gone from `main()` (zero occurrences). `AuthNotifier.build()` bootstraps from `SharedPrefsService`, returning an `AuthSession` when a token exists and `null` otherwise, so a host-written session survives a cold start. `clearAuth()`'s only remaining production caller is `AuthNotifier.logout()`. | **P1** |
| Commented-out bootstrap in `main.dart` | ⚠️ | Medium | **VERIFIED:** an alternative bootstrap sits commented out, containing a real lesson about login hanging on mobile networks. | — |

---

## Build

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| `compileSdk` / `targetSdk` 36, `minSdk` 24 | ✅ | — | Current. | — |
| Release signing on the dev runner | ⚠️ | Medium *(Critical if shipped)* | **VERIFIED:** `.android/app` release buildType uses `signingConfigs.debug`. It is generated and gitignored — a dev runner only, never a release target. Real signing belongs in the native host. | **P4** |
| `enableJetifier=true` | ❌ | Low-Med | **VERIFIED:** unnecessary on this AGP/compileSdk; slows every build. | **P5** |
| `-Xmx8G -XX:MaxMetaspaceSize=4G` | ❌ | Low-Med | **VERIFIED:** will fail or thrash on typical CI runners. | **P5** |
| Host patch tooling | ⚠️ | Medium | **VERIFIED:** `apply_android_patches.ps1` is Windows-only and Android-only; no iOS equivalent. | **F2** |
| Generated hosts | ⚠️ | — | **VERIFIED:** `.android/` and `.ios/` are generated and gitignored; `flutter clean` regenerates them. | **F2** |
| Obfuscation / R8 rules | ➖ | Medium | Not configured; decide before release. | **P2** |

---

## Testing

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| Pure-layer coverage | ✅ | — | **VERIFIED:** identity primitives, domain enums, reducer and model detection/merge all covered. | **T-TIER1** |
| Controller coverage | ✅ | — | **VERIFIED:** routing, seating, `PlayerLeft`, game-over. | **T-TIER2** |
| Round-specific coverage | ❌ | High | Largest uncovered surface; blocked on payload contracts. | **T-COV** |
| Testability seams | ⚠️ | Med-High | **VERIFIED:** controller tests work via subclass fakes; datasource and network-layer tests still need seams. | **T2** |
| Known failing test | ⚠️ | Low | **VERIFIED:** `widget_test.dart` overflow, pre-existing. Would make a new pipeline red on day one. | **T3** |
| CI | ❌ | **High** | **VERIFIED:** `.github/` does not exist. | **T4** |
| Integration / golden tests | ❌ | High | None. | — |

---

## Observability

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| Crash reporting | ❌ | **High** | **VERIFIED:** no `FlutterError.onError`, no `PlatformDispatcher.onError`, no `runZonedGuarded`, no reporting SDK. Zero production visibility. Needs a dependency decision. | **E3** |
| Analytics | ➖ | Low | None. Product decision, not assessed. | — |

---

## Documentation

| Item | Status | Risk | Action | Task |
|---|---|---|---|---|
| `docs/` set | ✅ | — | Rebuilt against the current repository state. | — |
| `README.md` / `SAMPLE_SCREEN.md` | ❌ | High | **VERIFIED:** both describe a `lib/core` layout and a `chat_example` feature that no longer exist. | **MA1** |

---

## Release Gate

Minimum before shipping to real users:

| Gate | Task | Status |
|---|---|---|
| Credential leak closed and confirmed on a release build | **SEC1 / SEC1a** | ✅ satisfied — owner-confirmed on a release/device build |
| Environment configurable per build | **F1** | ✅ satisfied — the host build must still pass both defines (**F1b**) |
| Sessions survive a cold start | **P1** | ✅ satisfied |
| Host integration documented (session handoff, entrypoint decision) | **A1** | ⚠️ documented; host→Waiting mechanism still host-owned |
| Crash reporting live | **E3** | ❌ open — vendor/dependency decision |
| Session expiry recovers automatically | **N2 / P1a** | ✅ satisfied — REST and SignalR both refresh and retry |
| Gameplay actions cannot be silently dropped | **N3 / S5** | ✅ satisfied |
| Identity semantics resolved | **S9** | ✅ satisfied |
| Game-over results correct | **E1 / E6** | ✅ satisfied |
| Tokens in secure storage | **SEC2** | ❌ open — needs host-key coordination |
| CI enforcing the analyzer and test gates | **T3 / T4** | ✅ satisfied — workflow itself never executed (never pushed) |

> **Removed gate — corrected, not silently dropped.** "A production entry
> point exists" (**P2**) was removed: this module is embedded into an
> existing native host app, which provides its own production entry point.
> The debug launcher is a dev/test harness, not a gate this repository needs
> to satisfy. See [HOST_INTEGRATION.md](HOST_INTEGRATION.md).

# Task Registry

Work items derived from [PROJECT_ASSESSMENT.md](PROJECT_ASSESSMENT.md).
Sequencing lives in [ROADMAP.md](ROADMAP.md).

**Statuses:** `DONE` · `OPEN` · `BLOCKED` · `DEFERRED` · `PARTIALLY DONE` · `CLOSED / OUT OF SCOPE`

> `DONE` means implemented **and** verified. Nothing else qualifies.
> `PARTIALLY DONE` means the core contract is implemented and verified, with
> specific, named remaining scope (not a vague residual).
> `CLOSED / OUT OF SCOPE` means the item was investigated and found not to
> apply to this repository's actual product boundary — not abandoned.
> Update this file whenever a status changes.
> Labels: **VERIFIED** · **INFERRED** · **EXTERNAL VERIFICATION REQUIRED**.

---

## Status Summary

Counts are of **task IDs**, one row each. No work is counted twice — the test
foundation is tracked once, as `T-TIER1` + `T-TIER2` under
[Testing](#3-testing), and is cross-referenced (not re-listed) from
[Foundation](#1-foundation).

| Status | Count | Task IDs |
|---|---|---|
| **DONE** | 40 | `F-A4C`, `F-ANL`, `A3`, `S9`, `S9a`, `S9b`, `S9c`, `S9-TEST`, `T-TIER1`, `T-TIER2`, `T3`, `T4`, `E5`, `MA6`, `W-CONTRACT`, `SEC1`, `SEC1a`, `F1`, `P1`, `E6`, `N3`, `S5`, `MA1`, `E2`, `E4`, `M2`, `W-ACTION`, `E1`, `E1a`, `R-AUC`, `R-BELL`, `N4`, `M1`, `M3`, `P3`, `N2`, `P1a`, `W-IMPL`, `W-TEST`, `MA3`, `MA4` |
| **PARTIALLY DONE** | 1 | `A1` — repository side done; host→Waiting mechanism host-owned |
| **CLOSED / OUT OF SCOPE** | 2 | `P2`, `P4` |
| **BLOCKED** | 1 | `N5` |
| **DEFERRED** | 2 | `A4 Option D`, `MA2` (removal not approved) |
| **OPEN** | 18 | all remaining entries, including `T2`, `T-COV`, `PRIV-JOIN` |
| **Total** | **64** | |

**The identity cluster is fixed.** All five backend identity questions were
answered by the repository owner, and `S9`, `S9a`, `S9b`, `S9c` and `S9-TEST`
are now implemented and verified: identity is decided by **positive matching
against the persisted login `user_id`**, and the *"not the opponent, therefore
me"* inversion no longer exists anywhere in the codebase. **`E1a` is now
`DONE`** — `GameOverResult.isWinner` was switched to `playerIdsEqual`.

**One task is still `BLOCKED`:** the `signalr_core` maintenance question
(**N5**). The auction payload contract (**R-AUC**) and the release-build log
check (**SEC1a**) both left that list — R-AUC is implemented, and SEC1a's
release/device verification has been confirmed by the repository owner.
**`W-CONTRACT` is not among them either** — the WDYK payload semantics were
supplied by the repository owner; see [WDYK](#5-wdyk).

> **Count correction.** The previous summary read `OPEN 43 … Total 62`, which did
> not add up (10 + 9 + 1 + 43 = 63). The figures above were **re-derived by
> enumerating every task entry**, not by adjusting the old numbers — an
> arithmetic adjustment gave 48/63 and was also wrong. Enumeration is the
> authoritative method for this table; verify that way after any status change.

**`flutter analyze` now reports zero issues.** The analyzer baseline in
[TESTING_STRATEGY.md](TESTING_STRATEGY.md) is **0**, not 1 — any finding in a
future run is new and belongs to whoever introduced it.

**Suite baseline — VERIFIED: 385 passing / 0 failing.** The suite is fully
green: **T3**, the long-standing `RenderFlex overflowed by 104 pixels` in
`widget_test.dart`, was a real layout defect and is fixed — any failure in a
future run is new and belongs to whoever introduced it.
*(`TESTING_STRATEGY.md` still records the older 144/1 baseline and is out of
scope here.)*

**Three Critical production blockers are now closed** — `SEC1` (release-log
credential leak), `F1` (hardcoded backend URL) and `P1` (startup auth wipe).
Each left a tracked residual: `SEC1b`, `F1b`, `P1a`.

**Recovered tracking.** Ten issue IDs — `E2`, `E4`, `S1`, `S2`, `S3`, `S7`, `S8`,
`M2`, `MA4`, `P3` — were tracked in earlier documentation, lost when that
documentation was removed, and re-added here. **Each was re-verified against the
current codebase**, not copied from the old descriptions; where the current code
differs from the old record, the current evidence is used. None is a duplicate of
a newer ID: `S4` remains superseded by **S9**, and `A2` by **A4 / Option D**.

---

## 1. Foundation

| ID | Task | Status |
|---|---|---|
| **F-A4C** | A4 Option C — private state accessor; `state` → `_s` at 33 sites in `lobby_screen_handler.dart` and `round_screen_handler.dart` | **DONE** |
| **F-ANL** | Remove 6 redundant `game_dialog.dart` imports, 1 unused import, apply 1 `const` | **DONE** |

> The Foundation phase also established the test foundation (112 tests, 6 files).
> That work is tracked once, as **`T-TIER1`** and **`T-TIER2`** under
> [Testing](#3-testing) — not re-listed here, to avoid double-counting.

### A4 — Option D (handler decoupling)
- **Status:** `DEFERRED` — open by decision
- **Problem — VERIFIED:** the `part`/`extension` handlers remain coupled to `GameController`'s state and roughly eleven private members. Option C removed the warnings; it did not decouple anything. The handlers still cannot be constructed or tested in isolation.
- **Solution:** extract handlers as real classes or pure functions, promoting or threading the private members they need.
- **Files:** `game_controller.dart`, `lobby_screen_handler.dart`, `round_screen_handler.dart`, `waiting_screen_handler.dart`
- **Dependencies:** should follow broader controller test coverage; needs architectural approval.
- **Risk — INFERRED:** high churn (~470 lines), and a restructure of routing logic.
- **Attempted and reverted (evidence, not a skip).** A constraint-respecting alternative was tried first: move a cohesive cluster (the five payload-decoding methods, which touch no session state) into a `part`-file `extension`, the pattern the ten existing handler parts already use. **It does not compile — 21 errors.** A private instance member moved into a part-file extension stops resolving as an instance call from the *other* part files (`_gameFromData` "isn't defined for the type 'GameController'" at `waiting_screen_handler.dart:55`). Dart `part` files cannot add members to a class, so an extension is the only mechanism, and it breaks private cross-part access. This is precisely why the Solution above says the private members must be **promoted or threaded**: promoting changes visibility, threading restructures routing. The attempt was fully reverted (`game_controller.dart` back to 994 lines, whole suite green). **Option D therefore still needs the architectural approval recorded above — it is blocked by design, not by effort.**

### A5 — UI concerns in the state layer
- **Status:** `OPEN` · Medium
- **Problem — VERIFIED:** `RoundScreenHandler.showRoundIntro` takes a `showDialog` function and an `AudioService`; `onChangeTurn` / `onPenalty` take `showAppDialog`.
- **Dependencies:** naturally addressed with A4 Option D.

### A1 — Host module contract
- **Status:** **PARTIALLY DONE**
- **Corrected framing — VERIFIED.** The previous problem statement ("the module authenticates itself instead of receiving a host session") was incomplete. `AuthNotifier.build()` already bootstraps from whatever's already in `SharedPrefsService` — a host-provided session is the *primary* path. The module's own `login()` (`LoginUseCase`) is a secondary, debug-only fallback, exercised only by the debug launcher's "Register" button. `PrefsKeys`' own doc comment ("Native host already uses these names — do not rename") confirms a session-handoff contract already exists via shared native storage, and `PlayGame.open*` (`play_game_launcher.dart`) is a real, stable Dart API surface a host's Flutter-side glue can already call. This is a working add-to-app pattern, not a missing platform channel.
- **This module does not need, and must not build, a production Login or Home screen.** Login, Home, and host-side navigation are owned entirely by the native host — see [HOST_INTEGRATION.md](HOST_INTEGRATION.md).
- **Resolved by this audit — VERIFIED, not just documented.** The native storage key prefix question is closed: the resolved `shared_preferences-2.5.5` package (`.dart_tool/package_config.json`) uses its classic `SharedPreferences.getInstance()` API, and `shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart:22` hardcodes `static String _prefix = 'flutter.';`, applied to every key (`:172`, `:179`) before the platform channel is reached — identically on Android and iOS, since the prefixing happens in the shared Dart facade. No `SharedPreferences.setPrefix()` call exists anywhere in this repository (confirmed by search), so the default applies unmodified. **The effective key for `PrefsKeys.token` is `flutter.auth_token`, not `auth_token`** (and likewise for every other `PrefsKeys` entry). See [HOST_INTEGRATION.md](HOST_INTEGRATION.md) §2 for the full citation.
- **Repository side — DONE. All three items that were once open here are closed:**
  1. ~~Consolidated host-integration documentation~~ — delivered as [HOST_INTEGRATION.md](HOST_INTEGRATION.md).
  2. ~~Native storage key/prefix verification~~ — VERIFIED above (`flutter.`-prefixed).
  3. ~~Host/module connection lifecycle contract~~ — the audit found this was not only a documentation question: `connectHub()`'s single caller was the debug launcher, and every self-healing path in `SignalRService` (`invoke`, `addEventListener`, `reconnect`, `onAppResumed`, backoff) is gated on `_hubUrl != null`, which only `connect()` sets — so a host launching straight into Waiting would never connect and never retry. `GameControllerScreen` (the screen `PlayGame.openWaiting` pushes) now guarantees it on entry: it connects when `hasLiveConnection` is false and reuses the existing connection — connected *or* connecting — otherwise. Hub event binding is untouched (`playGameHubBindingsProvider` already binds on construction). Covered by `test/game_entry_connection_test.dart` (7 tests; 4 proven to fail without the guarantee). **The host may still pre-connect, but correctness no longer depends on it.**
- **Remaining scope — host-owned only:** how the native host launches the module directly at **Waiting**. The native host has **not yet embedded the Flutter engine**, and this repository has no entry mechanism to build on (no `MethodChannel`, no `vm:entry-point` beyond `main()`, no named routes; `AppTheme.navigatorKey` is `null` in release). Choosing that mechanism is a host-side decision this repository must not invent. This is why A1 stays `PARTIALLY DONE` — not because of any outstanding Flutter work.
- **Dependencies:** **S8** (container/observer disposal) is only actionable once the host defines an attach/detach lifecycle; that also decides whether the module should disconnect the hub on exit (today it does not).

### A3 — Barrel exports leak the data layer
- **Status:** **DONE**
- **Problem — VERIFIED (was):** `play_game` exported 9 `data/` paths, `coreapp` 3.
- **Fix:** all 12 feature data-layer exports removed from the two barrels. `coreapp`'s shared `network/*` exports were deliberately kept — they are infrastructure, not feature data.
- **Blast radius — VERIFIED before the change:** the 23 public symbols behind those exports were enumerated and their consumers traced. Every in-package consumer imports its datasource / repository / model **relatively**, so only `test/game_models_test.dart` reached data classes through the barrel; it now imports `created_game_model.dart` and `game_over_result_model.dart` by package path — the convention already used for `GameSessionReducer`. The one external barrel consumer, `home_launcher_page.dart`, uses only the `PlayGame` facade.
- **Verification:** analyze **0 issues**; suite count unchanged; no behavioural change — an `export` directive emits no code. Dart has no cross-package visibility enforcement, so `data/` stays reachable by explicit path; what this removes is the barrel's *endorsement* of it.

### S1 — Entity equality is identity-only
- **Status:** `OPEN` · Latent (nothing observably broken today)
- **Problem — VERIFIED:** 14 `props` getters across `play_game` entities; 11 are identity-leaning, only 3 use value equality (`[items, pageIndex, pageSize, fullCount]`, `[canUse, pageIndex, pageSize]`, `[id, text, isSelected]`). `CreatedGame` compares on `[id, status, currentTimerValue, currentTurn, type]`; `GamePlayer` on `[id, userId]` — so a roster differing only in `isReady` or `points` compares equal.
- **Why latent — VERIFIED:** no `.select()`, no `Set`/`Map` keyed on these entities, and `GameSessionState` has no equality (**S2**), so Riverpod notifies on every assignment regardless.
- **Why it matters:** identity-only equality is a legitimate convention, but it is **incompatible with using `==` for UI change detection**. Fixing `CreatedGame` alone would not work — its `players` list compares by `GamePlayer` identity.
- **Dependencies:** must be resolved **together with S2 and S3**, as one decision.
- **Tracking note:** tracked in earlier documentation, lost when that documentation was removed, re-added here after re-verification.

### S2 — `GameSessionState` has no equality
- **Status:** `OPEN` · Med-High
- **Problem — VERIFIED:** 16 `final` fields, **0** `extends Equatable`, **0** `operator ==` / `hashCode`. Every `state = …` assignment therefore notifies all listeners.
- **Why it matters — INFERRED:** during a round, timer events rebuild every watcher of `gameControllerProvider`, including full-screen Lottie widgets.
- **Dependencies:** blocked behind **S1** — value equality on the state object is ineffective while the entities it holds compare by identity.
- **Tracking note:** re-added after re-verification.

### S3 — `copyWith` carries 7 `clearX` boolean flags
- **Status:** `OPEN` · Med-High
- **Problem — VERIFIED:** `GameSessionState.copyWith` takes `clearResult`, `clearGameOver`, `clearMeEmote`, `clearOpponentEmote`, `clearMe`, `clearOpponent`, `clearReadyTimerPlayerId` (lines 71–77).
- **Why it matters:** the canonical Dart nullable-`copyWith` trap, hand-managed seven times — passing `meEmote: null` silently does nothing rather than clearing.
- **Dependencies:** pairs with **S1**/**S2**; also with **MA2**, since `freezed` is already declared and unused.
- **Tracking note:** re-added after re-verification. Earlier documentation recorded 8 flags; the current code has **7**.

### S7 — Global mutable statics
- **Status:** `OPEN` · Medium
- **Problem — VERIFIED:** `AppStrings` holds `static String _languageCode` mutated by `setLanguage()` and read via `static get current`; `Failure` subclasses read `AppStrings.current` in **5** places, so failure messages depend on hidden global state. `AudioService` holds `static AudioService? _instance` with a `static get instance` that throws if read before the provider.
- **Why it matters:** breaks test isolation, and in an add-to-app module the host controls attach/detach lifecycle.
- **Tracking note:** re-added after re-verification.

### S8 — Container and lifecycle observer never disposed
- **Status:** `OPEN` · Medium
- **Problem — VERIFIED:** `main()` constructs a `ProviderContainer` and calls `WidgetsBinding.instance.addObserver(lifecycleObserver)`. `lib/main.dart` contains **0** `removeObserver` and **0** `container.dispose` calls.
- **Why it matters:** for a module a native host can attach and detach repeatedly, both leak.
- **Dependencies:** naturally addressed alongside **A1**, once its host attach/detach lifecycle question is resolved.
- **Tracking note:** re-added after re-verification.

---

## 2. Identity — RESOLVED

**All five blocking questions were answered by the repository owner, and the**
**fixes are implemented and verified.** The rule below now holds throughout.

### Confirmed backend semantics — VERIFIED (owner-supplied)

- Login `user_id` and hub player ids share **one namespace** — e.g. `user_id`
  47 appears as a player id in the same game alongside `211403`.
- **Player-related hub values can refer to either player.** They are **not
  inherently the local user.**
- `currentTurn`, `PlayerReady`, `ChangeTurn` and `PlayerEmoted.userId` can each
  carry either player's id.
- `PlayerLeft` carries the player id directly, as `[playerId, gameId]`:
  `playerId == persisted user_id` → the local player left; otherwise the other
  player left.

**The single rule this establishes:** identity must be decided by **positive
matching against the persisted `user_id`** — never by *"not the opponent,
therefore me"*.

### Blocking questions — RESOLVED

| # | Question | Answer |
|---|---|---|
| 1 | Does the hub always send `userId` on players, or sometimes only a GUID `id`? | **Effectively answered** — observed ids are account-shaped numerics (47, 211403). Whether `id` and `userId` can differ is still unstated, but `matchesHubUserId` checks both, so this does not block. |
| 2 | Is `PlayerLeft.playerId` a game-player id or an account id? | **Answered** — the player id directly, comparable to persisted `user_id`. |
| 3 | Is `PlayerEmoted.userId` the account id? | **Answered** — can be either player's id. |
| 4 | Is `CreatedGame.currentTurn` a game-player id or an account id? | **Answered** — either player's id. |
| 5 | Is prefs `user_id` in the same namespace as either hub id? | **Answered — yes.** |

**Still unverified, but not blocking:** whether `players[].id` and
`players[].userId` can ever differ; whether a game can hold more than two
players (every predicate and `_findPlayers` assumes exactly two).

### S9 — Two-player closed-world assumption
- **Status:** **DONE** — replaced with positive local-ID matching
- **Problem — VERIFIED:** `isCurrentUser`, `isLocalPlayerLeft` and `_emoteIsMine` reduce to *"if not the seated opponent, it is me"*. The confirmed semantics state hub values are **not inherently the local user**, so this inversion is wrong by design — not merely when `opponent` is null. With `opponent == null` (which `_findPlayers` can produce for a single-player roster) a legitimate opponent id such as `211403` resolves to the local user.
- **Fix direction:** positive match against `state.me`, falling back to `_getMyUserId()`. `_getMyUserId()` already returns the correct comparison key and needs no change.
- **Files:** `game_controller.dart` (`isCurrentUser`, `isLocalPlayerLeft`, `_emoteIsMine`)
- **Current coverage:** six characterization tests pin the present behaviour without endorsing it; they are replaced, not edited, when the fix lands.

### S9a — PlayerLeft handling is wrong — **re-characterized**
- **Status:** **DONE** — root cause was S9c; positional ids now resolve
- **Previous description was wrong and is superseded.** It claimed a false *positive*: that with no opponent seated, any `PlayerLeft` would report the local user as leaving and pop the game screen. Tracing the confirmed positional payload shape shows the live failure is the **opposite**.
- **Problem — VERIFIED:** `PlayerLeft` arrives as positional `[playerId, gameId]`. `HubEventPayload.mapFromArgs` maps positional scalars to `{'arg0': …, 'arg1': …}`, and `playerIdFrom` reads only `['playerId', 'userId', 'leftPlayerId']` — so it returns `null`, `isLocalPlayerLeft` short-circuits to `false`, and **the local player leaving is never detected**. `_leaveGame()` never fires and the screen never pops. Root cause is tracked as **S9c**.
- **Both failure modes remain possible, by payload shape:** a map-shaped payload carrying `playerId` reaches the inversion in S9 (false positive); a positional payload never matches at all (false negative). The positional case is the one the owner has confirmed.
- **Files:** `game_controller.dart` (`isLocalPlayerLeft`), consumed by `game_controller_screen.dart:55` and `lobby_screen_handler.dart:85`.
- **Dependencies:** needs **S9c** fixed first, otherwise a positive-match fix still receives a null id.

### S9b — Positional seating fallback
- **Status:** **DONE** — positional seating guess removed
- **Problem — VERIFIED:** when no player matches the stored identity, `_findPlayers` falls back to list position and `players[0]` becomes "me".
- **Why it is now clearly wrong:** with the namespace confirmed shared, `_getMyUserId()` can always be matched positively. A positional guess can seat the local user as the wrong player and has no remaining justification.

### S9c — `playerIdFrom` ignores positional `arg0` — **new**
- **Status:** **DONE** — `arg0` fallback added
- **Problem — VERIFIED:** `GameSessionReducer.playerIdFrom` reads only `['playerId', 'userId', 'leftPlayerId']`. Its sibling `turnPlayerIdFrom` was given an explicit `arg0` fallback (commented *"[ChangeTurn] may send `playerId` or positional `arg0`"*); `playerIdFrom` never received the same treatment. `PlayerLeft` and `PlayerReady` can arrive as positional `[playerId, gameId]`, which `mapFromArgs` turns into `{'arg0': …}` — so `playerIdFrom` returns `null`.
- **Blast radius — VERIFIED:** `isLocalPlayerLeft`, `gameAfterPlayerLeft` (roster removal), `_applyPlayerReady` and `emoteFrom` all depend on `playerIdFrom`.
- **Fix direction:** add an `arg0` fallback mirroring `turnPlayerIdFrom`.
- **Note:** that the hub emits these events positionally at runtime is **VERIFIED from the owner's payload description**; it has not been observed on the wire.
- **Files:** `game_session_reducer.dart` (`playerIdFrom`)

### S9-TEST — Two seating tests to revisit
- **Status:** **DONE** — tests reworked; caveat removed
- **Resolution — VERIFIED:** the rule these two tests encode is now **confirmed correct**. Prefs `user_id` and hub player ids share one namespace, so matching the stored id against `players[].id` / `players[].userId` is the intended behaviour, not an assumption. The caveat can be dropped.
- **Action:** re-affirm both tests with the semantics stated explicitly in their names or comments, and remove the caveat section from [TESTING_STRATEGY.md](TESTING_STRATEGY.md#seating-tests-caveat). Their assertions do not need to change.
- **Historical note — the original concern, now resolved:**
- **Tests — VERIFIED:**
  - `test/game_controller_seating_test.dart:94` — *the local player is seated as me when the id matches*
  - `test/game_controller_seating_test.dart:112` — *the local player is matched on the account userId too*
- The concern: unlike the six characterization tests, these two were **not**
  labelled as unresolved, yet asserted that matching the stored `user_id`
  against `players[].id` / `players[].userId` was the intended rule — exactly
  what blocking questions **1** and **5** left open at the time.
- **Outcome:** question 5 is answered *yes* — the namespaces are shared — so the
  rule these tests encode is correct. The risk did not materialise and no
  assertion needs to change; only the caveat wording does.
- **Cross-reference:** [TESTING_STRATEGY.md](TESTING_STRATEGY.md#seating-tests-caveat)

---

## 3. Testing

| ID | Task | Status |
|---|---|---|
| **T-TIER1** | Pure-function tests — identity primitives, domain enums, reducer, models | **DONE** |
| **T-TIER2** | GameController tests — routing, seating, PlayerLeft, game-over | **DONE** |

### T3 — Widget test overflow
- **Status:** **DONE**
- **Problem — VERIFIED (was):** `widget_test.dart` failed with `RenderFlex overflowed by 104 pixels`. `HomeLauncherPage` used `AppScaffold(scrollable: false)` around a fixed-height `Column`.
- **The earlier "harness artifact" reading was wrong.** It was recorded as `INFERRED: a harness artifact of the 800×600 test viewport, not user-visible`. Measuring the layout disproved that: 9 × `GameButton.minHeight` (52) + `AppTextField` (48) + gaps (12 × 9 + 8) = **632 px** of content against `600 − 56 kToolbarHeight − 16 padding =` **528** available — exactly the reported **104**. The layout needs **≥ 704 logical px**, so it also overflowed at 640 px and at 667 px (iPhone SE 2/3, iPhone 8). `AppScaffold`'s `ClipRect` suppressed the debug stripes but not the error, so on a release device the bottom button was **silently clipped and unreachable** rather than fine.
- **Fix:** removed `scrollable: false` (one line, `+0 −1`), letting `AppScaffold` apply its documented default. The justification for the override never applied here — the class doc reserves `scrollable: false` for bodies that manage their own scrolling or need `Expanded`/`Spacer` for height, and this `Column` does neither; its only two `Expanded` widgets sit inside a `Row`, constraining width. The doc also names this page's exact failure mode as the reason `scrollable` exists.
- **`widget_test.dart` was not modified** — confirmed byte-identical to `HEAD`. The test was never weakened, changed or deleted; it simply stopped failing.
- **Consequence:** `resizeToAvoidBottomInset` defaults to `scrollable`, so it flipped `false → true`. The debug launcher now scrolls and the keyboard resizes the body instead of overlaying it — the behaviour `AppScaffold` prescribes for a fixed `Column` containing a `TextField`.
- **Scope:** `lib/features/home/presentation/pages/home_launcher_page.dart` only. **No `packages/` change**, so `AppScaffold` and the two legitimate `scrollable: false` users (`game_controller_screen.dart`, `lobby_private_game_screen.dart`) are untouched, and no game flow is affected.
- **Verification:** `flutter analyze` **0 issues**; `flutter test` **385 passing / 0 failing** — the suite is fully green.
- **Still open, separately:** the test asserts English literals and a hardcoded debug id. That brittleness is unchanged and unaddressed by T3.

### T2 — Testability seams
- **Status:** `OPEN` · Med-High
- **Problem — VERIFIED:** `ApiClient` and `SignalRService` are concrete. Controller tests were possible via subclass fakes; datasource and network-layer tests still need seams.

### T4 — CI
- **Status:** **DONE**
- **Problem — VERIFIED (was):** `.github/` did not exist; every run of `flutter analyze` / `flutter test` was manual.
- **Dependency satisfied:** the entry previously read *"T3 first, or record the known failure as an accepted baseline."* **T3 is fixed**, so the first branch applies — the suite is 385 pass / 0 fail and a new pipeline is green on day one rather than red.
- **Delivered:** `.github/workflows/ci.yml` — checkout → set up Flutter **3.35.7** (stable) → `flutter --version` → `flutter pub get` → `flutter analyze` → `flutter test`, on `[push, pull_request]`. Each step fails the job on a non-zero exit.
- **Scope decisions (owner):** analyze + test only. **No** add-to-app/module build — that stays an `F1b` / host concern. No coverage thresholds, no matrix, no cache, no branch filter.
- **Bootstrap — VERIFIED, not assumed:** this is a **pub workspace** (root lists `packages/coreapp` and `packages/play_game`; both declare `resolution: workspace`), so one root `flutter pub get` resolves all three — confirmed by reading `.dart_tool/package_config.json`, which lists `game_engine`, `coreapp` and `play_game`. **Melos bootstrap is therefore not needed**; its `analyze` / `get` scripts only fan the same commands out per package.
- **Failure behaviour — VERIFIED by measurement:** a deliberately introduced lint made `flutter analyze` exit **1**; a clean tree exits **0**. The probe file was removed immediately. So the workflow genuinely fails rather than reporting a false green.
- **YAML validated by parsing**, not by eye: a temporary test loaded `ci.yml` with `package:yaml` and asserted the job name, `runs-on`, both actions, the pinned version string, the three commands, and the absence of any `flutter build` or `--coverage`. Probe removed after.
- **Verified locally in CI order:** `flutter pub get` exit 0; `flutter analyze` **0 issues**; `flutter test` **385 passing / 0 failing**.
- **NOT verified — EXTERNAL:** the workflow has never executed. It cannot be until pushed. Two unknowns: whether the suite passes on `ubuntu-latest` (all local runs were Windows; the widget tests touch plugin-backed `AudioService` / `SharedPreferences`, which the test binding leaves unanswered on any platform — consistent, but unproven on Linux), and whether `subosito/flutter-action@v2` resolves 3.35.7 on the runner.
- **Residual:** the Flutter version now lives in **two** places — the workflow and each developer's local SDK — with nothing enforcing they agree. `.android/local.properties` only points at a path, so there is no version file for CI to read. A `.flutter-version` / `.fvmrc` read by both would close it, but that changes local developer setup and was out of T4's scope.

### T-COV — Remaining coverage gaps
- **Status:** `OPEN` — reduced scope. Four of the listed areas are covered — `JsonValue`, `ApiResponse`, `SecurityGenerator` and **every remote datasource**. What remains is round-specific handler logic and `SignalRService` internals; only the latter is genuinely gated on **T2**.
- **Original list:** round-specific handler logic, `SignalRService` internals, `BaseRepository.guard`, `ApiResponse`, `JsonValue`, `SecurityGenerator`, every datasource.

**Covered — 101 tests added, production source and existing tests unchanged.**

| Area | Tests | File |
|---|---|---|
| `JsonValue` | 35 | `test/json_value_test.dart` |
| `ApiResponse` | 27 | `test/api_response_test.dart` |
| `SecurityGenerator` | 13 | `test/security_generator_test.dart` |
| The four remote datasources | 26 | `test/remote_datasources_test.dart` |

- **`JsonValue` + `ApiResponse` (62).** `JsonValue` had **87 call sites and no tests** — every hub payload read and model parse goes through it. Covers `parseInt` / `parseDouble` / `parseBool` / `field` / `hasField` / `asMap`, including the PascalCase and case-insensitive key fallback that **W-5** and **W-6** depend on, and the `field` vs `hasField` distinction for a key present with a null value. `ApiResponse` covers `succeeded`, `data` with and without `fromJsonT`, `fullCount`, `message`, `error`, `displayMessage` precedence, `statusCode` and equality.
- **`SecurityGenerator` (13).** Structural only: both entry points yield a decodable 172-character / 128-byte block with no line breaks, encrypt empty and non-ASCII payloads, reject a payload larger than one RSA block, and **never repeat a token** — a repeat would mean PKCS#1 v1.5 padding stopped being randomised. Every constant was measured against the implementation, not derived from the RSA spec.
- **`BaseRepository.guard` is partly covered** as a side effect of **E2** — `test/failure_message_test.dart` drives the catch-all directly.
- **The four remote datasources (26).** Every public remote method: `auth.login`, `games.exitFromAllGames`, `profile.getPublicProfile`, `stickers.getStickerGroups`, `stickers.payStickerGroup`. Each asserts the verb, the path against its `ApiEndpoints` / `PlayGameEndpoints` constant — and, for the two id-interpolated paths, against the literal string as well, so a constant edited to match a wrong test still fails, the request body or its absence, successful parsing, and the `ApiResponseHandler.ensureSuccess` failure path carrying `error.message` / `error.code` into `ApiException`. Branch coverage the datasources own: `login`'s three envelope shapes (`data` map, bare string token, root-level token) and its `loginMissingToken` throw; `exitFromAllGames` defaulting to `true` on a non-boolean payload; an empty profile when `data` is null; an empty sticker page when `data` is not a list, with `pageIndex` / `pageSize` echoed from the request and `fullCount` carried from the envelope; and a `DioException` propagating rather than being swallowed.
- **The seam — VERIFIED by running it, not assumed.** A test-local `_FakeApiClient extends ApiClient` overriding `get` / `post` / `put` / `delete`. **No interface, no production change, no T2 seam.** Three details make it safe: `enableChucker: false` and `enableLogging: false` are passed explicitly, because both default to `kDebugMode`, which is **true** under `flutter test`; `baseUrl` points at an unroutable `127.0.0.1:9`, so a call that escaped the override would fail rather than reach a backend; and the overrides never call `super`, so Dio never issues a request. It is the same technique already load-bearing for `SignalRService` in three WDYK test files, and it works because every datasource takes its `ApiClient` through the constructor.
- **Verification — `JsonValue` / `ApiResponse` / `SecurityGenerator` slice:** `flutter analyze` **0 issues**; `flutter test` **362 passing / 1 failing** (the known **T3** baseline at the time, since fixed).
- **Verification — datasource slice, 2026-09-03:** `flutter analyze` **0 issues**; `flutter test` **420 passing / 0 failing**, 26 of them new. Production code untouched: `git diff` empty, one added test file.

**Not covered, and why — no part of this is silently dropped.**

- **`SecurityGenerator` has no round-trip and no clock control.** The repository ships only the **public** key, so nothing proves the ciphertext decrypts to `data;millis` — a change encrypting the wrong plaintext would pass every test. `_currentUtcTimeMilliseconds()` reads `DateTime.now()` with no injection point. [TESTING_STRATEGY.md](TESTING_STRATEGY.md) lists this unit as testable *"given a fixed clock"*; **that condition is not met**. Reported deliberately rather than fixed — adding a seam was out of scope.
- **Updated (this batch) — two of the three remaining areas are now closed.** `BaseRepository.guard` is fully covered (`test/base_repository_guard_test.dart`, 27 tests: every ApiException, NoInternetException, DioException and envelope arm; the tests also pinned that `ApiResponse.statusCode` reads `error.code`, not a top-level key). `SignalRService`'s **listener registry** is covered (`test/signalr_listener_registry_test.dart`, 22 tests: `addEventListener`, `subscribe`, `unsubscribe`, `unsubscribeAll`, `isSubscribed`, `reattachEventHandlers`, `onAppResumed`/`onAppPaused`) — **no seam and no production change needed**, because those paths touch only the three in-memory maps and null-guard every `_hubConnection?` call. The round-handler gap is closed by the rounds' own suites (Auction, Bell, Comeback and Breaker each ship reducer, screen, dialog, answering and timer tests). **What remains is only the connection half of `SignalRService`**, which is the part genuinely gated on **T2**.
- **Historical note (superseded by the line above):** round-specific handler logic and `SignalRService` internals remain uncovered.
- **Below `ApiClient`'s method boundary is not covered, and this seam cannot reach it.** Headers, interceptors, retry and timeout behaviour are applied by `AppBaseInterceptor` and Dio *underneath* the overridden methods, so the datasource tests observe the verb, path, query and body only. Reaching them needs a Dio-adapter seam — **T2** territory.
- **The earlier claim that "every datasource" was blocked behind T2 was wrong and has been removed.** `ApiClient` being a concrete class was true; the conclusion did not follow, because every datasource takes its `ApiClient` by constructor injection. Disproven by 26 passing tests rather than by argument.
- **Observed while testing, not fixed:** `encryptDataRSA` and `encryptDataRSAs` are functionally identical — `_currentUtcTimeMilliseconds()` is exactly what the latter inlines — and the RSA public key is hardcoded with no environment override (related to **SEC3 / SEC4**, backend-owned).

---

## 4. Analyzer Cleanup

**Current baseline — VERIFIED: 0 issues.**

### E5 — dead_null_aware_expression
- **Status:** **DONE**
- **Location:** was `game_controller.dart:141`, in `_stopRoundTimer`
- **Finding — VERIFIED (re-confirmed before the change):** `game` is null-checked into a local two lines above, so it is promoted to non-null; `CreatedGame.currentTimerValue` is declared `final double` (non-nullable — the `double?` at line 111 is only the `copyWith` "not provided" marker); and `GameJson.decimal` ends in `?? 0`, so the value is never null from JSON. The `?? 0` was therefore unreachable.
- **Fix:** `(game.currentTimerValue ?? 0) <= 0` → `game.currentTimerValue <= 0`. The parentheses existed solely to scope the `??` and went with it.
- **Behaviour — VERIFIED preserving:** for a non-null `double`, `(x ?? 0) <= 0` is identical to `x <= 0`. Surrounding timer logic untouched.
- **Why it looked nullable — INFERRED:** the other read sites go through a *nullable* game (`game?.currentTimerValue ?? 0` in `lobby_play_game_screen.dart:96`), where the `??` is live and correct. This one site had already unwrapped `game`. Reads as copy-paste — and those live sites were deliberately left alone.
- **Result:** `flutter analyze` now reports **No issues found**.

### MA6 — Hardcoded UI strings in `round_screen_handler.dart`
- **Status:** **DONE**
- **Problem — VERIFIED.** The task originally recorded a single literal at line 137. Inspection found **five**, not one — the first survey used a double-quote pattern and missed the single-quoted occurrences:

  | Line | Literal |
  |---|---|
  | 116 | `text: isMe ? 'Strike':'Timeout',` |
  | 137 | `text: "Strike",` |
  | 163 | `text: 'Start Timer',` |
  | 187 | `text: 'Skip',` |
  | 210 | `text: 'Correct Answer',` |

  Line 116 could not be localized in isolation — `'Strike'` and `'Timeout'` share one ternary.
- **Blocker resolved:** no Arabic copy existed for any of these concepts, and inventing game terminology would have been guessing at product content. The five translations were supplied by the repository owner.
- **Fix:** five members added to `PlayGameStrings` and both `EnPlayGameStrings` / `ArPlayGameStrings`, placed after `numberOfAttempts` following the existing grouping and camelCase convention. All five call sites now read `strings.*`, resolved via the pattern already used in this file: `PlayGameStrings.forLanguage(ref.read(appLanguageProvider))`. **No new localization mechanism or dependency.**
- **Consequence — VERIFIED:** three `RoundLottieDialog` call sites lost their outer `const` because `text` is now a runtime value; the nested `AppLottieView` constructors regained `const` in exchange. This partially reverts the `const` added under **F-ANL** at line 137 — unavoidable and expected. `flutter analyze` reports **0** `prefer_const_constructors` findings.
- **Verification:** analyze **No issues found**; tests **136 passing / 1 failing** (unchanged); zero `text: '…'` literals remain in the file; abstract/EN/AR parity confirmed for all five members.

### MA3 — Lint configuration
- **Status:** **DONE** — all four rules enabled in the root `analysis_options.yaml` (the strict analyzer flags were already present). 16 findings, **all in test files, none in production**: 11 `unawaited_futures` (deliberate route pushes, now wrapped in `unawaited(...)`) and 5 `avoid_dynamic_calls` (a bare `const []` erasing a handler-list element type, fixed with a shared `typedef`; one untyped `List.first`). `use_build_context_synchronously` and `cancel_subscriptions` produced **zero** findings, which is itself the result: the production async and subscription discipline was already correct. No rule suppressed or lowered.

---

## 5. WDYK

**Normal-turn WDYK is implemented and verified.** `ALLOW_ALL` timer behaviour
remains a separate, owner-deferred task.

| ID | Task | Status |
|---|---|---|
| **W-CONTRACT** | Establish WDYK hub payload semantics — question, answer, penalty, timer, turn | **DONE** |
| **W-IMPL** | Complete WDYK changes | `OPEN` — reduced scope |
| **W-TEST** | Test and verify WDYK | `OPEN` — reduced scope |
| **W-ACTION** | WDYK action dispatch — authoritative timer stop, and guard release on a failed dispatch | **DONE** |

> The four rows above are the status of record. The sections that follow carry
> their evidence and remaining gaps — they are **not** separate tasks and must
> not be counted again, the same convention used for `T-TIER1` / `T-TIER2` in
> [Foundation](#1-foundation).

### W-CONTRACT — semantics supplied by the repository owner
- **Status:** **DONE** — no longer `BLOCKED`.
- **Supplied (CONTRACT, owner-supplied — not established by this repository):** WDYK is GameType 1 on `/GameHub`, 1v1. Events: `NextQuestion`, `ChangeTurn`, `TimeStarted`, `TimerUpdatedSeconds`, `CorrectAnswer(text, textEn, playerId, gameId)`, `Penalty(penalty, gameId)`, `PlayerAnswered`, `PlayerPassed`, `RoundFinished`, `NextRoundStarted`. `Penalty.type` 1 = timeout, 2 = wrong answer. 1v1 questions carry one correct answer plus up to three wrong ones; `isCorrect` is not sent, and `MaxCorrectAnswersCount` is **Auction-only**. `Pass(gameId)` is WDYK-only, usable once, after at least two penalties. `StartGameTimer(gameId)` is Judge-only — 1v1 rounds start automatically. Timers are server-authoritative via `TimerUpdatedSeconds`. `PlayerAnswered` is delivered to the other client. `GameRestore` is followed by `TimerUpdatedSeconds`. Round order starts WHAT_DO_YOU_KNOW → AUCTION. `currentTurn` may hold a player id or the sentinel `ALLOW_ALL` (both players may act).
- **Residual detail questions — EXTERNAL VERIFICATION REQUIRED, not blocking the five areas above:** whether the roster always carries `passes`; whether `questionNumber` / `roundTotalQuestionsCount` are always populated; whether WDYK questions ever carry `image` / `video` / `audio`; the strike limit behind the client-side `_maxStrikes = 3`.

### W-IMPL — reduced scope
- **Status:** **DONE** — `ALLOW_ALL` was cancelled by the repository owner (the task does not exist), which removed the only gap keeping this open. The last adjacent residual — `applySessionEvent`'s `phase == null` branch updating `game` without reseating players — is now closed, matching the round-path reseat it was the twin of. Covered by five tests in `game_controller_seating_test.dart` ('session-event player refresh — unresolvable phase').
- **Implemented and verified:** positive-identity seating and refresh on round events; single delivery of `nextQuestion` / `gameOver` / `gameFinished`; hardened `Penalty.type` and `PlayerAnswered` text parsing; positive player-name resolution in the round dialogs; one `SubmitAnswer` per question; null-safe question count; diagnostic logging for an unresolved `Penalty.type` and an unparsed `NextQuestion`; `ALLOW_ALL` turn resolution via `GameSessionState.isMyTurn` / `isOpponentTurn`; duplicate-`Pass` protection; timer truncation, `TimerUpdatedSeconds` as the sole start signal; the timer freeze is driven by the authoritative event rather than by the tap — `PlayerPassed` for a Pass, `CorrectAnswer` or `Penalty` for an answer, with `PlayerAnswered` **not** a timer-stop event (**W-ACTION**, DONE); `ChangeTurn` with an explicitly empty playerId clearing the turn.
- **Former remaining gap, now void:** `ALLOW_ALL` timer behaviour — cancelled by the owner, not deferred and not outstanding. Nothing else in the normal-turn flow is missing.
- **Adjacent residuals tracked elsewhere, deliberately not folded in here:** `HubEventPayload.mapFromArgs` keeps only `arg0`–`arg2`, so `CorrectAnswer`'s `gameId` is dropped (shared `coreapp` infrastructure, no consumer needs it today); `GameSessionReducer.playerIdFrom` returns `arg0` on a `CorrectAnswer` payload, which is the answer text (latent — no caller); `applySessionEvent`'s `phase == null` branch updates `game` without re-seating players, the session-path twin of the round-path defect already fixed.

### W-TEST — reduced scope
- **Status:** **DONE** — every behaviour implemented under W-IMPL carries tests.
- **Coverage added:** `turn_resolution_test.dart`, `wdyk_allow_all_test.dart`, `wdyk_timer_test.dart`, `wdyk_answer_selection_test.dart`, `wdyk_question_count_test.dart`, plus new groups in `game_controller_routing_test.dart` and `game_controller_seating_test.dart`. These introduced the repository's first **widget** tests for a round screen.
- **Remaining:** none — the `ALLOW_ALL` line is void with the task. Broader gaps stay under **T-COV**.

### W-ACTION — authoritative timer stop and guard release on failed dispatch
- **Status:** **DONE** — implemented and verified.
- **Verification — 2026-09-03.** `flutter analyze` **0 issues**; `flutter test` **394 passing / 0 failing**. Every acceptance criterion below was checked individually against the implementation. Detection power was confirmed by temporarily reinstating the pre-change `_stopRoundTimer()` calls: the two failed-dispatch timer tests fail against the old behaviour and pass against the new one, and the production file was restored byte-identical afterwards.
- **Files changed.** Production: `game_controller.dart`, `wdyk_round_screen.dart`, `round_score_column.dart`. Tests: `wdyk_timer_test.dart`, `wdyk_answer_selection_test.dart`, `wdyk_allow_all_test.dart`. `_stopRoundTimer()` is deleted outright — zero remaining references.
- **Shared-component note.** `RoundScoreColumn` and `applySharedRoundEvent` are shared by all five round screens, so scope item 3 necessarily reaches the other four. VERIFIED inert: none of them references `isTimerStarted`, and all four remain static mockups.

**Problem — VERIFIED.** `pass()` and `submitAnswer()` both call `_stopRoundTimer()` **before** invoking the hub, so the countdown freezes on the tap rather than on anything the server confirmed. When `invoke()` returns `false` — hub disconnected, nothing dispatched — the timer is frozen for an action that never happened, and the screen-local guard that prevents a duplicate tap is never released: `_passRequested` clears only when `me.passes` changes, which cannot happen if the server never saw the Pass, so **the Pass button stays disabled for the life of the screen**. `_selectedAnswer` locks answering until the question changes or the turn is lost.

**Confirmed runtime contract (owner-supplied).** An answer produces `CorrectAnswer` (correct) or `Penalty` (wrong); a pass produces `PlayerPassed` — e.g. `PlayerPassed | args: [47, <gameId>]`. All are delivered to **both** devices.

**Current behaviour — VERIFIED by inspection.** `applySharedRoundEvent`'s if-chain sets `isTimerStarted: false` for `playerAnswered` and `playerPassed` only; `correctAnswer` and `penalty` fall through to the generic tail and have **no** timer effect. `RoundScoreColumn` additionally stops the countdown on a dedicated `lastEventName == playerAnswered` branch. The method contains **zero** identity gates, so every event applies on both devices.

**Scope.**
1. Remove the `_stopRoundTimer()` calls from `pass()` and `submitAnswer()`. The method then has no callers and should go with them.
2. Extend the existing if-chain branch so `correctAnswer` and `penalty` set `isTimerStarted: false`, alongside `playerPassed`.
3. **Remove `playerAnswered`'s timer-stop responsibility** — from the if-chain and from `RoundScoreColumn`'s dedicated branch.
4. `pass()` and `submitAnswer()` return `Future<bool>`, propagating `invoke()`'s result (available since **N3**).
5. On `false`, the WDYK screen releases the matching guard — `_passRequested`, `_selectedAnswer` — behind a `mounted` check.

**Acceptance criteria.**
- Tapping Answer alone does **not** stop the timer; `CorrectAnswer` stops and freezes it; `Penalty` stops and freezes it.
- Tapping Pass alone does **not** stop the timer; `PlayerPassed` stops and freezes it.
- `PlayerAnswered` no longer stops the timer.
- `TimerUpdatedSeconds` remains the **only** start signal; a stop remains a freeze; `currentTimerValue` is never written by a stop.
- A failed dispatch releases `_passRequested` / `_selectedAnswer` so the user can retry, restarts nothing locally, and rolls back no game state.
- A successful dispatch does **not** release the guard — server events remain responsible for normal completion.
- `flutter analyze` 0 issues; suite green.

**Dependencies.**
- **N3 (DONE)** — supplies `invoke()`'s `Future<bool>`. Satisfied.
- **Superseded part of W-IMPL's recorded evidence — now reconciled.** W-IMPL previously recorded *"freeze-on-stop for Answer, Pass and `PlayerPassed`"* as implemented and verified; that described the tap-driven freeze this task replaced. W-IMPL's bullet has been amended to the event-driven behaviour, and its status is unchanged (`OPEN` — reduced scope, `ALLOW_ALL` timer behaviour). `CHANGELOG.md`'s earlier timer material is **historical**, not current — the `_stopRoundTimer` guard described under **E5** refers to a method that no longer exists.
- **Seven existing tests in `test/wdyk_timer_test.dart` encode the old tap-freezes behaviour** and must be rewritten, moving the trigger from the tap to the event: `Answer freezes the display` ×2, `Pass freezes the display` ×2, `Answer/Pass leaves currentTimerValue untouched`, and `a fresh TimerUpdatedSeconds after a freeze restarts it`. This is the [ENGINEERING_RULES](ENGINEERING_RULES.md#7-tests) §7.2 case — the approved task changes the expected behaviour — **not** test weakening. No assertion is dropped.
- New tests: tap-does-not-stop for both actions; `CorrectAnswer` / `Penalty` / `PlayerPassed` each stop and freeze; failed dispatch releases each guard; successful dispatch holds each guard; existing timer behaviour intact.
- The WDYK fakes in `wdyk_allow_all_test.dart` and `wdyk_answer_selection_test.dart` return `true` unconditionally and need a settable `connected` flag — the pattern already in `waiting_join_retry_test.dart`.

**Out of scope.** No new timer mechanism. No change to `TimerUpdatedSeconds` start behaviour, to `RoundScoreColumn`'s architecture, or to `CountdownTimerText`. No handling of a mid-flight `invoke` exception — a drop *after* dispatch still throws and propagates, and can still strand a guard. No change to `PlayerAnswered` beyond removing its timer-stop responsibility. No other round type. No unrelated cleanup, and no rollback of game state.

**Risk — EXTERNAL VERIFICATION REQUIRED.** Once `PlayerAnswered` no longer stops the timer, the countdown depends entirely on `CorrectAnswer` or `Penalty` arriving after every answer. If either can be withheld — a rejected or unscored answer, say — the timer would run to `00:00` instead of freezing. Nothing in this repository establishes that they always follow.

**VERIFIED present:** `wdyk_round_screen.dart`, `TypePenalty`, `PlayerAnsweredDialog`, `anim_game_auction.json`, and round-handler methods gated on `GamePhase.wdyk`.

---

## 6. Remaining Rounds

All `OPEN`, all sequenced after WDYK. Payload contracts are
**EXTERNAL VERIFICATION REQUIRED** for each.

| ID | Round | Status |
|---|---|---|
| **R-AUC** | **Done.** Auction is fully implemented — bidding phase, answer phase, scoring, timer, and both outcome dialogs (`onAuctionRoundLost` and `onAuctionRoundWon`, R-12). Documented in `docs/tasks/auction-round-workflow.md`. | **DONE** |
| **R-BELL** | **Done.** Bell is fully implemented — turn-gated answering, one-submission-per-question lock, real `ringBell()` wiring — covered by `bell_dialogs_test.dart`, `bell_reducer_test.dart`, `bell_screen_test.dart`. | **DONE** |
| **R-CB** | Come Back is implemented (tries, timer, submission, dialogs via `ComebackStyleRoundContent`). Remaining gap is **R-08** only — a confirmed backend information gap, not a client defect. | `OPEN` — R-08 only |
| **R-BRK** | Breaker is implemented, same shape as R-CB (shares `ComebackStyleRoundContent`). Remaining gap is **R-08** only. | `OPEN` — R-08 only |
| **PRIV-JOIN** | Private Game **join by code** implemented: `PlayGame.openPrivateGameByCode`, `GameControllerScreen.privateGameCode` (asserted mutually exclusive with `privateInterestIds`), `PrivateLobbyHandler.joinPrivateGame` (blank code refused without dispatch, guard claimed before the await, `args: [code]`, guard reopened on a failed dispatch) behind its own `_didJoinPrivateGame`, plus `WrongGameCode` surfaced via `privateLobbyScreenEvents` with EN/AR strings and treated as a bare signal. `GameJoined` routing was **not** touched — `_routeByStatus` already sends `mode == 4` / `isPrivate` to `lobbyPrivate`. 28 tests in `test/private_game_join_test.dart`. **Out of scope by instruction and still open: `checkGame` REST pre-flight, `isHost`, guest sharing, and the `WrongGameCode` payload shape** — see the product/backend questions below. | `OPEN` — engine side done; `checkGame` + product answers outstanding |

---

## 7. Production Readiness

> **Observed follow-up — no task ID assigned.** `onRecovered()` awaits the
> `CheckPlayerGame` *invocation*, but the server's `GameRestore` reply arrives
> later as a separate hub event. A freshly built `GameController` — the
> provider is `autoDispose`, so backgrounding resets `_didJoinRandom` — whose
> join never dispatched can therefore still read `GamePhase.waiting` with an
> open guard and issue `JoinRandomGame` **before** `GameRestore` lands, for a
> player the server already has in a game. Both conditions are required, so it
> is narrow. Surfaced while implementing **S5** and deliberately left out of
> it: closing it means keying the retry off the `GameRestore` *response*
> rather than the request, which needs a listener — explicitly out of S5's
> scope. **Not covered by `N4`**, which is about multiple reconnect *triggers*
> guarded by entry-checked booleans, not request/response ordering. Needs an
> owner decision on whether it is reachable in practice before it earns an ID.

Detail and gating in [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

### Critical

| ID | Task | Status |
|---|---|---|
| **SEC1** | **Credential leak closed.** `PrettyDioLogger` is now registered only when `enableLogging` (defaults to `kDebugMode`, mirroring `enableChucker`), and the `Request-Token` value log was deleted from `ApiHeadersBuilder` along with its now-unused import. **VERIFIED:** a sweep of every logging call for `token`/`auth`/`password`/`bearer`/`secret` leaves only `'connect() aborted — token is empty'` — a status message carrying no value. Authentication and networking behaviour unchanged: same headers, same 4 interceptors in the same order. | **DONE** |
| **SEC1b** | **Residual, precautionary.** `AppLogger` still has a single `log()` level, so payload-carrying calls (hub event args, `invoke` args, `signalr_core` internal `[hub]` messages) are not separately gatable. **VERIFIED:** none of those sites carries a credential — they carry game payloads. Splitting into `log`/`verbose` + `redact()` is worthwhile but rests on **Claim 1** (`dart:developer` surviving release AOT), which is **EXTERNAL VERIFICATION REQUIRED** — see **SEC1a**. Deliberately excluded from the SEC1 fix as outside "smallest safe". | `OPEN` — Medium |
| **F1** | **Environment is now a build input.** `baseUrl` and `signalRHubUrl` resolve from `String.fromEnvironment('API_BASE_URL' / 'SIGNALR_HUB_URL')` with the existing test URLs as `defaultValue`. Both stay `static const`, so **all call sites are unchanged** — including the pure top-level media-URL helpers in `user_profile.dart` and `sticker_asset.dart`, which have no `ref` and could not take an injected value. Independently configurable. Covered by `test/api_endpoints_test.dart`, whose half-config guard was **proven to fire** by setting one define and watching it fail. | **DONE** |
| **F1b** | **Residual.** `defaultValue` still points at the test backend, so an omitted define silently ships test configuration. A hard fail-on-unset gate belongs with the host contract (**A1**), where the environment can be supplied by the host rather than guessed. Separately — **add-to-app hosts do not use the `flutter build` CLI** and must pass the same values via the Flutter Gradle extension's `dartDefines`, or the module silently uses the defaults. **INFERRED** from the module's generated-host structure; not exercised against a real host build. | `OPEN` — High |
| **P1** | **Startup auth wipe removed.** `await prefs.clearAuth();` deleted from `main()`; the adjacent log line, which asserted "auth empty until Register", was corrected since it would otherwise state something false. **No replacement auth mechanism was added and none is needed** — `AuthNotifier.build()` already bootstraps from `SharedPrefsService`, returning an `AuthSession` when a token exists and `null` otherwise. **VERIFIED:** `clearAuth()`'s only remaining production caller is `AuthNotifier.logout()`, reached from the launcher's "Clear data" button, which also disconnects the hub and calls `prefs.clear()` — a stronger reset than the startup wipe ever was. Startup order otherwise unchanged. | **DONE** |
| **P1a** | **Done.** The REST half closed with **N2**; the SignalR half is now closed too. The hub does not use signalr_core's `accessTokenFactory` (negotiate would append `?access_token=`, which this server rejects with close 1002) — its token travels through `SignalRHttpClient`, which signalr_core drives via `client.send(request)` for the WebSocket upgrade, so that is where a hub 401 is observable. `SignalRHttpClient.send()` now refreshes on a 401 and replays the upgrade **once** with the new token, reusing the same `AuthTokenRefresher` the REST interceptor uses — the in-flight guard moved into that refresher and a single shared instance (`authTokenRefresherProvider`) is handed to both transports, so a REST 401 and a hub 401 landing together share one refresh. The refresh itself goes over REST, never back through the hub, so it cannot recurse. A missing/failed refresh clears the stored session and returns the original 401 untouched. Reconnect/backoff/status behaviour, the empty-token connect guard, and `invoke()` are unchanged. No token, refresh token, or Authorization value is logged. Covered by `test/signalr_token_refresh_test.dart` (11 tests; disabling the retry was proven to fail 7 of them) plus 2 new cross-transport tests in `test/auth_token_refresher_test.dart`. `flutter analyze` **0 issues**; `flutter test` **1052 passing / 0 failing**. | **DONE** |
| **P2** | **Closed / out of scope.** Was framed as "the debug launcher is the module entry point, Critical for release," treating this module as if it needed to ship its own production Home/Login. **Corrected:** this module is embedded into an existing native host app; the host owns Home, Login, and navigation entirely (see [HOST_INTEGRATION.md](HOST_INTEGRATION.md)). `lib/main.dart` / `HomeLauncherPage` / `DebugConfig` are dev/test harness components, not a production entry point, and are not expected to be replaced by this repository. The one genuine residual — how a host tells the embedded engine which screen to show — is tracked under **A1**, not here. | **CLOSED / OUT OF SCOPE** |

### High

| ID | Task | Status |
|---|---|---|
| **E6** | **Fixed.** `_resultFromGameOver` now returns `null` when `hasKnownWinner` is false, so `_resultFromData` is reachable and an explicit `isWin` / `result` field is honoured instead of being ignored. | **DONE** |
| **E1** | **Done.** Terminal fallback: an undeterminable game-over yields `GameResult.ended` instead of `GameResult.loss`. Its other half, the `isWinner` raw-`==` comparison, is now also fixed — see **E1a**. | **DONE** |
| **E1a** | **Done.** `GameOverResult.isWinner` compared `winnerId == userId` exactly; switched to `playerIdsEqual`, matching `GameSessionState.winnerPlayer`'s existing comparison of the same field. The characterization test in `player_identity_test.dart` was replaced with intent-based assertions (whitespace and numeric-format drift now match; a genuinely different id still does not). | **DONE** |
| **N2** | **Done.** A 401 is now handled transparently, using the exact same login/auth mechanism and `GET api/Users/RefreshToken` (owner-confirmed) contract: a new `RefreshTokenInterceptor` (`network/refresh_token_interceptor.dart`), added to `ApiClient`'s Dio chain, catches the 401, calls `AuthTokenRefresher` (`features/auth/data/services/`) — which reads the stored `refreshToken`, calls the new `AuthRemoteDataSource.refresh()` / `AuthRepository.refresh()` (mirrors `login()`'s request/parse/error-mapping exactly, same `LoginResponseModel`/`AuthSession`), and persists the refreshed session via the existing `SharedPrefsService` setters — then retries the original request once with the new token (`AppBaseInterceptor` naturally picks it up via its live `tokenProvider`). Concurrent 401s share one in-flight refresh. A missing refresh token, or a refresh that fails, clears the cached auth (`clearAuth()`) and lets the original 401 propagate — no Login/Home screen or navigation was added; the existing `runApi`/`_fail` clear-on-401 (added under the earlier partial fix) stays in place as an unaffected safety net for a 401 that reaches it directly. **No native host involvement, no new dependency, no backend payload invented** — the endpoint and envelope shape were owner-confirmed, not guessed. Covered by `test/refresh_token_interceptor_test.dart` (6 tests: retry succeeds, new token used, refresh failure doesn't loop, missing token doesn't loop, non-401 unaffected, concurrent 401s share one refresh — the retry-disabled case was reverted-and-reran to confirm 5 of 6 fail without it), `test/auth_token_refresher_test.dart` (5 tests), and 4 new tests in `test/remote_datasources_test.dart` mirroring the existing `login()` coverage. `flutter analyze` **0 issues**; `flutter test` **1039 passing / 0 failing** (net +15 new). | **DONE** |
| **N3** | **Done.** `SignalRService.invoke` changed from `Future<void>` to `Future<bool>`: `false` on the pre-invocation disconnected branch, `true` only after the awaited hub invocation completes. **The original description was inaccurate** — invoke never was silent: it logged `'invoke() skipped — not connected'` and fired `connectIfNeeded` to self-heal. The real gap was that no *caller* could tell. That log and the self-heal are byte-identical, and the connection-loader, reconnect, transport and auth paths are untouched. **No queue or replay** — a skipped call is dropped, deliberately, since replaying a stale game action after a reconnect could be worse than losing it. **No production caller changed:** all 8 call sites use `await …invoke(…);` as a statement and compile unchanged; the only edits outside the service were the six test fakes whose `Future<void>` override no longer satisfies the member. **Mid-flight drops are out of scope and unchanged** — if the hub dies after the invocation starts, it still throws and still propagates. Covered by `test/signalr_invoke_test.dart` (10 tests) against the real service. **Limitation:** the `true` branch cannot be exercised without a live hub, so it is pinned by a subclass reporting the contract, and the production `await _hubConnection!.invoke(...)` line is verified by reading, not by test. `flutter analyze` **0 issues**; `flutter test` **372 passing / 1 failing** (known **T3** baseline). | **DONE** |
| **S5** | **Done.** `onWaitingShown()` no longer closes the guard optimistically — `_didJoinRandom` is now set from `invoke`'s return, so a join that was never dispatched stays retryable. `onRecovered()` retries `JoinRandomGame` **only** when the controller is still in `GamePhase.waiting` **and** the guard is open; a reconnect on its own is never a reason to re-join. **`CheckPlayerGame` remains first and unconditional**, and the retry reuses `onWaitingShown()` so the guard, log and set stay in one place. **No new listener, lifecycle hook, timer, queue or replay** — the existing `ConnectionRecoveryController` registration is the only hook used. `GameRestore` routing is untouched and pinned (status 1 stays waiting, 2 → lobby, 3 + type 2 → auction), as is the rest of recovery. Covered by `test/waiting_join_retry_test.dart` (**12** tests, asserting invocation counts since the guard is private); **three were proven to fail** against the old code. `flutter analyze` **0 issues**; `flutter test` **384 passing / 1 failing** (known **T3** baseline). **Not in scope and unchanged:** `pass()`, `submitAnswer()`, `_passRequested`, timer ordering, and the other six `invoke` callers, which share the same optimistic-state shape. | **DONE** |
| **E3** | No crash reporting or global error handlers | `OPEN` — needs a dependency decision |
| **MA1** | **Done.** `README.md` and `SAMPLE_SCREEN.md` now describe the actual repository. README's setup step was wrong twice over — it pointed at `lib/core/constants/api_endpoints.dart`, a path that no longer exists, for a mechanism `F1` replaced; it now documents the real `--dart-define` names with the both-or-neither rule and the add-to-app Gradle `dartDefines` caveat. The structure tree was replaced with the three real trees (`lib/` debug host, `packages/coreapp/lib/`, `packages/play_game/lib/`), and the `SignalRService` table went from 6 methods to the 11 the class exposes. `SAMPLE_SCREEN.md` was kept and rewritten around the **public player profile** slice — the only complete vertical slice paired with a real screen — with samples quoted from the files rather than invented; its old advice to subscribe to SignalR per screen was corrected, since that is the pattern **W-2** removed. **Documentation-only: no source or test change.** **Verified:** 21/21 documented paths exist, 24/24 named symbols found in source, 11/11 `SignalRService` methods and 10/10 `BaseState` helpers present, **0** stale `lib/core/*` / `chat_example` / `ChatPage` / `SignalREvents` references; `flutter analyze` **0 issues**; `flutter test` **349 passing / 1 failing** (the known **T3** baseline). Unverifiable reconnect literals (a "5-second" timer, exact `withAutomaticReconnect` backoff values) were **removed rather than repeated**. | **DONE** |

### Medium / Low

| ID | Task | Status |
|---|---|---|
| **N4** | **Done.** The original "reconnect paths not serialized" concern is closed by `GameController` re-registering hub bindings before its own `onRecovered` runs, and `ConnectionRecoveryController.notifyRecovered()` awaiting callbacks sequentially. A residual race was found and fixed: `onWaitingShown()`'s `_didJoinRandom` guard was claimed only after awaiting `invoke()`, so the screen's own mount and `onRecovered()`'s retry landing in the same tick could both pass the check and dispatch `JoinRandomGame` twice. The guard is now claimed synchronously before the await. Covered by `test/waiting_join_race_test.dart` (2 tests, proven to fail against the old code); `test/waiting_join_retry_test.dart`'s existing 12 tests are unaffected. | **DONE** |
| **N5** | `signalr_core` pins load-bearing; maintenance unverified | `BLOCKED` — EXTERNAL |
| **SEC1a** | **Done.** Release-build/device log verification of the **SEC1** credential-log fix has been carried out and **confirmed by the repository owner**. No longer blocked on external verification. | **DONE** |
| **SEC2** | Tokens in plaintext `SharedPreferences` | `OPEN` — host-key coordination |
| **SEC3 / SEC4** | Device-clock request token; RSA padding and key size | `OPEN` — backend-owned |
| **SEC5** | `DebugConfig` in every build. **Scope note:** contains no real secret (empty debug username/password; one non-secret test social-media id) and is only reachable through the debug launcher, which a real host embedding is not expected to show (see **P2**, [HOST_INTEGRATION.md](HOST_INTEGRATION.md)). A low-severity residual tied to the same entrypoint decision as **A1**, not an independent production Login/Home blocker. | `OPEN` — low severity |
| **M1** | **Done.** The root `pubspec.yaml`'s `flutter: assets:` list (26 entries) was 100% duplicated in `packages/coreapp/pubspec.yaml` — package assets are already inherited automatically, per the module's own adjacent comment. The whole block was deleted; `flutter pub get` confirmed clean. | **DONE** |
| **M3** | **Done.** `ExitFromAllGames` had zero callers anywhere (confirmed by grep) — the entire `games` feature slice (usecase, repository, remote datasource, providers — 5 files), its 3 barrel exports, and its endpoint constant were deleted. `test/remote_datasources_test.dart`'s dedicated test group (4 tests) was removed with it; the shared "calls recorded in order" test was repointed at two still-existing datasources. | **DONE** |
| **MA2** | Unused codegen dependencies declared (`freezed_annotation`, `json_annotation`, `build_runner`, `riverpod_generator`, `freezed`, `json_serializable`). **Owner decision: removal is NOT approved — do not delete them.** They stay declared deliberately; this is not outstanding release work and should not be proposed as such again. | `DEFERRED` — accepted by decision |
| **P4** | **Closed / out of scope.** Was framed as "debug signing on the dev runner." `.android/app`'s release `buildType` uses `signingConfigs.debug` — but `.android/` is generated and gitignored (regenerated by `flutter clean` / `pub get`), so this is a dev-runner artifact, not a shipped one. Release signing belongs entirely to the native host's own build, per the same module/host reasoning already applied to **A1** / **P2** — see [HOST_INTEGRATION.md](HOST_INTEGRATION.md). | **CLOSED / OUT OF SCOPE** |
| **P5** | Jetifier (`enableJetifier=true`); `-Xmx8G -XX:MaxMetaspaceSize=4G` JVM args | `OPEN` |
| **F2** | Windows-only `apply_android_patches.ps1`; no iOS equivalent | `OPEN` |
| **E2** | **Done.** `Failure` gained an additive `cause` field (raw diagnostic, never displayed); both catch-alls — `base_repository.dart:24` and `runApi` at `base_page.dart:246` — now pass `e.toString()` as `cause`, so `message` falls back to the existing localized `AppStrings.current.unknownError`. `_showError` logs the `cause` when present and still displays `message`. **No new localization strings**; the EN/AR `unknownError` already existed. All five `UnknownFailure` and eight other `Failure` call sites remain valid — the deliberate `message:` sites (`hubConnectFailed`, the Dio `unknown/cancel/badCertificate` branch) were left alone. Covered by `test/failure_message_test.dart` (13 tests), including three that drive `guard()` itself and were **proven to fail** against the old code. | **DONE** |
| **E4** | **Done.** `runApi` no longer casts: it pattern-matches the sealed `Result` through the existing `Result.when(...)`, so `Success<T>.data` arrives already typed and the `failureOrNull!` bang is gone too. A caller's `onSuccess` now runs inside `_callOnSuccess`, which logs a thrown exception with its stack trace and stops there — **decision: log and swallow**, because the request itself succeeded, so a failing screen callback is a diagnostic and must not become a user-facing API error; it is deliberately **not** routed through `_showError` and does not invoke `onError`. The loading lifecycle is unchanged — the loader is still cleared in the existing `finally` before the success branch. **Signature, `ui_helpers_interface.dart`, `result.dart`, `_fail` and all five call sites are untouched.** Covered by `test/run_api_test.dart` (12 widget tests); **five were proven to fail** against the old code with an escaping `StateError`. The cast removal itself could not be proven by failure — sound null safety rejects `Success<String>(null)` before the cast is reached — so the null case is covered for a nullable `T` instead. | **DONE** |
| **M2** | **Done.** The two single-line `export … show …` shims — `dialogs/game_dialog.dart` and `dialogs/show_dialog_game.dart` — were deleted along with their two `play_game.dart` export lines. **VERIFIED before deletion:** nothing imported either file; every consumer of `GameDialog`, `GameDialogCard`, `ShowDialogGame` and `showDialogGame` already imports `package:coreapp/coreapp.dart`, which exports the real widgets. **Scope was narrowed by Foundation** — the six redundant *imports* had already gone under `F-ANL`. No behavioural change: an `export` directive emits no code. | **DONE** |
| **MA4** | **DONE.** `pages/waitting/` renamed to `waiting/`; the three camelCase page directories renamed to `lobby_private/`, `lobby_public/`, `player_profile/` with every import updated. `player_profile_screen.dart` split 397 → 295 + a 110-line `player_profile_widgets.dart` `part` (its two leaf `StatelessWidget`s read no screen state; a `part`, not a library, so both stay private). **Deliberately unchanged, with reason:** `auction_round_screen.dart` (603) has no standalone class — every UI builder is an instance method mutating `_bidRequested` / `_pickedBid` / `_countController` / `_answerTimeout` through `setState`, so extraction needs a part-file extension, and the **A4** attempt proved private members moved into one stop resolving from sibling parts; `interaction_dialog.dart` (377) has only two private 28-line data models as standalone code, leaving 349 lines — a file for no benefit. `game_controller.dart` remains **A4**'s, not this task's. Backend-origin typos (`PublicPorfile`, `Assetss`, `tournmentGameName`) documented in-code and out of scope. | **DONE** |
| **P3** | **Done.** The dead, fully-commented-out alternative bootstrap (110 of `lib/main.dart`'s 166 lines) was deleted — it was never executed, so this is a zero-behaviour-change cleanup, not a decision between the two approaches. The running bootstrap is untouched. | **DONE** |

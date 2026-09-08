# Changelog

Record of work actually performed. Task detail: [TASKS.md](TASKS.md).

> Nothing is recorded as complete unless it was implemented **and** verified.
> Work that was investigated but deliberately not changed is recorded as such.
> Labels: **VERIFIED** · **INFERRED** · **EXTERNAL VERIFICATION REQUIRED**.

---

## Fresh Assessment

**Date:** 2026-09-02
**Branch:** `main-signalr` · **HEAD:** `ee45859` ("wdyk game plugin")

A complete re-inspection of the repository, treating every prior finding as
unverified until re-confirmed against the current code. No prior documentation
was carried forward as fact.

**Baseline recorded at entry — VERIFIED**

| Metric | Value |
|---|---|
| `flutter analyze` | 83 issues |
| `flutter test` | 12 passing / 1 failing |
| root `lib` | 3 files / 454 lines |
| `packages/coreapp/lib` | 77 files / 6,553 lines |
| `packages/play_game/lib` | 94 files / 8,988 lines |
| `test/` | 4 files / 220 lines |

**Analyzer breakdown — VERIFIED:** 37 `invalid_use_of_visible_for_testing_member`,
37 `invalid_use_of_protected_member`, 6 `unnecessary_import`, 1 `unused_import`,
1 `prefer_const_constructors`, 1 `dead_null_aware_expression`.

**Findings**

- **A4 — VERIFIED.** 74 of the 83 issues came from `part`/`extension` handlers
  accessing the `@protected` / `@visibleForTesting` `state`. 33 sites in exactly
  two files; `waiting_screen_handler.dart` produced none because it touches no
  `state`.
- **S9 — VERIFIED.** Identity resolution reduces to a two-player closed-world
  assumption; with no opponent seated, every id resolves to the local user.
- **A5 — VERIFIED.** UI callbacks (`showDialog`, `AudioService`) passed into
  notifier extensions.
- **E5 — VERIFIED.** `dead_null_aware_expression` at `game_controller.dart:136`.
- **Confirmed still open:** SEC1, F1, P1, E1, S5, N2, N3, N4, N5, SEC2–SEC5,
  M1, M3, A1, A3, MA1, MA2, T2, T3, T4.
- **Confirmed resolved by earlier merged work — VERIFIED:**
  `GameController.onRecovered()` now invokes `CheckPlayerGame`, so the
  `ConnectionRecoveryController` mechanism is live.

---

## Foundation Cleanup & Stabilization

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Objective:** make the shared codebase clean and stable before continuing round
development, without changing behaviour.

**Behaviour-neutrality is not a single claim — VERIFIED in part, INFERRED in
part.** See *Behavioural impact* below before citing this section as proof that
nothing changed.

### Result

| Metric | Before | After |
|---|---|---|
| `flutter analyze` | **83 issues** | **1 issue** |
| `flutter test` | **12 passing / 1 failing** | **124 passing / 1 failing** |
| Test files | 4 | 10 |
| Test lines | 220 | 1,504 |

### A4 — Option C implemented

Added inside the `GameController` class body:

```dart
// Part-file extensions cannot use the @protected/@visibleForTesting state.
GameSessionState get _s => state;

set _s(GameSessionState value) => state = value;
```

`state` was then replaced with `_s` at 33 sites — 15 in
`lobby_screen_handler.dart`, 18 in `round_screen_handler.dart`. A comment on
`lobby_screen_handler.dart:19` containing the word "state" was deliberately
excluded.

- The accessor is **private**, so **no public API was introduced**.
- The `part` / `extension` structure was **preserved**.
- `waiting_screen_handler.dart` was **not modified** — it was already clean.
- Options A (suppression), B (merge back) and D (real classes) were presented;
  **C was chosen** because it removes the diagnostic by using a legal access
  path rather than silencing it.

**VERIFIED no logic changed by the rename.** Normalising `_s` back to `state`
across both diffs yields evenly-paired added/removed lines. The only
text-differing lines are the four belonging to the approved `const` fix.

### Behavioural impact — split verdict

| Change | Verdict |
|---|---|
| `state` → `_s` at 33 sites | **VERIFIED behaviour-neutral.** `_s` is a straight pass-through to `state`; the even-pairing proof above shows no other text changed. |
| 7 unused-import removals | **VERIFIED behaviour-neutral.** The analyzer confirms the symbols still resolve through the `coreapp` barrel. |
| `const RoundLottieDialog(...)` / `const AppLottieView.strike(...)` | **INFERRED behaviour-neutral — not verified.** `RoundLottieDialog` is a `ConsumerStatefulWidget`, so `const` canonicalizes the instance: every call site now receives the same object rather than a fresh one. Each `showDialog` still builds its own Element and State, so the practical impact is judged nil — but this is a semantic change, not a purely textual one, and it was not exercised at runtime. |

**Do not cite this phase as completely behaviour-neutral as though it were a
verified fact.** The rename and import removals are verified; the `const` change
is inferred.

### Analyzer cleanup

Seven mechanical fixes:

- 6 redundant `game_dialog.dart` imports removed from `count_answer_dialog`,
  `end_game_dialog`, `loss_dialog`, `round_lottie_dialog`, `setting_game_dialog`
  and `win_dialog`.
- 1 unused `game_player.dart` import removed from `game_session_reducer.dart`.
- 1 `prefer_const_constructors` applied in `round_screen_handler.dart`.

**83 → 1.** No suppressions added, no analyzer rules weakened, no tests deleted
or skipped.

### Test foundation

**112 new tests across 6 new files.** No source file was modified to make a test
pass.

**Tier 1 — pure functions:** `player_identity_test.dart`,
`game_domain_enums_test.dart`, `game_session_reducer_test.dart`,
`game_models_test.dart`.

**Tier 2 — `GameController` via `ProviderContainer` + fakes:**
`game_controller_routing_test.dart`, `game_controller_seating_test.dart`.

**Six characterization tests** record unresolved behaviour without endorsing it,
each named `CHARACTERIZATION (unresolved)` with a comment stating it is not an
endorsement.

Three analyzer findings introduced by these new test files (an unused helper, a
missing `const`, an untyped list literal) were **found and fixed within the same
task**, since they were self-inflicted.

### Files changed

**Source — 10 files, +40 / −42**

| File | Change |
|---|---|
| `game_controller/game_controller.dart` | +5 lines — the private accessor only |
| `game_controller/lobby_screen_handler.dart` | 15 × `state` → `_s` |
| `game_controller/round_screen_handler.dart` | 18 × `state` → `_s`, plus 1 `const` |
| `game_controller/game_session_reducer.dart` | −1 unused import |
| `dialogs/` × 6 | −1 redundant import each |

**Tests — 6 new files**

### Scope held — VERIFIED

| Area | Files changed |
|---|---|
| `packages/coreapp` | **0** |
| `pages/rounds/` including `wdyk_round_screen.dart` | **0** |
| `waiting_screen_handler.dart` | **0** |
| All pubspecs | **0** |
| Dependencies added | **0** |

---

## Investigated, deliberately NOT changed

### E5 — dead_null_aware_expression — **NOT MODIFIED**

`game_controller.dart:141` (was `:136`; the accessor added 5 lines above it).

**VERIFIED:** `game` is null-checked into a local two lines above, and
`CreatedGame.currentTimerValue` is a non-nullable `double`. `GameJson.decimal`
ends in `?? 0`, so the value is never null. The `?? 0` is unreachable.

**INFERRED:** every other read site goes through a nullable game
(`game?.currentTimerValue ?? 0`), where the `??` is live. This one place had
already unwrapped `game`, so it reads as copy-paste.

The guard's intent is establishable and removal would be behaviour-preserving —
but it was **not changed**, per instruction. This is the single remaining
analyzer issue.

### E6 — game-over result fallback unreachable — **DISCOVERED, NOT FIXED**

**VERIFIED.** `_gameOverFromData` returns a non-null object for every event in
`gameOverEvents` — `winnerId` simply defaults to `''` — and
`_resultFromGameOver` never returns null. Therefore `_resultFromData`, the
`isWin` / `result` string fallback, is **unreachable for every game-over event**.
An explicit `isWin: true` is ignored and the player is told they lost.

Found while writing a test that asserted intended behaviour and failed. Per the
rules, the test was **not** changed to match the implementation, and the
implementation was **not** changed either — it is outside the approved scope.
Recorded as a characterization test and as task **E6**.

### MA6 — hardcoded UI string — **DISCOVERED, NOT FIXED**

**VERIFIED.** `text: "Strike"` at `round_screen_handler.dart:137` bypasses
`PlayGameStrings`. Noticed while applying the approved `const` fix on the
adjacent line. Reported separately, not fixed.

### Identity — **UNCHANGED, BLOCKED**

`_findPlayers`, `isCurrentUser`, `isLocalPlayerLeft` and `_emoteIsMine` were
**not modified**. Behaviour is pinned by characterization tests only.

**Blocked on five questions — EXTERNAL VERIFICATION REQUIRED:**

1. Does the hub always send `userId` on players, or sometimes only a GUID `id`?
2. Is `PlayerLeft.playerId` a game-player id or an account id?
3. Is `PlayerEmoted.userId` the account id?
4. Is `CreatedGame.currentTurn` a game-player id or an account id?
5. Is prefs `user_id` in the same namespace as either hub id?

---

## S9 / S9a / S9b / S9c / S9-TEST — Identity resolved by positive matching

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Backend semantics — VERIFIED (owner-supplied).** The persisted login `user_id`
and hub player ids share **one namespace**; hub player values can name **either**
player and are not inherently the local user; `PlayerLeft` arrives as
`[playerId, gameId]` carrying the player id directly. Observed session: 47 local,
211403 opponent.

**Problem — VERIFIED.** Three predicates decided identity by inversion —
*"if not the seated opponent, it is me"* — which the confirmed semantics
contradict. `_findPlayers` guessed by list position when no id matched. And
`playerIdFrom` read only named keys, so positional `PlayerLeft` payloads resolved
to no player at all.

**Implementation — 2 source files, minimal.**

| Change | Task |
|---|---|
| `playerIdFrom` gains an `arg0` fallback after the named keys, mirroring `turnPlayerIdFrom` | **S9c** |
| `isCurrentUser` matches positively: `playerIdsEqual(_getMyUserId(), id)`, then the seated `me` | **S9** |
| `isLocalPlayerLeft` delegates to `isCurrentUser` | **S9a** |
| `_emoteIsMine` delegates to `isCurrentUser` | **S9** |
| `_findPlayers` prefers the persisted id over a stored seat, and **returns existing seats rather than guessing by position** when no id matches | **S9b** |

**Confirmed removed — VERIFIED by grep:** no *"not opponent = me"* logic and no
`players[0]` / `players[1]` positional seating remain anywhere in
`packages/play_game`.

**Deliberately unchanged.** `GameOverResult.isWinner` still compares with exact
`==` (**E1a**) — that is a separate question about `winnerId` formatting, still
unverified. `turnPlayerIdFrom` keeps its own now-redundant `arg0` fallback; it
returns the same value either way and touching it was out of scope.

**Tests — reworked, not edited.** Four characterization tests asserted the buggy
behaviour and **failed as soon as the fix landed**, which was the intended
signal. They were **replaced** with intent-based assertions rather than adjusted.

`game_controller_seating_test.dart` (18 tests) now covers, using the observed
ids: local 47 → local; 211403 → opponent; an id belonging to neither → neither;
resolution with no opponent seated; positional `PlayerLeft [47, gameId]` → local
left; positional `[211403, gameId]` → opponent left; map-shaped payloads
resolving identically; seating with the local player listed first **and** second;
opaque ids matched via `userId`; and a roster of strangers neither seating anyone
nor displacing existing seats.

Positional payloads are built with the **real** `HubEventPayload.mapFromArgs`,
not a hand-written map, so the test exercises the actual delivery path.
`game_session_reducer_test.dart` adds four `playerIdFrom` cases covering
positional resolution, positional/map equivalence, named-key precedence, and
empty `arg0`.

**Verification**

- `flutter analyze` → **No issues found**.
- `flutter test` → **144 passing / 1 failing** (was 136/1; +8). The failure is
  the pre-existing `widget_test.dart` overflow (**T3**).
- Characterization tests remaining: **1** (the `winnerId` whitespace case,
  **E1a**) — down from six.

**Baseline documents updated** to 144 passing, and the identity entries in
`TESTING_STRATEGY.md` and `AI_AGENT_WORKFLOW.md` moved from "unresolved,
off-limits" to "resolved, safe to rely on".

---

## MA6 — Hardcoded UI strings localized

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Problem — VERIFIED, and larger than recorded.** MA6 listed one literal at
`round_screen_handler.dart:137`. Inspection found **five** — the original survey
used a double-quote pattern and missed the single-quoted ones:

| Line | Literal |
|---|---|
| 116 | `text: isMe ? 'Strike':'Timeout',` |
| 137 | `text: "Strike",` |
| 163 | `text: 'Start Timer',` |
| 187 | `text: 'Skip',` |
| 210 | `text: 'Correct Answer',` |

Line 116 could not be localized in isolation — `'Strike'` and `'Timeout'` share
one ternary expression.

**Blocker, and how it was resolved.** No Arabic copy existed for any of these
concepts anywhere in the repository — the closest was `pass => 'باس'`. Because
`ArPlayGameStrings` implements every abstract member, a partial implementation
would not compile, and inventing Arabic game terminology would have been
guessing at product content. Work was **stopped** and the five translations were
supplied by the repository owner.

**Implementation — 4 files, no new mechanism.**

| File | Change |
|---|---|
| `play_game_strings.dart` | 5 abstract getters after `numberOfAttempts` |
| `en_play_game_strings.dart` | `Strike` · `Timeout` · `Start Timer` · `Skip` · `Correct Answer` |
| `ar_play_game_strings.dart` | `سترايك` · `إنتهى الوقت` · `بدأ الوقت` · `تخطي` · `اجابة صحيحة` |
| `round_screen_handler.dart` | 5 call sites → `strings.*`; `strings` resolved in 4 methods |

Strings are resolved with the pattern already used in this file:
`PlayGameStrings.forLanguage(ref.read(appLanguageProvider))`. No new
localization mechanism and no dependency were introduced.

**Consequence — VERIFIED, and it partially reverts F-ANL.** Three
`RoundLottieDialog` call sites lost their outer `const`, because `text` is now a
runtime value; the nested `AppLottieView` constructors regained `const` in
exchange. One of those sites is the `const` added under **F-ANL**. This is
unavoidable — a widget taking a localized string cannot be `const` — and the
analyzer confirms no `prefer_const_constructors` finding was reintroduced.

**Verification**

- `flutter analyze` → **No issues found** (baseline remains clean).
- `flutter test` → **136 passing / 1 failing** — unchanged; the failure is the
  pre-existing `widget_test.dart` overflow (**T3**).
- **Zero** `text: '…'` literals remain in `round_screen_handler.dart`.
- Abstract / EN / AR parity confirmed for all five members (1/1/1 each).
- No unrelated UI or behaviour changed: the `isMe` ternary still gates `text`,
  `marginTop` and `lottie` exactly as before.

---

## E5 — Dead null-aware fallback removed; analyzer baseline now clean

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Problem — VERIFIED (re-confirmed before the change, not taken on trust).**
In `_stopRoundTimer`:

```dart
if (game.isTimerStarted != true && (game.currentTimerValue ?? 0) <= 0) {
```

Three independent checks:

1. `game` is null-checked into a local two lines above, so it is promoted to
   non-null at the guard.
2. `CreatedGame.currentTimerValue` is declared `final double` — non-nullable.
   The `double?` in the class is only the `copyWith` "not provided" marker.
3. `GameJson.decimal` ends in `?? 0`, so the value is never null from JSON.

The `?? 0` was therefore unreachable.

**Implementation — one expression.**

```diff
-    if (game.isTimerStarted != true && (game.currentTimerValue ?? 0) <= 0) {
+    if (game.isTimerStarted != true && game.currentTimerValue <= 0) {
```

The parentheses existed solely to scope the `??` and went with it. For a
non-null `double`, `(x ?? 0) <= 0` is identical to `x <= 0` — behaviour
preserved. Surrounding timer logic untouched.

**Deliberately left alone — VERIFIED.** The same expression at
`lobby_play_game_screen.dart:96` reads `game?.currentTimerValue ?? 0` through a
**nullable** game, where the `??` is live and correct. Only the one unreachable
site was changed.

**Verification**

- `flutter analyze` → **No issues found.** Down from 1.
- `flutter test` → **136 passing / 1 failing** — unchanged. The failure is the
  pre-existing `widget_test.dart` overflow (**T3**).

**Baseline documents updated.** Because the analyzer baseline other agents
compare against changed from 1 to 0, the *current-state* baseline statements in
`TESTING_STRATEGY.md`, `PROJECT_ASSESSMENT.md`, `ENGINEERING_RULES.md`,
`AI_AGENT_WORKFLOW.md`, `ROADMAP.md` and `TASKS.md` were corrected. **Historical
records in this changelog were not altered** — they state what was true at the
time.

The same pass also corrected a **pre-existing drift**: those documents still
cited `124 passing`, a figure left stale by the SEC1, F1 and E6 tasks which
added tests without updating the baseline docs. Current is **136 passing / 1
failing**. Flagged rather than silently absorbed.

---

## E6 / E1 — Game-over result fallback fixed (safe half only)

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Problem — VERIFIED.** Two defects made a player who had not lost be told they
had:

1. **E6.** `_gameOverFromData` returns a non-null object for every event in
   `gameOverEvents` (`winnerId` merely defaults to `''`), and
   `_resultFromGameOver` never returned `null`. `_resultFromData` — the
   `isWin` / `result` fallback — was therefore **unreachable for every game-over
   event**, so an explicit `isWin: true` was ignored.
2. **E1 (terminal fallback).** When nothing determined the outcome, the chain
   ended in `?? GameResult.loss`.

**Implementation — 2 source files, 3 edits.**

| File | Change |
|---|---|
| `game_over_result.dart` | Added `bool get hasKnownWinner => winnerId.trim().isNotEmpty;` |
| `game_controller.dart` | `_resultFromGameOver` returns `null` when `!hasKnownWinner` |
| `game_controller.dart` | Terminal fallback `GameResult.loss` → `GameResult.ended` |

**Identity semantics deliberately untouched — VERIFIED.** A diff scan confirms
**zero** changed lines mentioning `_myGameIds`, `_findPlayers`, `isCurrentUser`,
`isLocalPlayerLeft`, `_emoteIsMine` or `playerIdsEqual`. `_myGameIds()` was
**not** restored (0 occurrences repo-wide), and `isWinner`'s body is unchanged —
still exact `==` against a single `getUserId()` lookup. The identity half is
tracked separately as **E1a** (`BLOCKED`, EXTERNAL VERIFICATION REQUIRED).

**What this does and does not fix.** An undeterminable outcome is now neutral
rather than a defeat, and payload result fields are honoured. A winner whose
`winnerId` differs from the stored id by whitespace or namespace is **still**
reported as a loss — that is E1a, and it stays pinned by a labelled
characterization test.

**Tests updated to verify corrected behaviour.** Two characterization tests in
`game_controller_routing_test.dart` recorded the buggy behaviour; both were
**replaced** with intent-based assertions rather than merely edited, per the
testing rules. Six tests added overall:

- `isWin: true` honoured when no winner is named (E6 regression)
- `isWin: false` yields a loss
- textual `result: 'won'` honoured
- indeterminate game-over yields `ended`, not `loss` (E1 regression)
- a named `winnerId` still takes precedence over payload result fields
- `hasKnownWinner` group in `player_identity_test.dart`, including a test that
  separates "nobody won" from "you did not win"

The whitespace characterization test in `player_identity_test.dart` was **kept**
— `isWinner` is unchanged, so it still records real, unresolved behaviour.

**Verification**

- `flutter analyze` → **1 issue** (pre-existing `dead_null_aware_expression`,
  **E5**). No new findings.
- `flutter test` → **136 passing / 1 failing** (was 130/1; +6). The failure is
  the pre-existing `widget_test.dart` overflow (**T3**).
- No source file was changed to make a test pass; no test assertion was weakened.

---

## P1 — Startup auth wipe removed

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Problem — VERIFIED.** `main()` ran `await prefs.clearAuth();` unconditionally,
deleting `auth_token`, `refresh_token`, `user_id` and `social_media_id` on every
cold start. The module therefore started logged out every time.

**Implementation — `lib/main.dart` only, two lines net.**

- Removed `await prefs.clearAuth();`.
- Corrected the adjacent log, which read `'main() — hub idle until Start Hub;
  auth empty until Register'`. The second clause becomes **false** once sessions
  persist, so it was dropped rather than left asserting something untrue.

**No replacement auth mechanism was added, and none is needed — VERIFIED.**
`AuthNotifier.build()` already bootstraps from `SharedPrefsService`: it reads the
stored token and returns an `AuthSession` when one exists, `null` otherwise. A
persisted session therefore flows into state on its own. **VERIFIED:** zero
live (non-comment) references to `login` / `authNotifier` / `AuthSession` exist
in `main.dart` — the only matches are inside the pre-existing commented-out
bootstrap block (**P3**).

**The reset path is intact and stronger than the wipe — VERIFIED.**
`clearAuth()`'s only remaining production caller is `AuthNotifier.logout()`,
reached from the launcher's "Clear data" button, which additionally calls
`signalRService.disconnect()` and `prefs.clear()` — clearing everything, not just
auth keys.

**Reassessed, not restored.** The discarded branch's version of this change also
added a `hasStoredSession` presence log. That was **not** reimplemented: the
diagnostic it provided already exists at the point it matters —
`SignalRService.connect()` logs `'connect() aborted — token is empty (native
guard)'` when no token is present. Dropping the false clause was the smaller
truthful fix.

**Verification**

- `flutter analyze` → **1 issue** (pre-existing `dead_null_aware_expression`,
  **E5**). No new findings.
- `flutter test` → **130 passing / 1 failing** — unchanged. The failure is the
  pre-existing `widget_test.dart` overflow (**T3**). No test exercises `main()`;
  `widget_test.dart` mounts `HomeLauncherPage` with its own `ProviderScope`.
- **Startup order preserved — VERIFIED:** `ensureInitialized` →
  `SharedPrefsService.init` → `setLanguage` → `ProviderContainer` →
  `AppLifecycleObserver` → `addObserver` → log → `runApp`.
- **Out-of-scope areas untouched — VERIFIED:** 0 files changed under
  `app_base_interceptor.dart` or `features/auth/` (401/refresh), and this task
  changed only `lib/main.dart` — the `game_controller.dart` diff in the working
  tree is from the earlier Foundation phase (A4 Option C), not this change.

**KNOWN ISSUE — residual, tracked as P1a.** A stale or expired token now
persists across launches while **N2** (401 handling / token refresh) is still
absent, so an expired session causes hub backoff retries and REST error dialogs
until "Clear data" is tapped. **This change surfaces the pre-existing N2 gap
rather than causing it.** Accepted deliberately: a permanently logged-out module
blocks all realistic testing, and the manual reset works.

---

## F1 — Environment configuration via `--dart-define`

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Problem — VERIFIED.** `static const baseUrl = baseUrlDebug;` and
`static const signalRHubUrl = baseUrlHubDebug;` — a single hardcoded test
backend. Pointing at any other environment required editing and committing
source, so staging and production could not be built from the same commit.

**Implementation — one source file.**

`packages/coreapp/lib/constants/api_endpoints.dart`:

```dart
static const baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: baseUrlDebug,
);

static const signalRHubUrl = String.fromEnvironment(
  'SIGNALR_HUB_URL',
  defaultValue: baseUrlHubDebug,
);
```

Build with:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=SIGNALR_HUB_URL=https://api.example.com/GameHub
```

**Why `static const` was mandatory, not merely convenient — VERIFIED.**
`_mediaUrl` in `user_profile.dart` and the sticker equivalent in
`sticker_asset.dart` are **top-level functions in the domain layer** with no
`ref` in scope. A provider-injected value would have required changing their
signatures and every caller. Keeping `const` left **all call sites untouched** —
confirmed by diff: `di/providers.dart`, `base_page.dart`,
`auth_remote_datasource.dart`, `user_profile.dart` and `sticker_asset.dart` are
all unchanged.

**Deliberately not restored from the discarded branch.** That version also added
an `isUsingDefaultEnvironment` flag and a startup log in `lib/main.dart`. Neither
was requested here, and the log would have touched a file outside this task's
scope. The guard test computes the comparison directly instead. Mentioned as an
option, not implemented.

**Verification**

- **Default run** (no defines) → 6 tests pass.
- **Both defines set** → 6 tests pass.
- **Negative run — one define only** → the half-config guard **fails as
  designed**: `Half-configured build. Set BOTH API_BASE_URL and SIGNALR_HUB_URL,
  or neither.` This is what proves the define actually reaches the code; the two
  passing runs alone could not.
- `flutter analyze` → **1 issue** (pre-existing `dead_null_aware_expression`,
  **E5**). No new findings.
- `flutter test` → **130 passing / 1 failing** (was 124/1; +6 new). The failure
  is the pre-existing `widget_test.dart` overflow (**T3**).
- **Behaviour unchanged — VERIFIED:** no call site, networking, or
  authentication code was modified.

**KNOWN ISSUE — residual, tracked as F1b.** `defaultValue` still points at the
test backend, so an omitted define silently ships test configuration. And
**INFERRED:** add-to-app hosts building through Gradle do not use the
`flutter build` CLI and must pass the same values via `dartDefines` — not
exercised against a real host build.

---

## SEC1 — Release-log credential leak closed

**Date:** 2026-09-02 · **Applied to the working tree — NOT committed.**

**Problem — VERIFIED.** Two sites logged credential material on every request,
neither gated to debug builds:

1. `ApiClient` registered `PrettyDioLogger(requestHeader: true, requestBody:
   true, responseBody: true)` **unconditionally**, while `ChuckerDioInterceptor`
   directly below it *was* `kDebugMode`-gated. It wrote the `Authorization`
   header and full request/response bodies, including the login body.
2. `ApiHeadersBuilder` logged the `Request-Token` **value** on every request.

**Implementation — smallest safe scope.**

| File | Change |
|---|---|
| `packages/coreapp/lib/network/api_client.dart` | Added `bool enableLogging = kDebugMode` and moved the `PrettyDioLogger` registration inside `if (enableLogging)`. One `//` comment records why the gate exists. |
| `packages/coreapp/lib/network/api_headers_builder.dart` | Deleted the `Request-Token` log line and the `app_logger.dart` import it was the sole user of. |

The parameter mirrors the existing `enableChucker = kDebugMode` pattern rather
than introducing a new one. `ApiClient` has a single construction site
(`di/providers.dart`) which passes no override, so the default applies.

**Deliberately reassessed, not restored.** Earlier work on a discarded branch
also split `AppLogger` into `log`/`verbose` and added `redact()`. That was **not
reimplemented**: a sweep showed the remaining `AppLogger` payload sites carry hub
game payloads, not credentials, and the split's value rests on **Claim 1**
(`dart:developer` surviving release AOT), which is **EXTERNAL VERIFICATION
REQUIRED**. Tracked separately as **SEC1b**.

**Verification**

- `flutter analyze` → **1 issue** (the pre-existing `dead_null_aware_expression`,
  **E5**). No new findings; the removed import did not leave an unused-import
  warning.
- `flutter test` → **124 passing / 1 failing** — unchanged from baseline; the
  failure is the pre-existing `widget_test.dart` overflow (**T3**).
- **Credential sweep — VERIFIED:** grepping every `AppLogger`/`print` call for
  `token`/`auth`/`password`/`bearer`/`secret` now returns a single hit,
  `'connect() aborted — token is empty (native guard)'`, which carries no value.
  `SignalRHttpClient` continues to log booleans only.
- **Behaviour unchanged — VERIFIED:** `buildGlobalHeaders` returns the same map
  including `Request-Token`; `ApiClient` still registers the same 4 interceptors
  in the same order, with `AppBaseInterceptor` ungated as before. No
  authentication or networking behaviour was altered.

**KNOWN ISSUE — EXTERNAL VERIFICATION REQUIRED.** That the leak reached logcat in
a release build, and that it is now closed there, has **not** been confirmed on a
device. The fix rests on reading the source and on the analyzer/test baseline.
The release-build check remains **SEC1a**.

---

## T4 — CI pipeline added

`.github/` did not exist; `flutter analyze` and `flutter test` were run by hand
on every change. **T3 unblocked this** — with the suite at 385 pass / 0 fail, a
new pipeline is green on day one instead of red.

### Delivered

`.github/workflows/ci.yml`, on `[push, pull_request]`:

checkout → set up Flutter **3.35.7** (stable) → `flutter --version` →
`flutter pub get` → `flutter analyze` → `flutter test`.

Each step fails the job on a non-zero exit.

### Scope decisions — owner

| Decision | Outcome |
|---|---|
| Toolchain | Pinned to **3.35.7 / Dart 3.9.2**, the version this repository is developed against |
| Scope | `analyze` + `test` only |
| Add-to-app / module build | **Excluded** — remains an `F1b` / host concern |
| Coverage thresholds, matrix, cache, branch filters | **None** — kept minimal and deterministic |

### Established before writing it, not assumed

- **Melos bootstrap is not needed — VERIFIED.** This is a pub workspace: the
  root pubspec lists `packages/coreapp` and `packages/play_game`, and both
  declare `resolution: workspace`. One root `flutter pub get` resolves all
  three — confirmed by reading `.dart_tool/package_config.json`, which lists
  `game_engine`, `coreapp` and `play_game`. The `melos` scripts in the root
  pubspec only fan the same commands out per package.
- **The workflow genuinely fails — VERIFIED by measurement.** A deliberately
  introduced lint made `flutter analyze` exit **1**; a clean tree exits **0**.
  The probe file was removed immediately.
- **No version file exists for CI to read — VERIFIED.** There is no `.fvmrc`,
  `.tool-versions` or `.flutter-version`, and `.android/local.properties` only
  points at a local SDK path. The pin therefore lives in the workflow, with a
  comment recording that obligation.

### Verification

**YAML validated by parsing, not by eye.** A temporary test loaded `ci.yml`
with `package:yaml` and asserted the job name, `runs-on`, both actions, the
pinned version string, the three commands, and the absence of `flutter build`
or `--coverage`. Probe removed afterwards.

Run locally in CI order:

| Step | Result |
|---|---|
| `flutter pub get` | exit **0** |
| `flutter analyze` | **0 issues** |
| `flutter test` | **385 passing / 0 failing** |

### NOT verified — EXTERNAL VERIFICATION REQUIRED

**The workflow has never executed** and cannot be until it is pushed. Two
unknowns: whether the suite passes on `ubuntu-latest` (every local run was
Windows; the widget tests touch plugin-backed `AudioService` and
`SharedPreferences`, which the test binding leaves unanswered on any platform
— consistent, but unproven on Linux), and whether `subosito/flutter-action@v2`
resolves 3.35.7 on the runner. Neither justifies withholding the workflow —
the first run is the test — but the pipeline is **not** proven green.

### Files changed

| File | Change |
|---|---|
| `.github/workflows/ci.yml` | **new** — 39 lines |

No source, test, or other documentation was touched.

### Residual

The Flutter version now exists in **two** places — the workflow and each
developer's local SDK — with nothing enforcing they agree. A `.flutter-version`
or `.fvmrc` read by both would close it, but that changes local developer setup
and was outside T4.

---

## Final delivery pass — N4, N2 (partial), M1, M3, P3, status reconciliation

**Date:** 2026-09-05

A read-only audit of every remaining `OPEN`/`BLOCKED` backlog item against the
current code (not old docs) found several items already closed by earlier
round/navigation work this session, and five genuinely small, safe fixes
worth doing today. Nothing invented a backend contract, security posture, or
product decision this repository doesn't already provide.

**N4 — reconnect paths not serialized (residual race fixed).** The main
concern was already closed by `GameController` re-registering hub bindings
before `onRecovered` runs. One residual race remained:
`onWaitingShown()`'s `_didJoinRandom` guard was claimed only *after*
awaiting `invoke()`, so the screen's own mount and `onRecovered()`'s retry
landing in the same tick could both pass the check and dispatch
`JoinRandomGame` twice. Fixed by claiming the guard synchronously before the
await. `waiting_screen_handler.dart`. Tests: `test/waiting_join_race_test.dart`
(2 new, proven to fail pre-fix); `test/waiting_join_retry_test.dart`'s
existing 12 unaffected.

**N2 — 401 handling (partial).** `UnauthorizedFailure` was already
classified but never acted on — a rejected token kept being resent.
`runApi`'s `_fail` now clears the stored auth on `UnauthorizedFailure`.
`base_page.dart`. No redirect was added (no login screen exists yet — needs
**A1**); no token-refresh endpoint was assumed. Tests: `test/run_api_test.dart`,
new "N2" group (2 tests, proven to fail pre-fix).

**M1 — duplicated assets removed.** Root `pubspec.yaml`'s 26-entry
`assets:` list was 100% duplicated in `packages/coreapp/pubspec.yaml` —
package assets are already inherited automatically. Block deleted;
`flutter pub get` confirmed clean.

**M3 — dead `ExitFromAllGames` slice removed.** Zero callers anywhere
(confirmed by grep). Deleted the 5-file feature slice, its 3 barrel
exports, and its endpoint constant. `test/remote_datasources_test.dart`'s
dedicated 4-test group removed with it; the shared "calls recorded in
order" test repointed at two still-existing datasources.

**P3 — dead commented-out bootstrap removed.** 110 of `lib/main.dart`'s 166
lines were an alternative `main()` that never ran. Deleted — zero behaviour
change, since dead comments execute nothing either way. The running
bootstrap is untouched.

**Status corrections (no code change).** `docs/TASKS.md`: **R-AUC** and
**R-BELL** were still marked `BLOCKED`/`OPEN` but are fully implemented
(confirmed by reading the current round screens/handlers/tests) — corrected
to `DONE`. **R-CB**/**R-BRK** are implemented with one accepted gap
(**R-08**) — annotated rather than left as bare `OPEN`. **E1** is now fully
closed (its remaining half was E1a, already fixed) — corrected to `DONE`.

**Investigated and deliberately NOT changed today** (see the reasoning
inline where relevant — none of these invent a contract this repo doesn't
provide):
- **W-IMPL/W-TEST** — `ALLOW_ALL` timer behavior needs an owner/backend
  decision; nothing in the repo establishes it needs different treatment.
- **P2-task, SEC5** — both trace back to the same root cause: no
  product-defined home/login screen exists yet (needs **A1**). No safe
  partial fix exists without inventing one.
- **SEC1b** — adding an unused `verbose()` log level would not itself
  reduce any exposure; closing the item for real means migrating 80+
  call sites across the hub/round layer, too large a footprint for today,
  and its value depends on the still-unresolved **SEC1a** AOT question.
- **MA2** — genuinely unused codegen deps, but removing a dependency needs
  the same approval as adding one (Engineering Rules §6.3) — not touched
  without that approval.
- **A1, A5, S1, S2, S3, S7, S8, T2, MA3, MA4, P4/P5/F2** — architectural,
  needs-approval, or large-blast-radius items, unchanged.

**Verification.** `flutter analyze` — 0 issues. `flutter test` — 1024/1024
passing (net: +4 new N4/N2 tests, −4 deleted M3 tests). Full diff reviewed
file-by-file for scope creep; nothing outside the 5 items above was touched.

---

## A1 (partial) — the GameEngine guarantees its own hub connection on entry

**Date:** 2026-09-05

**Confirmed requirement.** The native host may or may not connect SignalR
before opening the GameEngine; on entry the GameEngine must guarantee a
connection, reusing a live one rather than creating a second.

**What the audit found — VERIFIED, and it was not only a doc gap.**
`connectHub()`'s only caller in the whole repository was the debug
launcher's "Start Hub" button (`home_launcher_page.dart:160`); nothing in
`packages/play_game` ever connected. And every self-healing path in
`SignalRService` — `invoke()` `:379`, `_connectIfSubscribeNeedsHub()` `:320`,
`reconnect()` `:217`, `onAppResumed()` `:418`, `_scheduleReconnect()` `:486`
— is gated on `_hubUrl != null`, which only `connect()` assigns `:107`. So a
host opening Waiting directly would have produced no connection, no join,
and no retry: `WaitingScreen.initState` → `onWaitingShown()` →
`invoke(JoinRandomGame)` would simply return `false` forever.

| File | Change |
|---|---|
| `play_game/.../game_controller_screen.dart` | On entry (post-frame, alongside the existing sticker load) `_ensureHubConnected()` connects when `hasLiveConnection` is false, and returns immediately when it is true |
| `coreapp/.../base_page.dart` | `connectHub()` gains `ErrorType error = ErrorType.dialog` — default unchanged, forwarded to `runApi` |
| `coreapp/.../ui_helpers_interface.dart` | Same parameter on the interface declaration |

**Why the guard, and why `ErrorType.none`.** `connectHub()` is written for
the launcher: it toasts when already connected, and while a connect is still
in flight its own `connectIfNeeded` no-ops so it would then report
`hubConnectFailed` even though nothing failed. `hasLiveConnection` covers
both connected *and* connecting, so reuse is silent and never duplicated.
Calling it bare also put a modal error dialog over the screen being entered
whenever connect did not immediately succeed — **that was not theoretical:
it broke 10 existing dialog/navigation tests**, which is why the entry path
passes `ErrorType.none`. The service's own failure handling is untouched:
`connect()` still sets `failed` and schedules its backoff retry, and a later
drop still raises the `ConnectionLoader`.

**Deliberately unchanged:** hub event binding (`playGameHubBindingsProvider`
already binds on construction and `SignalRService` re-attaches after
connecting), the debug launcher, gameplay/rounds/timers/dialogs/navigation,
Private Lobby, and both refresh flows (N2 REST, P1a SignalR).

**Tests.** `test/game_entry_connection_test.dart` (7): no connection →
exactly one connect; already connected → none; already connecting → none;
failed connect leaves the screen usable with no modal; failed connect is not
looped by the entry path; binding lifecycle undisturbed; re-entry after a
drop connects again. Removing the guarantee was **proven** to fail 4 of the
7.

**Verification:** `flutter analyze` **0 issues**; `flutter test` **1059
passing / 0 failing** (net +7).

**Still open for A1 — host-owned:** how the native host launches the module
directly at Waiting. The repository has no `MethodChannel`, no
`vm:entry-point` beyond `main()`, no named routes, and
`AppTheme.navigatorKey` is `null` in release (it is Chucker's debug key), so
no entry mechanism exists to build on yet.

---

## P1a — SignalR access-token refresh

**Date:** 2026-09-05

Extends **N2**'s refresh to the hub, using the *same* mechanism rather than a
second one.

**Where the hub's token actually lives — VERIFIED before changing anything.**
This module deliberately does **not** use signalr_core's `accessTokenFactory`:
negotiate would append `?access_token=` to the WebSocket URL, which this
server rejects (close 1002 — the load-bearing comment in
`signalr_service.dart`). The token reaches the hub through `SignalRHttpClient`
instead, and signalr_core's own `web_socket_channel_io.dart` drives the
upgrade with `client.send(request)` — so `send()` is the one place a hub 401
is observable, and where the refresh belongs.

| File | Change |
|---|---|
| `features/auth/data/services/auth_token_refresher.dart` | The in-flight guard moved **into** the refresher (`_pending`), so it coordinates every caller instead of one transport. Constructor is no longer `const` (it now holds state). |
| `di/providers.dart` | New `authTokenRefresherProvider` — **one shared instance** for both transports. `apiClientProvider` reads it lazily (only on a 401), which replaces the previous `late final client` self-reference. Both providers are explicitly typed because they reference each other and inference cannot resolve that alone. |
| `signalr/signalr_http_client.dart` | On a 401: refresh via the shared refresher, then replay the upgrade **once** with the new token. Non-401 passes straight through. The 401 body is drained only once a retry is certain. A sent `Request` is finalized, so the retry uses a copy that preserves signalr_core's upgrade headers. Optional `inner` client added as a test seam. |
| `signalr/signalr_service.dart` | Optional `obtainRefreshedAccessToken`, forwarded to `SignalRHttpClient`. Null keeps pre-P1a behaviour exactly. |
| `signalr/signalr_provider.dart` | Wires the shared refresher in, read lazily. |

**Concurrency.** One `AuthTokenRefresher` instance, one `_pending` future:
a REST 401 and a hub 401 landing together share a single refresh. The guard
releases on completion, so a later 401 can refresh again.

**Failure behaviour.** Missing/empty refresh token or a failed refresh →
the stored session is cleared through the existing mechanism and the
original 401 is returned untouched, for signalr_core to handle as before.
No fallback was invented. A retry that is itself rejected is **not**
refreshed again — one retry only, no loop. The refresh travels over REST,
never back through the hub, so it cannot recurse.

**Deliberately unchanged:** reconnect/backoff/status logic, the empty-token
guard in `connect()`, `invoke()`, subscriptions, and the `skipNegotiation` /
close-1002 transport decision. No backend contract or endpoint was added.
No token, refresh token, or Authorization value is logged.

**Tests.** `test/signalr_token_refresh_test.dart` (11): valid token used
as-is with no refresh; 401 refreshes and retries with the new token;
refreshed session persisted; concurrent hub 401s share one refresh; missing
refresh token; failed refresh; a rejected retry does not loop; non-401
passthrough; unchanged behaviour when no refresher is wired; upgrade headers
preserved on the retry; and a source-level guard that no credential value is
interpolated into a log call (AppLogger has no seam to capture — SEC1b).
Disabling the retry was **proven** to fail 7 of the 11. Two cross-transport
tests were added to `test/auth_token_refresher_test.dart`. Existing
`signalr_invoke_test.dart` passes unchanged.

**Verification:** `flutter analyze` **0 issues**; `flutter test` **1052
passing / 0 failing** (net +13).

**Remaining limitation.** The refresh triggers on a server 401. There is no
proactive expiry check — the repository has no established JWT-expiry
parsing and inventing one was out of scope. A token that expires while the
hub sits idle is therefore refreshed on the next upgrade attempt, not before
it.

---

## N2 — full access-token refresh and retry on a 401

**Date:** 2026-09-05

**Product requirement (owner-confirmed):** on an expired access token, the
module refreshes it itself, using the existing login/auth mechanism and
`GET api/Users/RefreshToken`. The native host is not involved. No new
storage contract, no invented payload.

**Implementation — reuses the login flow's own classes, mirrored, not
duplicated.**

| File | Change |
|---|---|
| `constants/api_endpoints.dart` | `refreshToken = '/api/Users/RefreshToken'` |
| `network/app_base_interceptor.dart` | Honors `extra[authTokenOverrideKey]` so one call can authenticate with a token other than `tokenProvider()`'s — needed only for the refresh call itself (which must send the refresh token, not the expired access token) |
| `network/refresh_token_interceptor.dart` (new) | `RefreshTokenInterceptor` — Dio `onError` interceptor: on a 401 (that isn't the refresh call itself, and hasn't already been retried), calls the injected `obtainRefreshedAccessToken`, then re-dispatches the original request via `dio.fetch(err.requestOptions)`. Concurrent 401s share one in-flight refresh (`_pendingRefresh`). A `_retriedKey` extra flag caps retries at one. |
| `network/api_client.dart` | New optional `obtainRefreshedAccessToken` param wires the interceptor in (absent everywhere else, incl. every existing test's `ApiClient` subclass — zero behavior change for them); `get()` gains `authTokenOverride` / `isAuthRefreshCall`, used only by the refresh call |
| `features/auth/domain/repositories/auth_repository.dart`, `data/repositories/auth_repository_impl.dart`, `data/datasources/auth_remote_datasource.dart` | `refresh(String refreshToken)` added to each, mirroring `login()` exactly — same `LoginResponseModel.fromEnvelope` parsing, same `ApiResponseHandler` error mapping, same `AuthSession` result |
| `features/auth/data/services/auth_token_refresher.dart` (new) | `AuthTokenRefresher` — the refresh *policy*: reads the stored refresh token, calls `AuthRepository.refresh()`, persists the new session via the existing `SharedPrefsService` setters, or clears the stored auth (`clearAuth()`) when there's no usable refresh token or the call fails |
| `di/providers.dart` | `apiClientProvider` wires `AuthTokenRefresher` in via a `late final` self-reference (`client`) — this is what avoids a circular dependency on `authRepositoryProvider`, itself built from `apiClientProvider` |

**No Login/Home screen or navigation was added** — a refresh failure clears
the cached session and lets the original 401 propagate, which is exactly
what already drives the existing `runApi`/`_fail` clear-on-401 behavior
(from the earlier N2 partial fix) and generic error dialog. That existing
code path is untouched and still serves as a safety net for any 401 that
isn't intercepted.

**Tests.** `test/refresh_token_interceptor_test.dart` (6, driven through a
real `Dio` + the real `AppBaseInterceptor`/`RefreshTokenInterceptor` pair,
using a fake `HttpClientAdapter` — no new dependency, `Dio` already exposes
one): retry succeeds, the retried request actually carries the new token,
a refresh failure doesn't retry or loop, a missing refresh token doesn't
loop, a non-401 failure never touches the refresh path, and concurrent
401s share exactly one refresh (verified by calling `onError` directly,
twice, back to back — deterministic, independent of Dio's own request
scheduling). Reverted-and-reran: disabling the retry made 5 of these 6
fail. `test/auth_token_refresher_test.dart` (5): missing/empty refresh
token clears auth without calling the repository, a successful refresh
persists the full session and returns the new token, a failed refresh
clears auth, an empty-token "success" is treated as failure. 4 new tests
in `test/remote_datasources_test.dart` mirror `login()`'s existing
coverage for `refresh()`.

**Scope note.** This closes the REST/`ApiClient` half of **P1a**'s residual
risk. The SignalR hub's own `accessTokenFactory` is unchanged — a hub
connection dropped for an expired token still isn't proactively refreshed;
that was never in this task's scope.

**Verification:** `flutter analyze` **0 issues**; `flutter test` **1039
passing / 0 failing** (net +15 new; one pre-existing test file's `ApiClient`
subclass needed its `get()` override signature synced, not weakened).

---

## E1a — `isWinner` now uses tolerant identity comparison

**Date:** 2026-09-05

**Problem — VERIFIED.** `GameOverResult.isWinner` compared `winnerId == userId`
exactly, the one identity comparison in the codebase still doing so — every
other comparison of a hub-sourced id already went through `playerIdsEqual`
(`GameSessionState.winnerPlayer` compares this same `winnerId` that way).

**Implementation.** `packages/play_game/lib/features/games/domain/entities/game_over_result.dart`:
`isWinner` now calls `playerIdsEqual(winnerId, userId)`.

**Tests.** `player_identity_test.dart`'s characterization test (whitespace in
`winnerId` failing to match) was replaced with an intent-based assertion that
it now matches; added a numeric-format-drift case (`'007'` vs `'7'`) and a
genuinely-different-id case. `game_controller_routing_test.dart` gained one
integration test exercising the same fix through `applySessionEvent`.

**Verification:** `flutter analyze` **0 issues**; `flutter test` **1024
passing / 0 failing**.

---

## Round & navigation fixes — audit follow-ups

**Date:** 2026-09-05

Four independently-scoped fixes, each investigated and confirmed before
changing anything:

| Fix | File | Change |
|---|---|---|
| Stale Auction/Comeback fields on `RoundFinished`/`ShowResults` | `game_controller.dart` | `showPhase`'s trailing metadata reapply cleared via `game?.copyWith(clearAuctionGameMetadata: true)`, mirroring `NextRoundStarted`'s existing reset |
| Dialog chain could orphan onto a screen already left | `coreapp/base_page.dart` | `showAppDialog` now skips when `ModalRoute.of(context)?.isActive == false`, not just `mounted` |
| Auction round win had no feedback (loss already did) | `auction_dialog_handler.dart`, `auction_round_screen.dart` | added `onAuctionRoundWon`, wired to `PlayerWonAuctionRound` |
| `GameUpdated` while Waiting always opened Lobby, ignoring `status` | `waiting_screen_handler.dart` | `onWaitingGameUpdated` now tries `_routeByStatus` first, same as its `onWaitingGameRestore` sibling |

**GameOver result flow.** `_showResultDialog` (`game_controller_screen.dart`)
no longer calls `_leaveAllGames()`/`_leaveGame()` after the result dialog
closes — GameOver/GameFinished/GameTerminated already mean the server
considers the match concluded, so Collect Rewards now returns to Home via a
new `_returnToHomeAfterResult()` that only pops this screen's own route,
dispatching no `LeaveGame` call. Explicit exit and `PlayerLeft` are
unchanged and still use `_leaveGame()`.

**Investigated, not changed:** Comeback/Breaker cannot distinguish an
already-resolved question from an active one on the very first `GameRestore`
a fresh screen sees — no repository-evidenced field exists to do so; recorded
as `CHARACTERIZATION (unresolved)` tests in `comeback_screen_test.dart` and
`breaker_screen_test.dart`, not fixed.

**New test files:** `finish_round_stale_state_test.dart`,
`round_dialog_disposal_test.dart`, `waiting_gameupdated_routing_test.dart`,
`gameover_result_leave_flow_test.dart`.

**Verification:** `flutter analyze` **0 issues**; `flutter test` **1024
passing / 0 failing**.

---

## W-ACTION — WDYK timer stops on the server's event, not on the tap

**Date:** 2026-09-03

`pass()` and `submitAnswer()` froze the round countdown **before** invoking the
hub. When `invoke()` returned `false` — hub disconnected, nothing dispatched —
the timer stayed frozen for an action that never happened, and the screen-local
guard was never released: `_passRequested` clears only when `me.passes` changes,
so the Pass button stayed dead for the life of the screen.

### Delivered

The stop moved from the tap to the authoritative event:

| Trigger | Before | After |
|---|---|---|
| Tap Answer | froze the timer | no timer effect |
| Tap Pass | froze the timer | no timer effect |
| `CorrectAnswer` | no timer effect | stops and freezes |
| `Penalty` | no timer effect | stops and freezes |
| `PlayerPassed` | stops and freezes | unchanged |
| `PlayerAnswered` | stopped the timer | **no longer a timer-stop event** |

`_stopRoundTimer()` lost every caller and was deleted. `RoundScoreColumn`'s
dedicated `lastEventName == playerAnswered` stop branch went with it.

`pass()` and `submitAnswer()` now return `Future<bool>`, propagating `invoke()`'s
result (available since **N3**). On `false` the WDYK screen releases the matching
guard — `_passRequested`, `_selectedAnswer` — behind a `mounted` check, so the
player can retry. A **successful** dispatch does not release the guard; server
events remain responsible for normal completion.

A stop remains a freeze: `currentTimerValue` is never written by one, and
`TimerUpdatedSeconds` remains the only start signal.

### Established before writing it, not assumed

- **The runtime event contract is owner-supplied.** A correct answer produces
  `CorrectAnswer`, a wrong one `Penalty`, a pass `PlayerPassed` — e.g.
  `PlayerPassed | args: [47, <gameId>]`. All are delivered to both devices.
- **`correctAnswer` and `penalty` actually reach the reducer — VERIFIED.** Both
  are in `PlayGameHubEvents.sharedRoundEvents` and `lifetimeEvents`, and neither
  payload satisfies `looksLikeCreatedGame`, so `_routeByStatus` does not
  intercept them.
- **`invoke() == true` means the call was dispatched, not that the game action
  succeeded.** No optimistic game state is written anywhere in this change.

### Verification

`flutter analyze` — **0 issues**. `flutter test` — **394 passing / 0 failing**.

Seven tests in `wdyk_timer_test.dart` encoded the old tap-freezes behaviour and
were rewritten to move the trigger from the tap to the event. This is the
[ENGINEERING_RULES](ENGINEERING_RULES.md) §7.2 case — an approved task changing
the expected behaviour — not test weakening; no assertion was dropped.

**A defect in the new tests was caught in final verification and fixed.** Two
failed-dispatch tests asserted `isTimerStarted == null` without ever starting a
timer, so they passed against the old implementation too — the old
`_stopRoundTimer()` early-returned when no timer was running. Both now arm a
real countdown (`TimeStarted` → `TimerUpdatedSeconds 10` → three one-second
pumps → `00:07`), then assert after the failed dispatch that `isTimerStarted` is
still `true`, `currentTimerValue` is still `10`, the display has not restarted,
and the countdown reaches `00:03` four seconds later.

**Detection power was measured, not assumed.** The pre-change `_stopRoundTimer()`
calls were temporarily reinstated from `git show HEAD:`; both rewritten tests
failed, and only those two. The production file was restored byte-identical, and
the analyze and suite runs above were made after the restore.

### NOT verified — EXTERNAL VERIFICATION REQUIRED

With `PlayerAnswered` no longer stopping the timer, the countdown depends
entirely on `CorrectAnswer` or `Penalty` arriving after every answer. If either
can be withheld — a rejected or unscored answer, say — the timer would run to
`00:00` instead of freezing. Nothing in this repository establishes that they
always follow.

### Files changed

| File | Change |
|---|---|
| `game_controller/game_controller.dart` | `_stopRoundTimer()` deleted; `correctAnswer` / `penalty` added to the stop branch; `playerAnswered` removed from it; both actions return `Future<bool>` |
| `pages/rounds/wdyk_round_screen.dart` | guard release on a failed dispatch, behind `mounted` |
| `widgets/rounds/round_score_column.dart` | `playerAnswered` stop branch removed |
| `test/wdyk_timer_test.dart` · `test/wdyk_answer_selection_test.dart` · `test/wdyk_allow_all_test.dart` | rewritten and new coverage |

No documentation other than `TASKS.md` and this file was touched. Nothing was
committed or pushed.

### Residual

- `RoundScoreColumn` and `applySharedRoundEvent` are shared by all five round
  screens, so the change necessarily reaches the other four. VERIFIED inert:
  none of them references `isTimerStarted`, and all four remain static mockups.
- A mid-flight `invoke` exception — a drop *after* dispatch — still throws and
  propagates, and can still strand a guard. Out of scope here.
- **Supersedes earlier timer entries in this file.** The `_stopRoundTimer` guard
  described under **E5** refers to a method that no longer exists. Earlier
  sections stand as historical records and were not rewritten.

---

## Documentation

**Date:** 2026-09-02

Eight files created under `docs/`, written against the current repository state
and the Foundation report. Previous documentation was **not** restored or copied.

`PROJECT_ASSESSMENT.md` · `ENGINEERING_RULES.md` · `TASKS.md` · `ROADMAP.md` ·
`TESTING_STRATEGY.md` · `PRODUCTION_READINESS.md` · `AI_AGENT_WORKFLOW.md` ·
`CHANGELOG.md`

No source or configuration file was modified while writing them.

---

## Explicitly Not Done

| Item | Status |
|---|---|
| **A4 Option D** — decouple handlers from `GameController` state | Open by decision. Option C removed the warnings; the coupling remains. |
| **A5** — UI concerns in the state layer | Open. |
| **E5** — dead-null | Investigated, not modified. |
| **E6** — game-over fallback | Discovered, not fixed. |
| **MA6** — hardcoded `"Strike"` | Discovered, not fixed. |
| **Identity (S9 / S9a / S9b)** | Unchanged, blocked. |
| **T3** — `widget_test.dart` overflow | Still the one failing test; deliberately left. |
| **WDYK and all other rounds** | Not started. Payload contracts **EXTERNAL VERIFICATION REQUIRED**. |
| **Auction contracts** | **EXTERNAL VERIFICATION REQUIRED.** |
| **SEC1, F1, P1, P2, E1, N2, N3, S5, E3** | Untouched — all production blockers remain open. |

---

## Repository State

- **Foundation work and this documentation live in the working tree only.**
  Nothing has been committed or pushed.
- HEAD remains `ee45859`.
- `pubspec.lock` is modified in the working tree.
  - **VERIFIED:** the modification was already present **before** any Foundation
    source edit, and `pubspec.lock` was last committed in `bdc3a61`.
  - **VERIFIED:** the change is two transitive package **downgrades** —
    `1.17.0 → 1.16.0` and `0.7.7 → 0.7.6` — with their accompanying `sha256`
    entries. No direct dependency was added, removed, or re-pinned, and no
    pubspec was edited.
  - **INFERRED:** its exact provenance. The shape is consistent with a resolver
    artifact from an implicit `flutter pub get`, which `flutter analyze` and
    `flutter test` invoke. Since those commands were run during assessment and
    Foundation verification, **it cannot be stated with certainty that this work
    did not cause it.**

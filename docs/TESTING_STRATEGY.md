# Testing Strategy

How this project verifies work.

Related: [TASKS.md](TASKS.md) ·
[ENGINEERING_RULES.md](ENGINEERING_RULES.md#7-tests) ·
[AI_AGENT_WORKFLOW.md](AI_AGENT_WORKFLOW.md)

**Toolchain:** Flutter 3.35.7 / Dart 3.9.2 at `C:\flutter` — pinned by
`.android/local.properties`, not on `PATH`, so invoke by absolute path.

---

## Current Baseline

Compare every run against these numbers, **not against zero**. A change that
leaves them unchanged is a change that broke nothing.

```
flutter analyze   →  0 issues
flutter test      →  144 passing / 1 failing
```

### Before and after the Foundation phase

| | Before | After |
|---|---|---|
| Analyzer issues | **83** | **1** |
| Tests passing | **12** | **124** |
| Tests failing | 1 | 1 |
| Test files | 4 | 10 |
| Test lines | 220 | 1,504 |

The Foundation phase added **112 tests across 6 files** while changing no
behaviour.

### The analyzer baseline is clean

`flutter analyze` reports **0 issues**. The last known finding — a
`dead_null_aware_expression` in `game_controller.dart` — was removed under
**E5**. Because the baseline is clean, any finding in a future run is new and
belongs to whoever introduced it.

### Historical note — the former 1 analyzer issue

`dead_null_aware_expression` at
`packages/play_game/lib/presentation/game_controller/game_controller.dart:141`
(**E5**). Investigated first, then removed once the investigation established
the expression was unreachable and its removal behaviour-preserving — see
[TASKS.md](TASKS.md#4-analyzer-cleanup).

### The 1 failing test

`test/widget_test.dart` — `HomeLauncherPage shows four game buttons`:

```
A RenderFlex overflowed by 104 pixels on the bottom.
```

`HomeLauncherPage` stacks eight `GameButton`s and an `AppTextField` in
`AppScaffold(scrollable: false)`.

- **VERIFIED:** pre-existing, present before any Foundation work.
- **INFERRED:** a harness artifact of the default 800×600 test viewport rather
  than a user-visible defect — `AppScaffold` documents a `ClipRect` safety net
  for non-scrollable bodies.
- Tracked as **T3**, deliberately left.

> **Do not treat this as your regression.** A run showing `144 pass / 1 fail`
> with this same overflow has broken nothing. A failure count above 1, or a
> different failing test, **is** a regression.

---

## The 6 New Test Files

### Tier 1 — pure functions, no container, no backend assumptions

| File | Covers |
|---|---|
| `player_identity_test.dart` | `playerIdsEqual`, `GamePlayer.matchesHubUserId`, `GameOverResult.isWinner` |
| `game_domain_enums_test.dart` | `GameType.fromId`, `StatusGame.fromId`, `TypePenalty.fromId`, `GamePhase.fromHubValue` / `fromHubEvent` |
| `game_session_reducer_test.dart` | `playerIdFrom`, `turnPlayerIdFrom`, `timerValueFrom`, `roundTypeFrom`, `emoteFrom`, `shouldStopReadyTimer`, `gameAfterPlayerLeft`, `gameAfterPlayerReady` |
| `game_models_test.dart` | `CreatedGameModel.looksLikeCreatedGame` / `looksLikeCurrentQuestion` / `merge`, `GameOverResultModel.looksLikeGameOver` |

### Tier 2 — `GameController` via `ProviderContainer` + fakes

| File | Covers |
|---|---|
| `game_controller_routing_test.dart` | initial state; `_routeByStatus` for statuses 1–4 and round types 1–5; game-over win/loss; `_onHubEvent` phase filtering; `onRecovered` invoking `CheckPlayerGame` |
| `game_controller_seating_test.dart` | seating by id and by account `userId`; order independence; single-player roster; `isCurrentUser`; `PlayerLeft` routing and roster removal |

**Harness — VERIFIED as workable today.** `SignalRService` and
`PlayGameHubBindings` are plain classes, so test fakes subclass them;
`sharedPrefsProvider`, `signalRServiceProvider` and `playGameHubBindingsProvider`
are plain `Provider`s and are overridden. Two harness details matter:

- `user_id` is persisted as a **String** by `SharedPrefsService`.
- `gameControllerProvider` is `autoDispose`, so a test that awaits must hold a
  listener (`container.listen(...)`) or state resets mid-test.

`GameSessionReducer` is not exported from the package barrel and is imported by
package path rather than widening the barrel (**A3**).

---

## Characterization Tests

A characterization test records behaviour that is **unresolved**, not correct.
Each is named `CHARACTERIZATION (unresolved)` and carries a comment stating it is
not an endorsement.

**One remains — VERIFIED by grep:**

| Test | Records | Task |
|---|---|---|
| whitespace in `winnerId` | `isWinner` uses exact `==`, so formatting drift that `playerIdsEqual` tolerates is read as "not the winner" | **E1a** |

**Five have been retired** as their underlying questions were resolved and the
defects fixed — each **replaced** by an intent-based assertion, never merely
edited:

| Retired test | Resolved by |
|---|---|
| indeterminate game-over defaults to loss | **E1** — terminal fallback now `GameResult.ended` |
| `isWin` ignored | **E6** — `_resultFromData` is reachable again |
| positional seating (`players[0]` becomes "me") | **S9b** — positional guess removed |
| unmatched id resolves to the current user | **S9** — positive local-ID matching |
| no opponent seated → every id is local | **S9 / S9a** — resolution no longer depends on the opponent |

**Rules for these tests:**

1. They must never be cited as proof that the behaviour is correct.
2. They must not be used to resist a fix once the semantics are resolved.
3. When the underlying question is answered, the characterization test is
   **replaced** by an intent-based assertion, not merely updated.

> **Identity tests are not proof of backend identity semantics.** They assert
> how the client compares and seats values it is *handed*. Which identity the
> hub actually places in `players[].id`, `players[].userId`,
> `PlayerLeft.playerId`, `PlayerEmoted.userId` or `currentTurn` is
> **EXTERNAL VERIFICATION REQUIRED**.

### Identity semantics — RESOLVED

Backend identity semantics were confirmed by the repository owner and the
matching logic was corrected under **S9 / S9a / S9b / S9c**:

- The persisted login `user_id` and hub player ids share **one namespace**.
- Hub player values can name **either** player; they are not inherently local.
- `PlayerLeft` arrives as `[playerId, gameId]` and carries the player id
  directly.

`game_controller_seating_test.dart` was reworked accordingly. It now asserts
**positive local-ID matching** using the observed ids — 47 local, 211403
opponent — and covers positional and map-shaped payloads, seating with the
local player listed first or second, and resolution with no opponent seated.

**The earlier caveat on two seating tests no longer applies.** The rule those
tests encoded — matching the stored `user_id` against `players[].id` /
`players[].userId` — was confirmed correct, so no assertion had to change.
Tracked as **S9-TEST**, now `DONE`.

**Still open:** `GameOverResult.isWinner` compares with exact `==` (**E1a**).
Whether `winnerId` needs tolerant comparison is unverified, and one labelled
characterization test in `player_identity_test.dart` still pins that behaviour.

---

## Testing Priorities

1. **Round-specific handler logic** — `round_screen_handler.dart` is the largest
   uncovered surface. Blocked on payload contracts.
2. **`SignalRService`** — five reconnect paths, two subscription tiers, handler
   re-attachment. Needs a seam (**T2**).
3. **`BaseRepository.guard`** — exception → `Failure` mapping.
4. **`ApiResponse` / `JsonValue`** — envelope and camelCase/PascalCase tolerance.
5. **Auth flows** — `AuthNotifier` login/logout/persistence.
6. **`SecurityGenerator`** — deterministic given a fixed clock.
7. **Datasources** — need a fake `ApiClient` (**T2**).

---

## Test Rules

**Required when:** behaviour changes; a bug is fixed (add the regression case
that would have caught it); pure logic is added or modified; a `Failure`
mapping, JSON parse path, or hub event route changes.

**Not required when:** documentation-only changes; pure renames with no
behavioural effect; code that is untestable without a seam that does not exist
yet — in which case say so and name the blocking task.

**Always:**

- Assert intended behaviour, never the current implementation.
- Never weaken, skip, delete, or modify a test to make the suite pass.
- A red test is evidence. **E6 was discovered exactly this way** — a test
  written to assert intended behaviour failed, and investigation showed the code
  was wrong, not the test.
- Do not assert on user-facing English literals.
- Reset global state in `setUp` / `tearDown`.
- Tests live in the root `test/` directory, including tests for code in
  `packages/` — one command runs everything.

---

## Verification Commands

```bash
# Full suite
C:/flutter/bin/flutter test

# Single file
C:/flutter/bin/flutter test test/game_controller_routing_test.dart

# Analyzer, whole workspace
C:/flutter/bin/flutter analyze

# Per-package via melos — needs the Flutter SDK bin/ on PATH
export PATH="/c/flutter/bin:$PATH"
dart run melos run analyze
```

---

## Definition of Done

A task is **not** complete until:

1. Implementation matches the approved scope — no more, no less.
2. Relevant tests pass, and the full suite matches or improves on
   **144 pass / 1 fail**.
3. `flutter analyze` was run and reports **0 issues**. The baseline is now
   clean, so **any** finding in your run is one you introduced — fix it.
4. `git diff` was reviewed for unintended changes.
5. No unrelated changes are present.
6. The report states what was verified **and what was not**, including anything
   requiring a device, a release build, or the backend.
7. [TASKS.md](TASKS.md) status is updated and [CHANGELOG.md](CHANGELOG.md) is
   appended.

**"It should work" is not a result.** State the command run and its output.

# Roadmap

Overall sequence, with status reflecting what has actually been completed.

Task detail: [TASKS.md](TASKS.md) · Findings:
[PROJECT_ASSESSMENT.md](PROJECT_ASSESSMENT.md) · History:
[CHANGELOG.md](CHANGELOG.md)

---

## Sequence

```
Fresh Assessment                        ✅ COMPLETE
  → Foundation Cleanup & Stabilization  ✅ COMPLETE
    → GameController + Identity + Tests ◐ PARTIAL — tests done, identity BLOCKED
      → Analyzer Clean                  ◐ NEAR-COMPLETE — 1 deferred issue
        → Complete WDYK Changes         ⬜ NOT STARTED — contracts blocked
          → Test & Verify WDYK          ⬜ NOT STARTED
            → Complete Remaining Rounds ⬜ NOT STARTED
              → Auction → Bell → Come Back → Breaker
```

---

## 1. Fresh Assessment — ✅ COMPLETE

Full re-inspection of the current repository, treating all prior findings as
unverified until re-confirmed.

**Delivered:** baseline metrics, architecture review, the merged branch's new
work (GameController split, WDYK files, `TypePenalty`, `PlayerAnsweredDialog`,
`postFrame`), re-verification of every previously known issue, and identification
of newly introduced ones (**A4**, **S9**, **A5**, **E5**).

**Recorded baseline at entry — VERIFIED:** 83 analyzer issues, 12 passing /
1 failing.

---

## 2. Foundation Cleanup & Stabilization — ✅ COMPLETE

**Objective:** make the shared codebase clean and stable before continuing round
development.

| Item | Result |
|---|---|
| **A4 Option C** | Private state accessor in `GameController`; `state` → `_s` at 33 sites in two handler files. No public API added. **VERIFIED** no logic change. |
| **Analyzer cleanup** | 6 redundant imports, 1 unused import, 1 `const` — all mechanical and verified. |
| **Test foundation** | 112 new tests across 6 files. |
| **Analyzer** | **83 → 1** |
| **Tests** | **12 → 124 passing**, 1 pre-existing failure unchanged |

**Scope held — VERIFIED:** `packages/coreapp` 0 files changed; `pages/rounds/`
including WDYK 0 files; `waiting_screen_handler.dart` 0 changes; all pubspecs
0 changes.

**Deliberately not done, and still open:** A4 Option D, E5 (dead-null), E6, MA6
(hardcoded "Strike"), all identity behaviour.

---

## 3. GameController + Identity + Tests — ◐ PARTIAL

**Tests: complete.** Routing, seating, PlayerLeft and game-over behaviour are
now covered, plus the pure layers beneath them.

**Identity: BLOCKED.** No identity behaviour was changed. Six characterization
tests pin current behaviour without endorsing it.

**Blocking questions — EXTERNAL VERIFICATION REQUIRED:**

1. Does the hub always send `userId` on players, or sometimes only a GUID `id`?
2. Is `PlayerLeft.playerId` a game-player id or an account id?
3. Is `PlayerEmoted.userId` the account id?
4. Is `CreatedGame.currentTurn` a game-player id or an account id?
5. Is prefs `user_id` in the same namespace as either hub id?

**Also open here:** **A4 Option D** (handlers still coupled to controller state)
and **A5** (UI concerns in the state layer). Option D is best done *after* the
test coverage that now exists, and needs architectural approval.

**Exit criteria:** the five questions answered; S9 / S9a / S9b resolved;
characterization tests replaced with intent-based assertions.

---

## 4. Analyzer Clean — ◐ PARTIAL

**VERIFIED: `flutter analyze` reports 0 issues.** The last finding —
`dead_null_aware_expression` in `game_controller.dart` — was removed under
**E5**, after investigation established it was unreachable and its removal
behaviour-preserving.

`flutter analyze` is now a trustworthy gate **with a clean baseline**: no
suppressions were added, no rules weakened, no tests deleted or skipped. Any
finding in a future run is new and belongs to whoever introduced it.

**Also in this bucket, still open:** **MA6** (hardcoded `"Strike"` string),
**MA3** (thin lint configuration — sequence after CI so findings are gated).

**Exit criteria:** MA6 fixed; **MA3** adopted; ideally **T4** (CI) in place so
the clean baseline is enforced rather than remembered.

---

## 5. Complete WDYK Changes — ⬜ NOT STARTED

**Blocked.** WDYK hub payload semantics — question, answer, penalty, timer and
turn — are **EXTERNAL VERIFICATION REQUIRED**. Nothing in this repository
establishes them.

**VERIFIED present:** `wdyk_round_screen.dart`, `TypePenalty`,
`PlayerAnsweredDialog`, and round-handler methods gated on `GamePhase.wdyk`.

**Entry criteria:** contracts confirmed; identity resolved or explicitly
scoped out of WDYK; Foundation committed.

---

## 6. Test & Verify WDYK — ⬜ NOT STARTED

Follows implementation. Tests must assert intended behaviour once contracts are
known — not re-state whatever the implementation does.

---

## 7. Complete Remaining Rounds — ⬜ NOT STARTED

**Order:** Auction → Bell → Come Back → Breaker.

Each round's payload contracts are **EXTERNAL VERIFICATION REQUIRED**. Auction
is first and is the most involved — it has its own event group
(`auctionScreenEvents`, `auctionEvents`) covering bidding and answer phases.

---

## Backend Coordination

Start these conversations early; lead time is the constraint, not effort.

| Topic | Needed for | Note |
|---|---|---|
| **Identity semantics** (5 questions) | S9, WDYK, all rounds | Highest leverage — blocks the most work |
| **WDYK payload contracts** | Stage 5 | |
| **Auction payload contracts** | Stage 7 | |
| **Token refresh endpoint** | N2 | The client already stores `refreshToken` with nowhere to send it |
| **WebSocket close-1002 claim** | N1 / transport fallback | Comment-sourced only; if it has lapsed, `skipNegotiation` may be removable with no server change |
| **Request-token scheme** | SEC3 / SEC4 | Server-time source; RSA padding and key size |

---

## Execution Loop

Every task follows:

```
Inspect → Plan → Approval → Implement → Test → Analyze → Review → Report → STOP
```

**Practices that proved useful in the Foundation phase:**

- Capture a baseline before the first edit; compare every later run against it.
- Prove a mechanical change is mechanical — normalising the rename back and
  checking every diff line pairs evenly is what established that A4 Option C
  changed no logic.
- When a test fails because the code is wrong, do not change the test to pass.
  E6 was found exactly this way, and was recorded rather than silently fixed.
- State plainly what was left undone and why.

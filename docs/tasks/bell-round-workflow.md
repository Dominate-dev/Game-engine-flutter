# Bell Round — Workflow, Scenarios & Porting Plan

Source: T30 Android (`BellRoundFragment`, `GameControllerFragment`, `JudgeModeGame`).

Round id: **3** (`GameTypeEnum.BELL` / `GameRoundType.BELL_ROUND`).

This is **round 3**: a **buzz race**, then the winner answers chips. There is **no Pass** and **no strike row** on this screen.

**Impossible** (round 6) reuses the **same layout and almost the same code** (`ImpossibleFragment` + `fragment_bell_round.xml`). Treat Impossible as Bell with harder questions unless the server differs.

There are **two client implementations**:

| Mode | Screen | Who buzzes |
|------|--------|------------|
| PvP / private 1v1 | `BellRoundFragment` | Either player taps **Bell** |
| Judge | `JudgeModeGame` | Judge taps **take turn** for player A or B → `JudgeRingBell` |

---

## 1. Game rules

1. Question is shown. **Nobody’s turn yet** (`isTurnPlaying == null`).
2. Server starts the timer (`TimeStarted`). After the “start time” overlay, the **Bell button** appears.
3. **First player to ring** wins the right to answer → `RingBell(gameId)`.
4. Server sends `ChangeTurn(winnerId)`.
5. Winner sees chips and taps one → `SubmitAnswer(gameId, answerId)`.
6. **Correct** → overlay, then next question (race again).
7. **Wrong** → wrong overlay (not a WDYK-style strike UI on this screen).
8. **Timeout** → red overlay, chips cleared, back to waiting / next question (server).
9. Repeat until `RoundFinished`.

Unlike What Do You Know, **both** players can act before a turn exists (the buzz). Unlike Auction, there is **no bid**.

The **server owns** who won the race. Client only sends `RingBell` and shows “You’re the fastest” / “He’s the fastest” from `ChangeTurn`.

---

## 2. State machine

```
IDLE (round intro, ~2s Lottie)
  → WAITING (no turn: hide chips, hide bell, clear title)
  → TIME_STARTED overlay (~2s)
  → RACING (bell visible + clickable; still no turn)
       → RingBell
  → WINNER_TURN  (“You’re the fastest” if you buzzed, else “He’s the fastest”)
       → SubmitAnswer
       → Correct / Wrong / Timeout
  → NEXT QUESTION → back to WAITING / RACING
  → ROUND_FINISHED → Comeback (or next type)
```

If `ChangeTurn` happens **without** a race (`isBelling == false`), use the normal “Your turn” / “Turn / {name}” overlays (same as WDYK).

---

## 3. Hub contract

### 3.1 Client → server

| Method | Payload | When |
|--------|---------|------|
| `RingBell` | `gameId` | PvP: tap the Bell |
| `SubmitAnswer` | `gameId`, `answerId` | Winner taps a chip. Judge: chip, or `0` as wrong after a turn exists |
| `JudgeRingBell` | `gameId`, `playerId` | Judge awards the buzz to that player |

### 3.2 Server → client

**Round screen (PvP)**

| Event | Payload | Meaning |
|-------|---------|---------|
| `NextQuestion` | `CurrentQuestionModel` | Clear chips if the list was showing |
| `Penalty` | `{ playerId, type }` | `1` timeout, `2` wrong |
| `PlayerAnswered` | `{ answerText, answerTextEn }` | Reveal text |
| `CorrectAnswer` | `string` playerId | Correct overlay (T30 does **not** branch on playerId) |

**Match shell (parent)**

| Event | Payload | Meaning |
|-------|---------|---------|
| `NextRoundStarted` | `int` = **3** | Navigate to Bell; `clearDataRoundThree()` |
| `ChangeTurn` | `string` playerId or empty | Winner / next player; empty = race reset |
| `TimeStarted` | — | Parent plays timer Lottie, then `_isStartTimer = true` |
| `TimerUpdatedSeconds` | seconds | Countdown |
| `GameUpdated` / `NextQuestion` | question + answers | Title, chips data |
| `RoundFinished` / `GameOver` / `GameRestore` | — | Same as other rounds |

There is **no** dedicated `PlayerRangBell` event. The race result is **`ChangeTurn`**.

### 3.3 Shared models

Same as What Do You Know: `AnswersModel`, `CurrentQuestionModel`, `PenaltyModel`, `PlayerAnswersModel`.

---

## 4. Local UI state (PvP)

| Field | Role |
|-------|------|
| `isTurnPlaying` | `true` you answer / `false` opponent / `null` racing or idle |
| `isBelling` | Bell **visible**. Set `true` when timer started **and** turn is still `null` |
| `isBellingClickable` | Bell **enabled** (alpha 1 vs 0.4). Mirrors `isStartTimer` |
| `_isStartTimer` | Parent sets `true` after the 2s “start time” Lottie |
| `questionTitle` | Question text |
| `answerModels` | Chips; bound when it is **your** turn and timer has started |

`clearDataRoundThree()`: `isBelling = false`, `isTurnPlaying = null`, also clears leftover filter fields.

### Control enablement (PvP)

| Control | When |
|---------|------|
| Bell **visible** | `isBelling == true` |
| Bell **clickable** | `isBellingClickable == true` (`isStartTimer`) |
| Chips **visible** | `isTurnPlaying == true` |
| Chips **clickable** | Your turn **and** `isStartTimer` (then `adapter.isClickable = true`) |

On Bell tap: reset local timer, play `bell_round_t30`, `RingBell`. Button hide happens when `ChangeTurn` sets `isBelling = false`.

On chip tap: reset timer, click SFX, `SubmitAnswer`, `isClickable = false`.

---

## 5. Screens

1. **Round intro** — bell Lottie ~2s, `start_round_t30`. Title: “Bell Round”.
2. **Question + empty chip area** — chips hidden until your turn.
3. **Start-time overlay** — parent (`anim_timer`, “start time”) ~2s, then bell arms.
4. **Big Bell button** — bottom center, purple circle; faded until clickable.
5. **Fastest overlays** — “You’re the fastest!” / “He’s the fastest!” + `you_faster_t30`.
6. **Normal turn overlays** — if turn assigned without a buzz.
7. **Answer chips** — same flex chips as WDYK (winner only).
8. **Correct / wrong / timeout / answer-reveal** overlays.
9. **Report** — email with `questionId`.
10. **Judge** — per-player Take turn = buzz; after a turn exists, that button label becomes **Wrong** (`SubmitAnswer(0)`).

### Dialog timers (exact ms from T30)

`isTimer` / `timer` = auto-dismiss. Match countdown is **not** these overlays. **Impossible** uses the same values.

| Overlay | Helper | Duration |
|---------|--------|----------|
| Round intro | `showDialogGameStartPlayLottie` | **2000** |
| Then start looping music | `delay` | **3000** |
| Parent “start time” (arms Bell) | `showDialogGameStartPlayLottie` | **2000** |
| After start-time overlay, `_isStartTimer = true` | `delay` | **2000** |
| Fastest / turn / correct / wrong | `showDialogCircularLotti` | **1500** |
| After turn overlay | `delay` | **1500** |
| Timeout | `showDialogCircularLotti` | **1500** |
| Answer reveal | `showDialogAnswer` | **1500** |

**Judge**

| Overlay | Duration |
|---------|----------|
| Round intro | **3000** |
| After intro, start music | `delay(4000)` |
| Start time | **2000** + `delay(2000)` |
| Turn name | **1500** + `delay(1500)` |
| Timeout | **1500** |

---

## 6. How T30 wires the race (important)

Parent `TIME_STARTED` → `startTimer()`:

1. Play `start_time_t30`.
2. Show timer Lottie 2s.
3. `_isStartTimer = true`.

Bell fragment observes `isStartTimer`:

```text
if (isTurnPlaying == null && isStartTimer)
    isBelling = true          // show Bell
isBellingClickable = isStartTimer

if (isTurnPlaying == true)
    chips clickable + bind answers
```

`ChangeTurn` observer:

```text
reset local timer
if my turn:
  if isBelling:  “You’re the fastest”; isBelling = false
  else:          “Your turn”
if opponent:
  if isBelling:  “He’s the fastest”; isBelling = false
  else:          “Turn / {name}”
if null:
  clear title + chips
  isBelling = false
  isBellingClickable = false
```

So: **Bell only during “timer running, no turn yet”.** After a winner, Bell hides.

---

## 7. Workflow scenarios

### A. Happy path — PvP

1. Auction ends → `NextRoundStarted(3)` → Bell screen; reset race flags.
2. Intro Lottie; music after ~3s.
3. `GameUpdated` / `NextQuestion` sets title (chips still hidden).
4. `TimeStarted` → start-time overlay → `isBelling = true`, Bell clickable.
5. You tap Bell → `RingBell`.
6. `ChangeTurn(you)` while `isBelling` → “You’re the fastest!”; Bell gone; chips show.
7. You tap a chip → `SubmitAnswer`.
8. `CorrectAnswer` + `PlayerAnswered` → overlays.
9. `NextQuestion` → clear chips; `ChangeTurn("")` often resets race; wait for next `TimeStarted`.

### B. Opponent buzzes first

You tap late or not at all. `ChangeTurn(opponent)` while racing → “He’s the fastest!”; chips stay hidden; you watch `PlayerAnswered`.

### C. Both tap Bell

Both may send `RingBell`. **Server picks one.** UI follows `ChangeTurn` only. Do not locally assume you won.

### D. Bell before timer armed

`isBellingClickable == false` (alpha 0.4). Tap should not fire (layout `clickable` bound). If it does, still sending `RingBell` is a bug — ignore until armed.

### E. Correct answer

Correct Lottie + SFX; timer reset. T30 shows this to **both** (no `playerId` check).

### F. Wrong answer

`Penalty(type = 2)` → wrong Lottie + SFX. Timer reset. Server may give opponent the turn or next question.

### G. Timeout while answering (or racing)

`Penalty(type = 1)` → `isBelling = false`, lock + **clear** chips, red timeout overlay.

### H. Next question

Fragment: if chips were showing, `adapter.clear()`. Parent still updates title/answers. Race flags reset on `ChangeTurn(null)` or `clearDataRoundThree`.

### I. Turn without buzzing

`ChangeTurn` with `isBelling == false` → WDYK-style turn overlays. Possible if the server assigns a turn without a race.

### J. Restore

Parent restore → `nextRound(3)` + `gameUpdate`. If `isTurnPlaying == null`, wait for `TimeStarted` to show Bell. If a turn already exists, skip Bell and show chips for the winner.

### K. Round / match end

`RoundFinished` → next round (Comeback / Makeup). `GameOver` as usual.

### L. Report

Email with `questionId`.

---

## 8. Judge-mode extras

Players do not buzz. Judge decides who “rang”.

| Situation | Judge action | Hub |
|-----------|----------------|-----|
| No turn yet (`isFirstPlayerTurn` and `isSecondPlayerTurn` both `null`) | Take turn on player A or B | `JudgeRingBell(gameId, playerId)` |
| A turn already exists | Same button becomes **Wrong** | `SubmitAnswer(gameId, 0)` |
| Mark a chip | Tap answer | `SubmitAnswer` / `JudgeSubmitAnswer` |

`ChangeTurn` on Bell: **reset chip selection**, no “turn” name dialog (unlike WDYK).

`NextQuestion` on Bell: clear turn, stop timer, load new answers, lock chips.

Take-turn button styling (`roundId == 3` or `6`):

| `isPlayerTurn` | Button |
|----------------|--------|
| `null` | Enabled, full alpha (can buzz for them) |
| `true` | Still enabled (Wrong) |
| `false` | Disabled, alpha 0.3 |

---

## 9. T30 file map

| Area | Path |
|------|------|
| PvP screen | `ui/gamelobbyinterface/game/bellround/BellRoundFragment.kt` |
| Layout | `res/layout/fragment_bell_round.xml` |
| Impossible clone | `ui/gamelobbyinterface/game/impossible/ImpossibleFragment.kt` |
| Parent navigate | `GameControllerFragment.nextRound` → `BELL.id` |
| Reset | `GameControllerViewModel.clearDataRoundThree()` |
| Timer arm | `GameControllerFragment.startTimer()` → `_isStartTimer` |
| Judge buzz | `JudgeModeGame.judgeRingBellHub` |
| Take-turn UI | `JudgeModeBindingAdapters.handleTakeRoleButton` |
| Nav | `game_nav_graph.xml` → `bellRoundFragment` |
| Hub | `RING_BELL = "RingBell"`, `JUDGE_RING_BELL = "JudgeRingBell"` |

`FilterAnswerAdapter` is **injected but unused** in `BellRoundFragment`. REST `filterAnswer` is leftover (typed search). **Do not port** unless you want type-ahead answers.

---

## 10. Implementation plan (other project)

### Phase 0 — Spec lock

- Confirm first-buzz-wins via `ChangeTurn` (no extra event).
- Confirm timeout vs wrong do **not** use WDYK strike dots.
- Confirm Impossible is the same UX.

### Phase 1 — Domain

- Phases: `Idle`, `Racing`, `Answering`.
- Flags: `bellVisible`, `bellArmed`, `isMyTurn`.
- Reuse question/answer/penalty models.

### Phase 2 — Hub

- Round: Penalty, CorrectAnswer, PlayerAnswered, NextQuestion (clear chips).
- Shell: ChangeTurn, TimeStarted, timers, GameUpdated, round end, restore.
- `RingBell` only while `Racing && bellArmed`.

### Phase 3 — UI

- Intro → question → start-time overlay → Bell.
- Fastest vs normal turn overlays.
- Chips only for winner; lock after submit.

### Phase 4 — Judge (optional)

- `JudgeRingBell` while no turn; Wrong = `SubmitAnswer(0)` after.

### Phase 5 — Test matrix

| # | Scenario | Expect |
|---|----------|--------|
| 1 | Enter round | Intro; Bell hidden |
| 2 | TimeStarted, no turn | After overlay, Bell visible + armed |
| 3 | Tap Bell before armed | Ignored |
| 4 | You buzz first | “You’re the fastest”, chips yours |
| 5 | Opponent buzzes first | “He’s the fastest”, chips hidden |
| 6 | Double RingBell | UI follows server `ChangeTurn` only |
| 7 | Correct | Overlay both clients |
| 8 | Wrong | Wrong overlay, not strike row |
| 9 | Timeout | Red overlay, chips cleared, Bell hidden |
| 10 | Next question | Race again after timer |
| 11 | ChangeTurn empty | Title/chips/Bell reset |
| 12 | Restore during race | Show Bell after TimeStarted |
| 13 | Restore during answer | No Bell; chips for current turn |
| 14 | Judge buzz player A | That player’s turn |
| 15 | Judge Wrong after turn | `SubmitAnswer(0)` |
| 16 | Round finished | Leave Bell |

---

## 11. What not to copy blindly

- `CorrectAnswer` overlay is shown even if **you** were not the answering player.
- Bell visibility (`isBelling`) vs armed (`isBellingClickable`) — both required.
- `FilterAnswerAdapter` / `filterAnswer` API are dead for this round.
- Impossible is a copy-paste of this fragment; share one component when porting.
- Parent `TIME_STARTED` is what **arms** the Bell, not the fragment’s own subscribe list (Bell does **not** subscribe to `TimeStarted`).
- `NEXTQUESTION_` on the fragment only **clears chips**; title still comes from the parent.

---

## 12. Suggested reducer (porting)

```text
NextRoundStarted(3)           → Bell screen; phase=Idle; hide bell
TimeStarted (after overlay)   → if no turn: phase=Racing; bellVisible=true; bellArmed=true
RingBell                      → wait for server (do not hide bell until ChangeTurn)
ChangeTurn(id) + wasRacing    → hide bell; if me: “fastest” + chips; else “he’s fastest”
ChangeTurn(id) + !wasRacing   → normal turn overlay
ChangeTurn(empty)             → phase=Idle; clear Q/chips; hide bell
SubmitAnswer                  → lock chips
CorrectAnswer / PlayerAnswered→ overlays; reset timer
Penalty(2)                    → wrong overlay
Penalty(1)                    → timeout; clear chips; hide bell
NextQuestion                  → clear chips; wait for TimeStarted
GameRestore                   → if turn set: Answering; else Idle until TimeStarted
```

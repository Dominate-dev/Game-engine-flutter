# Comeback Round — Workflow, Scenarios & Porting Plan

Source: T30 Android (`ComeBackRoundFragment`, `GameControllerFragment`, `JudgeModeGame`).

Round id: **4** (`GameTypeEnum.MAKEUP` / `GameRoundType.COME_BACK_ROUND`).

UI name: **Comeback** / **جولة التعويض**. Server name: **Makeup**.

This is **round 4**: a limited-try catch-up. Same chip answers as What Do You Know, but **no Pass**, **no strikes**, **no Bell**. Each player has `makeupTryCount` / `maxMakeupTryCount` attempts.

Breaker (round 5) is almost the same screen with a different intro and one layout quirk — see `docs/breaker-round-workflow.md`.

---

## 1. Game rules

1. Shown after Bell (or whenever the server sends type `4`).
2. Question + answer chips. Player taps one → `SubmitAnswer(gameId, answerId)`.
3. **Limited attempts**: `tryCount` (used) vs `maxTryCount` (cap), from `PlayersModel.makeupTryCount` / `maxMakeupTryCount` on `GameUpdated`.
4. Display: `used/max` plus warning *“You only have N attempts”*.
5. If `used >= max` → chips cleared and locked.
6. **Correct** → overlay for you; opponent sees “{Name} answered correctly”.
7. **Wrong** → wrong overlay **only if you** were the one who missed (`Penalty` type 2 + your id).
8. **Timeout** → red overlay, clear chips and question title.
9. No Pass. No strike dots. No buzz.

The **server** decides who is allowed to answer and when the round ends (often the trailing player). T30’s PvP UI does **not** hide chips by turn — porting should still gate on `ChangeTurn`.

---

## 2. State machine

```
IDLE (intro Lottie ~2s)
  → QUESTION (bind chips from GameUpdated)
  → TAP (lock chips) → wait server
       → Correct → overlay → next Q or GameUpdated (tryCount++)
       → Wrong (me) → overlay → maybe retry if used < max
       → Timeout → clear board
  → used >= max → lock + clear chips
  → ROUND_FINISHED → Breaker or Impossible / game over
```

---

## 3. Hub contract

### 3.1 Client → server

| Method | Payload | When |
|--------|---------|------|
| `SubmitAnswer` | `gameId`, `answerId` | Tap a chip |
| `JudgeSubmitAnswer` | `gameId`, `answerId`, `playerId` | Judge: after selecting a chip, credit that player |

Judge does **not** send `SubmitAnswer` on chip tap for this round. Tap only stores `judgeAnswerId`; submit is a later judge action. If no chip selected, Comeback/Breaker fallback uses **first answer id**.

### 3.2 Server → client

**Round screen**

| Event | Payload | Meaning |
|-------|---------|---------|
| `NextQuestion` | `CurrentQuestionModel` | If chip list empty, bind answers |
| `Penalty` | `{ playerId, type }` | `1` timeout, `2` wrong |
| `CorrectAnswer` | `string` playerId | You vs opponent overlay |

`PLAYER_ANSWERED_` is **handled in code but not subscribed** in T30. Do **not** copy that; subscribe if you want the answer-reveal toast.

**Match shell**

| Event | Meaning |
|-------|---------|
| `NextRoundStarted(4)` | Navigate here; `clearDataRoundThree()` |
| `GameUpdated` | Question, shuffled answers, **your** `makeupTryCount` / `maxMakeupTryCount`, points |
| `NextQuestion` | Title, answers, count (parent) |
| `ChangeTurn` | Whose turn (parent; Comeback fragment ignores it for chip visibility) |
| `TimerUpdatedSeconds` | Restart countdown; parent also sets `tryCount = 0` |
| `TimeStarted` / `RoundFinished` / `GameOver` / `GameRestore` | Same as other rounds |

### 3.3 Player fields

```kotlin
makeupTryCount: Int      // used attempts → tryCount
maxMakeupTryCount: Int   // cap → maxTryCount
```

Set in `GameControllerFragment.gameUpdate()` for the **local** user.

---

## 4. Local UI state (PvP)

| Field | Role |
|-------|------|
| `tryCount` | Used makeup tries |
| `maxTryCount` | Max tries |
| `questionTitle` | Question |
| `answerModels` | Chips |
| `isGameUpdated` | Rebind chips |

**Clickable** if `tryCount < maxTryCount` (checked 650ms after bind).

**Locked** if `tryCount >= maxTryCount` (observer clears adapter).

Chips are **always visible** (unlike WDYK/Bell). No `isTurnPlaying` on the RecyclerView.

---

## 5. Screens

1. Intro — `anim_game_come_back`, “Come Back Round”.
2. Question + flex chips.
3. Attempts row: `Number of attempts: {used}/{max}`.
4. Warning plural (`warning_count_msg`).
5. Report.
6. Overlays: correct (you), “X answered correctly” (them), wrong (you only), timeout.

### Dialog timers (exact ms from T30)

`isTimer` / `timer` = auto-dismiss. Match countdown is **not** these overlays.

| Overlay | Helper | Duration |
|---------|--------|----------|
| Round intro | `showDialogGameStartPlayLottie` | **2000** |
| Then start looping music | `delay` | **3000** |
| Correct (you) | `showDialogCircularLotti` | **1500** |
| Wrong (you) | `showDialogCircularLotti` | **1500** |
| Timeout | `showDialogCircularLotti` | **1500** |
| Opponent correct | `showDialogAnswer2` | **2000** |
| Answer reveal (handler exists; not subscribed) | `showDialogAnswer` | **1500** |
| Enable chips after bind | `Handler.postDelayed` | **650** (not a dialog) |

**Judge**

| Overlay | Duration |
|---------|----------|
| Round intro | **3000** |
| After intro, start music | `delay(4000)` |
| Turn name | **1500** + `delay(1500)` |
| Timeout | **1500** |

---

## 6. Workflow scenarios

### A. Happy path

1. Bell ends → `NextRoundStarted(4)` → Comeback.
2. Intro; music after ~3s.
3. `GameUpdated` → chips after 650ms if tries remain.
4. Tap chip → `SubmitAnswer`.
5. `CorrectAnswer(you)` → correct overlay; timer reset.
6. Next question or round end.

### B. Opponent answers correctly

`CorrectAnswer(other)` → toast “{firstName} answered correctly” (`showDialogAnswer2`, ~2s). No green Lottie for you.

### C. Wrong (you)

`Penalty(2, you)` → wrong Lottie. Tries increment on next `GameUpdated`. If still `used < max`, chips rebind clickable.

### D. Wrong (opponent)

No wrong overlay for you.

### E. Timeout

`Penalty(1)` → timeout Lottie, lock, **clear chips and title**.

### F. Out of attempts

`tryCount >= maxTryCount` → clear chips, not clickable. Wait for server (next Q, turn, or round end).

### G. Next question with empty adapter

Fragment `NextQuestion`: bind only if `adapter.items` is empty. Parent still sets title/answers.

### H. Timer tick zeros tries (T30 quirk)

Parent `TimerUpdatedSeconds` sets `tryCount = 0`. That can **re-enable** chips. When porting, do **not** reset makeup tries on timer unless the server says so.

### I. Restore

Parent `nextRound(4)` + `gameUpdate` (tries + question).

### J. Judge

- Chip tap: store id, stop timer (Comeback shares that stop with WDYK).
- Credit player: `JudgeSubmitAnswer`.
- `NextQuestion`: clear turn, lock chips, load answers.

---

## 7. T30 file map

| Area | Path |
|------|------|
| Screen | `.../game/comebackround/ComeBackRoundFragment.kt` |
| Layout | `res/layout/fragment_come_back_round.xml` |
| Attempts binding | `ComeBackRoundBindingAdapter.kt` (`used/max`, warning plural) |
| Navigate | `GameTypeEnum.MAKEUP` → `comeBackRoundFragment` |
| Tries source | `PlayersModel` + `gameUpdate()` |

---

## 8. Porting plan

1. One **limited-try Q&A** component; theme it as Comeback vs Breaker.
2. Gate chips on **turn + remaining tries** (improvement over T30).
3. Subscribe `PlayerAnswered` if you want reveal text.
4. Do not zero `tryCount` on timer.
5. Tests: correct you/them, wrong you/them, timeout, last try locks, restore, judge select-then-submit.

### Test matrix

| # | Scenario | Expect |
|---|----------|--------|
| 1 | Enter round | Intro, chips if tries left |
| 2 | Correct (me) | Green overlay |
| 3 | Correct (them) | “{Name} answered correctly” |
| 4 | Wrong (me) | Wrong overlay; tryCount++ |
| 5 | Wrong (them) | No wrong overlay |
| 6 | Last try used | Chips gone / locked |
| 7 | Timeout | Clear question + chips |
| 8 | Next Q | New chips if tries remain |
| 9 | Restore | Same tries + question |
| 10 | Judge tap then credit | `JudgeSubmitAnswer` |

---

## 9. What not to copy blindly

- `PLAYER_ANSWERED` handler without subscribe.
- Chips visible for both players (no turn gate).
- `TimerUpdatedSeconds` → `tryCount = 0`.
- `clearDataRoundThree()` on navigate also clears **Bell** flags (shared reset).
- Kotlin is a near-copy of Breaker; share one class when porting.

---

## 10. Suggested reducer

```text
NextRoundStarted(4)     → Comeback UI, intro
GameUpdated             → question, answers, tryCount/maxTryCount
                          if used >= max: lock else bind chips
SubmitAnswer            → lock chips
CorrectAnswer(me)       → correct overlay
CorrectAnswer(other)    → “{name} answered correctly”
Penalty(2, me)          → wrong overlay
Penalty(1)              → timeout; clear board
NextQuestion            → bind if empty; parent fills title
ChangeTurn              → (recommended) only winner/active can tap
RoundFinished           → leave
```

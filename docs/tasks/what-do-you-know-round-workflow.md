# What Do You Know Round — Workflow, Scenarios & Porting Plan

Source: T30 Android (`WhatDoYouKnowFragment`, `GameControllerFragment`, `JudgeModeGame`).

Round id: **1** (`GameTypeEnum.WHAT_DO_YOU_KNOW` / `GameRoundType.WHAT_DO_YOU_KNOW_ROUND`).

This is **round 1** of a match: turn-based multiple choice. One player answers at a time. Wrong answers and timeouts give **strikes** (max 3). After **2 strikes**, **Pass** can unlock (once), if the server still has remaining passes.

There are **two client implementations**:

| Mode | Screen | Who answers |
|------|--------|-------------|
| PvP / private 1v1 | `WhatDoYouKnowFragment` | The player whose turn it is |
| Judge | `JudgeModeGame` | Judge starts the timer, taps answers / strike / pass for the active player |

All-in-one uses a **different** answer API (`SubmitAnswer` on the All-in-one hub). It is **not** this screen.

---

## 1. Game rules

1. Server sends a question + a list of answer chips (`answers`).
2. `ChangeTurn(playerId)` decides who may tap. The other player **cannot see chips** (`INVISIBLE`).
3. Active player taps one chip → `SubmitAnswer(gameId, answerId)`.
4. **Correct** → points, overlay, then next question or turn change (server decides).
5. **Wrong** → `Penalty(type = 2)` → strike. Timer often resets.
6. **Timeout** → `Penalty(type = 1)` → strike (and timeout overlay for the spectator).
7. Each player has **3 strike slots**. `player.penalty` is the strike count.
8. **Pass** is a skip. It is **not** always available:
   - Server: `player.passes > 0` → `enablePass`
   - Client UX: Pass UI lights up after **2 strikes** (`userPass`)
   - Copy: *“You can use the pass button only once”*
9. After Pass / correct / next question, chips reload from `GameUpdated` / `NextQuestion`.

The **server owns truth**. Client shows overlays and sends one hub call per tap.

---

## 2. State machine

```
IDLE (round intro, ~2s Lottie)
  → WAITING_TURN (isTurnPlaying = null: no Pass, chips hidden)
  → MY_TURN
       → tap answer → wait for Correct / Penalty
       → or Pass (if unlocked)
  → OPPONENT_TURN (watch overlays, chips hidden)
  → STRIKE / TIMEOUT overlay
  → NEXT QUESTION (chips locked until new turn + timer)
  → ROUND_FINISHED → Auction (round 2)
```

Unlike Auction, there is **no bidding phase**. One question, one active player, repeat.

---

## 3. Hub contract

### 3.1 Client → server

| Method | Payload | When |
|--------|---------|------|
| `SubmitAnswer` | `gameId`, `answerId` | PvP: tap a chip. Judge: tap a chip, or `0` for strike |
| `Pass` | `gameId` | Skip this question (if allowed) |
| `StartGameTimer` | `gameId` | **Judge only**: start the countdown for the current question |
| `JudgeSubmitAnswer` | `gameId`, `answerId`, `playerId` | **Judge only**: credit a correct (used more on later rounds; WDYK often uses `SubmitAnswer`) |

### 3.2 Server → client

Handled on the **round screen** (PvP):

| Event | Payload | Meaning |
|-------|---------|---------|
| `Penalty` | `{ playerId, type }` | `1` timeout, `2` wrong answer |
| `CorrectAnswer` | `string` playerId | That player was correct |
| `PlayerAnswered` | `{ playerId, answerText, answerTextEn }` | Reveal the chosen text to both |
| `PlayerPassed` | `string` playerId | Someone passed |
| `TimeStarted` | — | First time: bind answer chips |
| `NextQuestion` | subscribed here, **handled on parent** | New question |

Handled on the **match shell** (`GameControllerFragment`):

| Event | Payload | Meaning |
|-------|---------|---------|
| `NextRoundStarted` | `int` = **1** | Enter this round (also default start of `game_nav_graph`) |
| `ChangeTurn` | `string` playerId or empty | Whose turn; empty = nobody |
| `GameUpdated` | `CreatedGame` | Question, shuffled answers, points, `penalty`, `passes` |
| `NextQuestion` | `CurrentQuestionModel` | Title, answers, `questionNumber/roundTotal` |
| `TimerUpdatedSeconds` | `double` seconds | Restart local countdown; also resets `tryCount` |
| `TimeStarted` | — | Start timer (parent also listens) |
| `RoundFinished` / `GameOver` / `GameFinished` | — | Leave round |
| `GameRestore` | `CreatedGame` | Reconnect; navigate to type + `gameUpdate` |

### 3.3 Models (T30)

```kotlin
data class AnswersModel(
    val id: Int? = null,
    val text: String? = null,
    val textEn: String? = null,
    var isSelected: Boolean = false
)

data class CurrentQuestionModel(
    val id: Long,
    val text: String?,
    val textEn: String?,
    val description: String? = null,
    val type: Int,
    val image: String? = null,
    val video: String? = null,
    val audio: String? = null,
    val answers: List<AnswersModel>,
    val maxCorrectAnswersCount: Int? = null,
    val questionNumber: Int? = null,
    val roundTotalQuestionsCount: Int? = null
)

data class PenaltyModel(
    val playerId: String,
    val type: Int   // 1 timeout, 2 wrong
)

data class PlayerAnswersModel(
    val playerId: String? = null,
    val answerText: String? = null,
    val answerTextEn: String? = null
)

data class PlayersModel(
    val id: String,
    var playerName: String,
    val profileImageUrl: String? = null,
    val penalty: Int,      // strike count 0–3
    val points: Int,
    val passes: Int = 0,   // remaining pass tokens
    val isReady: Boolean,
    val makeupTryCount: Int,
    val maxMakeupTryCount: Int
)
```

On `GameUpdated`, answers are **shuffled** before bind (`answers.shuffled()`).

---

## 4. Local UI state (PvP)

| Field | Role |
|-------|------|
| `isTurnPlaying` | `true` you / `false` opponent / `null` nobody |
| `questionTitle` | Localized question text |
| `questionCountTitle` | `questionNumber/roundTotalQuestionsCount` |
| `answerModels` | Chip list |
| `userStrikes` / `playerStrikes` | From `player.penalty` |
| `enablePass` | `player.passes > 0` (server still allows Pass) |
| `userPass` | Client: Pass highlighted after **2** strikes |
| `inFirstTime` | Fragment flag: first `TimeStarted` binds chips |

### Control enablement (PvP)

| Control | Enabled when |
|---------|----------------|
| Answer chips | `isTurnPlaying == true` and adapter `isClickable` |
| Chip visibility | `VISIBLE` if my turn, else `INVISIBLE` (layout still occupies space) |
| Pass button visible | `isTurnPlaying == true` (hidden if `null` or opponent) |
| Pass actually usable | `userPass && enablePass` (alpha 1.0 vs 0.3) |

On tap: play click SFX, `SubmitAnswer`, immediately `isClickable = false` (wait for server).

### Strike UI (3 slots)

PvP maps `penalty` with **minus one** before indexing:

| Server `penalty` | Lit slot index | Pass (`userPass`) |
|------------------|----------------|-------------------|
| 0 | none | `false` |
| 1 | 0 | — |
| 2 | 1 | `true` |
| 3 | 2 | stays as set |

Judge maps `penalty` **directly** as 1 / 2 / 3 → slots 0 / 1 / 2. Pass unlocks at **2**.

Porting: prefer **one** mapping (`penalty == 2` unlocks Pass) and document it. Do not mix both.

---

## 5. Screens

1. **Round intro** — WDYK Lottie ~2s, SFX `start_round_t30`.
2. **Play screen** — 3+3 strike dots, question, flex chips, Pass, report, pass warning text.
3. **Turn overlay** — “Your turn” vs “Turn / {opponent name}”.
4. **Correct overlay** — green Lottie + `right_answer_t30`.
5. **Strike overlay** — strike Lottie ~2s + `get_strick_t30` (skipped if app in background).
6. **Timeout overlay** — red Lottie + `time_over_t30` (spectator on timeout).
7. **Answer reveal toast** — chosen text (or “Skip” on pass) ~1.5s.
8. **Judge extras** — Start timer button, strike buttons (submit `answerId = 0`), pass buttons per player.

### Dialog timers (exact ms from T30)

`isTimer` / `timer` = auto-dismiss. Match countdown (`00:30`) is **not** these overlays.

| Overlay | Helper | Duration |
|---------|--------|----------|
| Round intro | `showDialogGameStartPlayLottie` | **2000** |
| Then start looping music | `delay` (not a dialog) | **3000** |
| Your turn / their turn | `showDialogCircularLotti` | **1500** |
| After turn overlay, bind chips | `delay` | **1500** |
| Correct | `showDialogCircularLotti` | **1500** |
| Strike | `showDialogGameStartPlayLottie` | **2000** |
| Timeout (spectator) | `showDialogCircularLotti` | **1500** |
| Answer reveal / Skip | `showDialogAnswer` | **1500** |

**Judge**

| Overlay | Duration |
|---------|----------|
| Round intro | **3000** |
| After intro, start music | `delay(4000)` |
| Strike | **3000** |
| Start time | **2000** + `delay(2000)` before chips clickable |
| Turn name | **1500** + `delay(1500)` |
| Timeout | **1500** |

---

## 6. Workflow scenarios

### A. Happy path — PvP

1. Match starts or previous round ends → `NextRoundStarted(1)` (or graph default) → What Do You Know.
2. Intro Lottie ~2s; music after ~3s.
3. `GameUpdated` fills question, shuffled answers, points, strikes, `enablePass`.
4. `ChangeTurn(you)` → “Your turn”; chips visible and clickable.
5. `TimeStarted` / `TimerUpdatedSeconds` → countdown.
6. You tap a chip → `SubmitAnswer`.
7. `CorrectAnswer(you)` → correct overlay; timer reset.
8. `PlayerAnswered` → both see the answer text.
9. `NextQuestion` + `ChangeTurn` → repeat until `RoundFinished` → Auction.

### B. Opponent’s turn

`ChangeTurn(opponent)` → chips hidden, Pass hidden, “Turn / {name}”. You still see `PlayerAnswered` / their strikes via `GameUpdated`.

### C. Wrong answer (you)

`Penalty(type = 2, you)` → stop timer, lock chips, strike overlay. `GameUpdated` increments `penalty` → strike dots. If that was strike **2**, Pass lights up (if `passes > 0`).

### D. Wrong answer (opponent)

You do **not** show the strike Lottie for their wrong (only `playerId == me` on type 2). Their dots update on `GameUpdated`.

### E. Timeout (you)

`Penalty(type = 1, you)` → lock chips, **strike** overlay (not the red timeout).

### F. Timeout (opponent)

`Penalty(type = 1, opponent)` → **timeout** overlay for you (spectator).

### G. Pass — allowed

Pass visible on your turn. `userPass && enablePass` → `Pass(gameId)`.

- You: skip overlay + `pass_t30`.
- Opponent: answer-reveal with “Skip”.
- Timer reset. Server typically `ChangeTurn` / `NextQuestion`.

### H. Pass — blocked

- Not your turn → button gone.
- `enablePass == false` (`passes == 0`) → snackbar *“You can't use the Pass button”* even if tapped.
- Fewer than 2 strikes → button faded (`userPass == false`).

### I. First question chip bind

`inFirstTime = true` until first `TimeStarted`, then bind chips. Later turns bind after the 1.5s turn overlay (`!inFirstTime`).

### J. Next question

Parent sets title, id, count `n/total`, replaces `answerModels`. Fragment does not parse `NextQuestion` itself. Chips re-bind on `isGameUpdated` / turn overlay.

### K. Disconnect / restore

Parent `GameRestore`: if not `ENDED`, `nextRound(type)` + `gameUpdate`. For type 1 you land on this screen with latest question, strikes, turn.

### L. Round / match end

`RoundFinished` → loading → Auction. `GameOver` / `GameFinished` → win/loss.

### M. Report

Email with `questionId`.

### N. App background

Strike, timeout, intro, turn overlays **skip** if `isAppBackground` (avoid dialogs off-screen).

### O. Tap while not clickable

Adapter ignores taps when `isClickable == false`. After submit it stays false until turn / `GameUpdated` rebinds.

---

## 7. Judge-mode extras

Judge drives the clock and scoring. Players may not tap.

| Action | Hub |
|--------|-----|
| Start countdown | `StartGameTimer(gameId)` |
| Mark a chip | `SubmitAnswer(gameId, answerId)` |
| Strike (wrong / force) | `SubmitAnswer(gameId, 0)` + strike SFX, stop timer |
| Pass for a player | `Pass(gameId)` if that player `passes > 0` |
| Next question | Chips disabled, turn cleared, wait for timer again |

On `ChangeTurn` in WDYK: turn overlay with next player name; `isCorrectAnswerEnabled = true`.

On `NextQuestion` in WDYK: disable correct-answer, lock chips, `removeTurnPlayer`, stop timer.

On `Penalty(type = 1)` in WDYK: strike overlay (not generic timeout). Type 2: wrong SFX + strike button handling.

On `CorrectAnswer`: right-answer SFX only (no playerId branch in judge).

---

## 8. T30 file map

| Area | Path |
|------|------|
| PvP screen | `ui/gamelobbyinterface/game/whatdoyouknow/WhatDoYouKnowFragment.kt` |
| PvP layout | `res/layout/fragment_what_do_you_know.xml` |
| Chip adapter | `.../whatdoyouknow/adapter/QuestionAdapter.kt` |
| Strike adapter | `.../whatdoyouknow/adapter/StrikeAdapter.kt` |
| Match shell | `ui/gamelobbyinterface/game/GameControllerFragment.kt` |
| Shared state | `ui/gamelobbyinterface/GameControllerViewModel.kt` |
| Judge | `ui/gamelobbyinterface/judgemode/fragment/JudgeModeGame.kt` |
| Graph start | `res/navigation/game_nav_graph.xml` → `whatDoYouKnowFragment` |
| Hub names | `utils/pref/PrefConstants.kt` |

Parent `nextRound(1)` navigates here if not already on it.

---

## 9. Implementation plan (other project)

### Phase 0 — Spec lock

- Confirm 3 strikes, Pass after 2, one pass token from server.
- Confirm timeout = strike for the answering player.
- Confirm opponent does not see chips (hidden vs disabled).

### Phase 1 — Domain

- Models: Question, Answer, Penalty, Player (penalty, passes, points).
- State: turn, chips, strikes[2][3], passUnlocked, passRemaining, timer.

### Phase 2 — Hub adapter

- Round screen: Penalty, CorrectAnswer, PlayerAnswered, PlayerPassed, TimeStarted.
- Shell: ChangeTurn, GameUpdated, NextQuestion, timers, round/game end, restore.
- Subscribe only while this round is visible.

### Phase 3 — Play UI

- Question + flex chips, click lock after submit.
- Strike dots synced from `penalty`.
- Pass: visible on my turn; enabled iff strikes ≥ 2 **and** `passes > 0`.

### Phase 4 — Overlays

- Intro, your turn / their turn, correct, strike, timeout, answer reveal, skip.

### Phase 5 — Parent match shell

- `NextRoundStarted(1)` → this screen (first round / default).
- Shuffle answers on update if you want the same anti-pattern as T30 (or shuffle on server only).

### Phase 6 — Judge (optional)

- `StartGameTimer`, strike as `SubmitAnswer(0)`, pass with `passes` check.

### Phase 7 — Test matrix

| # | Scenario | Expect |
|---|----------|--------|
| 1 | Match starts | Intro, then waiting or your turn |
| 2 | My turn | Chips visible, Pass visible |
| 3 | Opponent turn | Chips invisible, Pass gone |
| 4 | Correct tap | Overlay, reveal text, next Q or turn |
| 5 | Wrong tap | Strike 1, chips locked until next |
| 6 | Second wrong | Strike 2, Pass lights up if `passes > 0` |
| 7 | Third wrong | Strike 3 |
| 8 | Timeout (me) | Strike overlay |
| 9 | Timeout (them) | Timeout overlay |
| 10 | Pass with 2 strikes + token | Skip overlay, token consumed |
| 11 | Pass with 0 tokens | Error snackbar |
| 12 | Pass with 0–1 strikes | Button faded / ignored |
| 13 | Double tap chip | Second tap ignored |
| 14 | Restore mid-question | Same Q, strikes, turn |
| 15 | Round finished | Navigate to Auction |
| 16 | Judge start timer | Countdown + chips clickable |
| 17 | Judge strike (`answerId = 0`) | Penalty / strike UI |
| 18 | Background during strike | No crash; overlay skipped |

---

## 10. What not to copy blindly

- `NEXTQUESTION_` is subscribed in the fragment but **parsed in the parent**.
- Strike index uses `penalty - 1` in PvP and raw `penalty` in Judge — pick one.
- Pass needs **two** flags (`userPass` + `enablePass`); either alone is wrong.
- Timeout for **you** is a **strike** animation, not the red timeout (that is for watching the opponent time out).
- `GameUpdated` shuffles answers every time — can jump chips if you rebind mid-question.
- `inFirstTime` avoids binding chips during the intro; without it, chips can flash early.
- All-in-one is a different flow; do not reuse this fragment there.

---

## 11. Suggested reducer (porting)

```text
NextRoundStarted(1)     → show WDYK, intro
GameUpdated             → question, answers, points, strikes, enablePass
ChangeTurn(id)          → isMyTurn; show turn overlay; bind chips if mine
TimeStarted             → start timer; first time bind chips
TimerUpdatedSeconds     → restart countdown
SubmitAnswer            → lock chips (optimistic)
CorrectAnswer(me)       → correct overlay; reset timer
PlayerAnswered          → reveal text overlay
Penalty(2, me)          → strike overlay; lock chips
Penalty(1, me)          → strike overlay; lock chips
Penalty(1, other)       → timeout overlay
PlayerPassed            → skip overlay (me) or “Skip” reveal (other)
NextQuestion            → new title/answers; lock until next ChangeTurn
RoundFinished           → leave to Auction
GameRestore             → rebuild from CreatedGame.type + players
```

Pass click:

```text
if (!isMyTurn) ignore
if (passesRemaining == 0) error
if (myStrikes < 2) ignore   // T30 UX
else send Pass(gameId)
```

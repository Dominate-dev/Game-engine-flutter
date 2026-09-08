# Auction Round — Workflow, Scenarios & Porting Plan

Source: T30 Android (`AuctionRoundFragment`, `GameControllerFragment`, `JudgeModeGame`).

Auction is a **two-phase round**: bid how many answers you can get, then the winner must hit that number before time runs out.

There are **two client implementations**:

| Mode | Screen | Who bids |
|------|--------|----------|
| PvP / private 1v1 | `AuctionRoundFragment` | Each player bids for themselves |
| Judge | `JudgeModeGame` | Judge assigns a bid to a player |

**All-in-one does not implement Auction.**

---

## 1. Game rules

A question has many correct answers (`maxCorrectAnswersCount`). Players bid: *“I can get N of them in ~30 seconds.”*

1. **Bidding phase** — raise only. New bid must be **> current bid**, and **≤ max answers**.
2. **Pass / take turn** — only after **someone has already bid**. You refuse to raise. Last bid stands; that player answers.
3. **Answer phase** — winner selects answers. Goal = their bid (`currentScore / goalScore`). Wrong answers are tracked separately.
4. **Win** — `currentScore == goalScore` before timeout.
5. **Lose** — timeout, too many wrongs, or judge says they failed.

The **server owns truth** (timer, whose turn, scores). The client is UI + hub calls.

---

## 2. State machine

```
IDLE (round intro, ~2–3s Lottie)
  → BIDDING (phase = 1)
       → raise Bid
       → opponent Bid (currentBid updates; your turn to raise)
       → Pass (only if currentBid exists)
  → ANSWERING (phase = 2)
       → SubmitAnswer (correct / wrong)
       → score ticks
  → WON (hit goal) or LOST (timeout / fail)
  → next question (same round, bidding again) OR ROUND_FINISHED → next round
```

### Phases (`StatusAuctionPhaseEnum`)

| id | name |
|----|------|
| 1 | `BIDDING` |
| 2 | `QUESTION` (answer) |

UI flag `startAuctionRound`:

- `true` → bidding screen
- `false` → answer chips

---

## 3. Hub contract

### 3.1 Client → server

| Method | Payload | When |
|--------|---------|------|
| `Bid` | `{ gameId, bidValue }` | PvP: player raises |
| `Pass` | `gameId` | PvP: refuse to raise; last bidder answers |
| `SubmitAnswer` | `gameId`, `answerId` | PvP: tap an answer chip |
| `JudgeBid` | `{ gameId, playerId, bidValue }` | Judge assigns a bid to a player |
| `AuctionConfirmResult` | `gameId`, `bool` | Judge: player succeeded (`true`) / failed (`false`) |

### 3.2 Server → client

| Event | Payload | Meaning |
|-------|---------|---------|
| `NextRoundStarted` | `int` = **2** | Enter Auction |
| `AuctionBiddingPhaseStarted` | `string` playerId | New bidding round; reset bid UI |
| `PlayerBidded` | `{ playerId, bidValue }` | Current bid + whose bid it was |
| `ChangeTurn` | `string` playerId or empty | Whose turn; empty = nobody |
| `TimeStarted` / `TimerUpdatedSeconds` | seconds | Timer |
| `AuctionAnswerPhaseStarted` | `{ playerId, bidValue }` | Bidding over; this player answers |
| `GameUpdated` | full `CreatedGame` + `auctionGameMetadata` | Question, answers, timeout, phase |
| `NextQuestion` | question + answers | New question (often with bidding reset) |
| `CorrectAnswer` | — | Last tap was correct |
| `PlayerAnswered` | `{ answerText, answerTextEn, … }` | Show the answer to both |
| `AuctionAnswerPhaseScoreUpdate` | `{ playerId, currentScore, goalScore, wrongScore }` | Progress `3/7` |
| `Penalty` | `{ type, playerId }` | `1` timeout, `2` wrong |
| `PlayerLostAuctionRound` | `string` playerId | Failed the bid |
| `PlayerWonAuctionRound` | — | Judge: they hit the goal |
| `ShowAuctionConfirmationDialog` | — | Judge: confirm success (Win/Loss) |
| `RoundFinished` / `GameOver` / `GameFinished` | — | Leave round |
| `GameRestore` | `CreatedGame` | Reconnect mid-auction |

### 3.3 Metadata on `CreatedGame`

```text
auctionGameMetadata:
  currentBid
  currentScore
  latestBidder
  phase            // 1 = BIDDING, 2 = QUESTION
  answerTimeout

currentQuestion.maxCorrectAnswersCount  → picker max
```

### 3.4 Payload models (T30)

**Bid request (PvP)**

```kotlin
data class ArgumentBidRequest(
    val gameId: String,
    val bidValue: Int
)
```

**Judge bid request**

```kotlin
data class SendJudgeBidModelRequest(
    val gameId: String,
    val playerId: String,
    val bidValue: Short
)
```

**Player bidded**

```kotlin
data class PlayerBidded(
    val playerId: String,
    val bidValue: Int
)
```

**Answer phase started**

```kotlin
data class AuctionAnswerPhaseStarted(
    val playerId: String,
    val bidValue: Int
)
```

**Score update**

```kotlin
data class AuctionAnswerPhaseScoreUpdate(
    val playerId: String,
    val currentScore: Int,
    val goalScore: Int,
    val wrongScore: Int
)
```

**Auction metadata**

```kotlin
data class AuctionGameMetadataModel(
    val currentBid: Int,
    val currentScore: Int,
    val latestBidder: String? = null,
    val phase: Int,
    val answerTimeout: Int
)
```

---

## 4. Local UI state (PvP)

| Field | Role |
|-------|------|
| `startAuctionRound` | Bidding UI vs answers UI |
| `isBiding` | You may raise (set `false` immediately after **you** bid) |
| `isTurnPlaying` | `true` you / `false` opponent / `null` nobody |
| `biddingNumber` | Current bid; `null` = no bid yet → **Pass disabled** |
| `countAnswer` | Number picked in picker (not sent until Bid) |
| `answerTimeout` | “in X seconds” copy |
| `answerUser` / `answerPlayer` | `current/goal` |
| `userAnswerWrongPlayer` / `playerAnswerWrongPlayer` | Wrong count |
| `maxCorrectAnswersCount` | Picker max |
| Picker **min** | `currentBid + 1` (or `1` if no bid) |

### Control enablement (PvP)

| Control | Enabled when |
|---------|----------------|
| Bid | `isBiding && isTurnPlaying && countAnswer is not empty` |
| Pass / take turn | `biddingNumber != null && isTurnPlaying` |
| Answer chips | `!startAuctionRound && isTurnPlaying` |

`isBiding` and `isTurnPlaying` are **different**:

- `isBiding` — who last bid (local flip on `PlayerBidded`)
- `isTurnPlaying` — `ChangeTurn` from the match shell

---

## 5. Screens

1. **Round intro overlay** — auction art / Lottie, ~2s, SFX.
2. **Bidding screen** — current bid, timeout copy, number picker, Bid, Pass.
3. **Answering screen** — question, flex chips, `score/goal`, optional wrong count, attempt hint, report.
4. **Feedback overlays** — your turn / their turn, correct toast, wrong, timeout, “start increasing”.
5. **Judge only** — Win/Loss confirmation sheet (“Did the player finish successfully?”).

### Dialog timers (exact ms from T30)

`isTimer` / `timer` = auto-dismiss. Match countdown is **not** these overlays.

| Overlay | Helper | Duration |
|---------|--------|----------|
| Round intro | `showDialogGameStartPlayLottie` | **2000** |
| Then start looping music | `delay` | **3000** |
| “Start increasing” | `showDialogCircularLotti` | **2000** |
| Your turn / their turn | `showDialogCircularLotti` | **1500** |
| Extra wait in `isPlayerTurn` after overlay | `delay` | **4000** |
| Wrong | `showDialogCircularLotti` | **1500** |
| After wrong, chips clickable again | `Handler.postDelayed` | **1500** |
| Timeout / round finished | `showDialogCircularLotti` | **1500** |
| Answer reveal | `showDialogAnswer` | **1500** |
| Bid number picker | `CountAnswerFragment` | **no auto-dismiss** |
| Judge Win/Loss confirm | `showDialogAuctionAlert` | **no auto-dismiss** |

**Judge**

| Overlay | Duration |
|---------|----------|
| Round intro | **3000** |
| After intro, start music | `delay(4000)` |
| Start increasing | **2000** |
| Turn name | **1500** + `delay(1500)` |
| Timeout | **1500** |
| Win/Loss sheet | stays until Beat / Fail |

---

## 6. Workflow scenarios

### A. Happy path — PvP

1. Previous round ends → `NextRoundStarted(2)` → navigate to Auction.
2. Intro Lottie ~2s + SFX.
3. `clearDataRoundTwo()`: bid UI, `isBiding = true`, `biddingNumber = null`.
4. `AuctionBiddingPhaseStarted` + `ChangeTurn(you)`: pick N > 0, tap **Bid** → `Bid`.
5. `PlayerBidded`: show N; **you** `isBiding = false`; opponent can raise.
6. Opponent raises M > N → `PlayerBidded`; **you** `isBiding = true`.
7. You **Pass** (`Pass`) — you will not go higher.
8. `AuctionAnswerPhaseStarted(opponent, M)`: bidding UI hides; chips show.
9. Opponent taps answers → `SubmitAnswer` → `CorrectAnswer` / `PlayerAnswered` toast + `ScoreUpdate`.
10. `currentScore == goalScore` → chips clear; that question done.
11. Repeat bidding for next question, or `RoundFinished`.

### B. Raise war

Keep bidding until one Passes. Each bid must be **strictly higher**. Picker min = last bid + 1. Bid with empty picker → snackbar, **no hub call**.

### C. First bid of the question

`biddingNumber == null` → Pass disabled. Someone must Bid first.

### D. You win the auction (you answer)

`AuctionAnswerPhaseStarted(you, bid)`. “Your turn” overlay. Chips clickable. Score on **your** side (`answerUser`). Opponent watches; chips hidden when `isTurnPlaying == false`.

### E. Hit the goal

`ScoreUpdate` with `currentScore == goalScore` → stop timer, clear chips, wait for next question / round.

### F. Timeout while answering

`Penalty(type = 1)` and/or `PlayerLostAuctionRound` → red timeout overlay, chips locked.

If the displayed timer is **not** `00:00`, copy may be “round finished” instead of “time out”.

### G. Wrong answer while answering

`Penalty(type = 2)` for you. Wrong counter updates via `wrongScore`. Chip re-enables after feedback. Does **not** end the round unless the server also sends Lost.

### H. Correct tap, not yet at goal

`CorrectAnswer` + `PlayerAnswered` (show text) + `ScoreUpdate` (`3/7`). Keep tapping.

### I. Pass mid-bidding (PvP)

T30 is **optimistic**: hide bidding UI immediately, then send `Pass`. Server follows with `AuctionAnswerPhaseStarted` for the **last bidder**.

When porting, prefer waiting for `AuctionAnswerPhaseStarted` instead of hiding UI early.

### J. Disconnect / restore

On `GameRestore`:

| Condition | UI |
|-----------|----|
| Game `ENDED` (status 4) | Ignore / go to end |
| `type == AUCTION` and `phase == BIDDING` | Bidding UI, restore `currentBid`, `isBiding = true` |
| `phase == QUESTION` | Answer UI, load answers from `GameUpdated` |

Also listen to `GameUpdated` for `answerTimeout` and the answer list when answering has started.

### K. Timer (parent match shell)

- `TimerUpdatedSeconds` restarts local countdown.
- `TimeStarted` starts it.
- Auction screen **resets** timer on bid, phase change, and lost.

### L. Next question, same round

`NextQuestion` + often `AuctionBiddingPhaseStarted` again: reset bid, clear answers, new title. `maxCorrectAnswersCount` comes from the new question.

### M. Round / match end

- `RoundFinished` → loading overlay → next round (Bell, etc.).
- `GameOver` / `GameFinished` → win/loss + optional ads.

### N. Report bad question

Email with `questionId` (not gameplay).

### O. Validation errors

- Bid with no number → error snackbar.
- Hub invoke exception → snackbar.

### P. Intro vs “start increasing”

If bidding starts and **it is your turn and `isBiding`**, show “start increasing” overlay. Else show “X’s turn”.

---

## 7. Judge-mode extras

The judge does **not** bid for themselves. They pick N, then tap **player A** or **player B** → `JudgeBid(gameId, playerId, N)`.

| Scenario | Behavior |
|----------|----------|
| Start auction | Same intro; `auctionBiddingPhaseStarted = true` |
| Assign bid | Number picker + Take-turn-first / second |
| After `PlayerBidded` | Highlight that player’s turn |
| Answer phase | `auctionBiddingPhaseStarted = false`; judge marks correct via `JudgeSubmitAnswer` |
| Score | One progress string on judge UI |
| `ShowAuctionConfirmationDialog` | Modal: “Did they finish successfully?” Beat → `AuctionConfirmResult(true)`, Fail → `false`. **Not cancelable.** |
| `PlayerWonAuctionRound` | Clear answers, stop timer |
| `PlayerLostAuctionRound` | Timeout overlay |

PvP has **no** confirmation dialog. That is judge-only.

---

## 8. T30 file map

| Area | Path |
|------|------|
| PvP screen | `ui/gamelobbyinterface/game/auctionround/AuctionRoundFragment.kt` |
| Bid picker | `ui/gamelobbyinterface/game/auctionround/sheet/CountAnswerFragment.kt` |
| PvP layout | `res/layout/fragment_auction_round.xml` |
| Shared match shell | `ui/gamelobbyinterface/game/GameControllerFragment.kt` |
| Shared state | `ui/gamelobbyinterface/GameControllerViewModel.kt` (`clearDataRoundTwo()`) |
| Judge screen | `ui/gamelobbyinterface/judgemode/fragment/JudgeModeGame.kt` |
| Judge confirm UI | `res/layout/auction_alert_dialog_new.xml` |
| Hub names | `utils/pref/PrefConstants.kt` |
| Round id | `data/signalR/enums/GameTypeEnum.AUCTION` = `2` |

Round navigation: `game_nav_graph.xml` → `auctionRoundFragment`.

---

## 9. Implementation plan (other project)

### Phase 0 — Spec lock

- Confirm 1v1 only vs also-judge.
- Confirm server event names (same as above or map them).
- Confirm Pass = last bidder answers (this app’s behavior).

### Phase 1 — Domain

- Enums: `AuctionPhase { Bidding, Answering }`.
- Models: BidRequest, PlayerBidded, AnswerPhaseStarted, ScoreUpdate, AuctionMetadata.
- State holder: turn, currentBid, myBidAllowed, scores, answers, timer, phase.

### Phase 2 — Hub adapter

- Subscribe/unsubscribe **only while Auction is visible**.
- One reducer: event → state (no UI in the socket callback).
- Restore: if `phase == Bidding` restore bid UI; else restore chips.

### Phase 3 — Bidding UI

- Picker min/max.
- Bid disabled after **your** bid until opponent bids (`isBiding` flip).
- Pass disabled until `currentBid != null`.
- Empty bid → client validation.

### Phase 4 — Answer UI

- Show chips only for the answering player.
- Submit on tap; wait for server (don’t locally mark win).
- Bind `current/goal`; clear chips when equal.

### Phase 5 — Overlays + audio

- Intro, turn, timeout, wrong; optional SFX.

### Phase 6 — Parent match shell

- `NextRoundStarted(2)` → Auction screen.
- Shared: ChangeTurn, timer, GameUpdated, RoundFinished, GameOver, restore.

### Phase 7 — Judge (optional)

- `JudgeBid`, confirmation dialog, `AuctionConfirmResult`, `PlayerWonAuctionRound`.

### Phase 8 — Test matrix

| # | Scenario | Expect |
|---|----------|--------|
| 1 | First Bid | Pass still disabled until bid exists |
| 2 | Bid empty | No hub, error |
| 3 | Bid ≤ current | Server reject (client picker should prevent) |
| 4 | Bid then wait | Your Bid disabled; opponent can raise |
| 5 | Raise several times | Displayed number always latest |
| 6 | Pass after opponent bid | Answer phase for opponent |
| 7 | You answer, hit goal | Score `N/N`, chips clear |
| 8 | You answer, timeout | Lost overlay, chips locked |
| 9 | Wrong then correct | `wrongScore++`, then `currentScore++` |
| 10 | Kill app in bidding | Restore bidding + `currentBid` |
| 11 | Kill app in answering | Restore chips + scores |
| 12 | Next question | Bidding UI again, bid reset |
| 13 | Round finished | Exit Auction |
| 14 | Judge confirm win/loss | Result event, next question |
| 15 | Hub drop mid-bid | Reconnect + restore, no duplicate bid UI |

---

## 10. What not to copy blindly

- Optimistic `startAuctionRound = false` on Pass (can flash answer UI before the server agrees). Prefer waiting for `AuctionAnswerPhaseStarted`.
- Mixing `isBiding` (who last bid) with `isTurnPlaying` (`ChangeTurn`) — keep both, document them.
- Auction is **not** in All-in-one.
- In T30, `NEXTQUESTION_` is subscribed in PvP Auction but handled on the **parent** `GameControllerFragment`.
- Wrong-count badges exist in the PvP layout but are currently `visibility="gone"`.

---

## 11. Suggested reducer (porting)

Keep one auction state object and apply events in order:

```text
AuctionBiddingPhaseStarted → phase=Bidding, reset bid, clear answers
PlayerBidded               → currentBid=bidValue
                             if me: canRaise=false else canRaise=true
ChangeTurn                 → isMyTurn
AuctionAnswerPhaseStarted  → phase=Answering, answeringPlayerId, goal=bidValue
ScoreUpdate                → current/goal/wrong; if current==goal → lock chips
Penalty(1) / Lost          → timeout UI, lock chips
CorrectAnswer / PlayerAnswered → feedback overlays
GameRestore                → rebuild from metadata.phase
```

Do not submit a second Bid until `PlayerBidded` (or `ChangeTurn`) confirms the previous one, unless you keep T30’s local `isBiding` flip.

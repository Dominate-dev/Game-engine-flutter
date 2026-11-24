# Judge mode (GameMode 3): behaviour spec for the Flutter client

Derived on 2026-11-25 from the server (TH30.Backend, branch `game-stability`) and the native
iOS judge screens (Th30_IOS_V2, `Modules/JudgeMode/Round 1-4`). The server is authoritative;
the native screens show how it looks today and where they work around server quirks.

Abbreviations: S = `GameEngineService_Normal.cs`, G = `Game.cs`, H = `Hubs/GameHub.cs`,
I = `Hubs/IGameHub.cs`. R1-R4 = the native `JudgeRoundNVC.swift`.

Enums: GameStatus 1 WaitingPlayers, 2 IsReady, 3 InProgress, 9 Ended.
GameType WDYK=1, AUCTION=2, BELL=3, MAKEUP=4, BREAKER=5, IMPOSSIBLE=6.

## Who is who
One device: the judge. Two players sit in front of the judge and answer out loud; the judge
records what happens. The judge is never a player. The server creates two virtual players with
ids `"{judgeUserId}1"` and `"{judgeUserId}2"`. Every event goes only to the judge (S GetGameUsersGroup).

## Setup
1. Leave any old game, then hub `CreateGame(3)`. Reply: `GameCreated(GameModel, gameId)`
   (status 1, no players, `showInterests`).
2. Name screen: two names, required, max 12 chars, different. One interest when
   `showInterests` is true.
3. Hub `StartJudgeGame(gameId, player1Name, player2Name, List<long> interests)`.
   Server marks both players ready, loads round 1, sets CurrentTurn to a random player
   (since `d3e8c65`; before that always player 1), and emits only `GameStarted(GameModel)` with the
   current question and `isTimerStarted=false`. No questions: `GameFinished(true)`.
4. Question payloads carry ONLY the correct answers (no isCorrect field),
   `maxCorrectAnswersCount = 100`.

## Answer ids sent with `JudgeSubmitAnswer(gameId, answerId, playerId)`
- an id from the list: correct (it is removed from the list);
- `0`: wrong;
- `-99`: correct, "a right answer that is not in the list" (counts as correct and bumps the
  question's missing-answer counter).
In WDYK, Auction, Bell and Impossible the server uses CurrentTurn and ignores playerId.
In Makeup and Breaker it takes playerId as the scorer.

The judge's turn timer is always 31s (`JudgeGameTimer + 1`), and timeouts do fire.

## Rounds
Order: WDYK, Auction, Bell, (Impossible only if enabled), Makeup, Breaker (only if tied).
Each round ends with `GameUpdated`, `RoundFinished`, `NextRoundStarted(type)`.

### WDYK (1)
- Judge sees the question and the correct answers; hide ones already given.
- "Start timer" -> `StartGameTimer(gameId)`. Server: `ChangeTurn(CurrentTurn)`, short pause,
  `TimerUpdatedSeconds`. Answers sent before the timer starts are ignored.
- Judge taps: an answer (that id), "right answer not listed" (-99), "wrong" (0),
  "pass" (`Pass(gameId)`, allowed once per player, needs 2 strikes).
- Wrong: `Penalty(playerId, 2)`; the third strike gives the opponent a point.
  Correct: `CorrectAnswer(text, textEn, playerId)`.
- Not over: turn alternates after every answer: `GameUpdated`, `ChangeTurn`,
  `TimerUpdatedSeconds`. Question over: `NextQuestion` + `GameUpdated`, no timer: the judge
  presses start again.
- Timeout: `Penalty(playerId, 1)`, play moves on.

### Auction (2)
- Per question: `GameUpdated`, `NextQuestion` (correct answers), `AuctionBiddingPhaseStarted`.
  No bidding timer for the judge.
- Judge picks a number and the player: `JudgeBid({gameId, playerId, bidValue})`.
  Accepted only if 0 <= bid <= 100, in the bidding phase and higher than the current bid.
  Exactly one bid per question: the answer phase starts at once (a bid >= the number of
  correct answers is capped and sends no `PlayerBidded`). A bid of 0 is dropped silently, so
  the client must not send it.
- Answer phase: `AuctionAnswerPhaseStarted{playerId,bidValue}`,
  `AuctionAnswerPhaseScoreUpdate{playerId,currentScore,goalScore,wrongScore}`,
  `ChangeTurn(bidder)`, `TimeStarted`, `TimerUpdatedSeconds`: one timer for the whole phase.
- Answers: id or -99 = score + 1; 0 = wrong (`Penalty(.., 2)`). Each emits `ScoreUpdate` and
  `GameUpdated`.
- Goal reached, too many wrong, or timeout: `ShowAuctionConfirmationDialog(gameId)`.
  Judge answers `AuctionConfirmResult(gameId, isWinner)`:
  won = bidder gets 1 (bid < 20), 2 (20-29) or 3 (>= 30) points and `PlayerWonAuctionRound`;
  lost = opponent +1, no event. Then the next question.

### Bell (3) and Impossible (6)
- Per question: `NextQuestion` with the full text. No ring timer for the judge.
- Judge taps the player who rang: `JudgeRingBell(gameId, playerId)` (only while nobody holds
  the turn). Server: `ChangeTurn(playerId)`, pause, `TimeStarted`, `TimerUpdatedSeconds`.
- Then: an answer id or -99 (Bell +1, Impossible +2) or 0 for wrong.
  Wrong or timeout: the other player automatically gets the turn. Both wrong or one correct:
  next question.

### Makeup (4) and Breaker (5)
- CurrentTurn = "ALLOW_ALL"; `GameUpdated`, `NextQuestion`, no timer until the judge presses
  "start timer" (`StartGameTimer`).
- "Point to player X": `JudgeSubmitAnswer(gameId, <a listed answer id>, playerX)`.
  Never send 0 here (it counts as wrong and the question sits until timeout); if the list is
  empty send -99.
- Makeup: next question; at the end, tied -> Breaker, else game over.
  Breaker: a point ends the game. Timeout: `Penalty("", 1)`, next question / game end.

## End
`GameOver(GameResultModel)`: winnerId, winningPoints, gameResultPlayers[{playerId, points,
strikes, correctAnswersCount}]. Names are not in it: take them from GameModel.players.
A tie still names a winner. Show the result without rewards. `LeaveGame(gameId)` ends the
game for real (a GameOver arrives; ignore it while leaving).

## Reconnect
`CheckPlayerGame()`: live game -> `GameRestore(GameModel)` (+ `ChangeTurn` if set, which can
be "ALLOW_ALL", + `TimerUpdatedSeconds` if running). Ended game -> `GameOver` then
`GameFinished(true)`. Rebuild per round:
WDYK: timer started ? answer window : start button.
Auction: by `auctionGameMetadata.phase` (1 bidding, 2 answering, 3 re-show the confirmation).
Bell: currentTurn set ? answer window : ring window.
Makeup/Breaker: timer started ? scoring window : start button.

## Server quirks the native screens work around
- `GameUpdated.currentTurn` can be stale in Auction; trust `ChangeTurn` for the turn.
- A confirmation that arrives early must still be shown.
- The Bell ring window opens on `NextQuestion` (there is no `ChangeTurn("")`).
- Ignore answer ids that are no longer in the list.

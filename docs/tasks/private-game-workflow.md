# Private Game (PvP) — How It Works

Source: T30 Android (`CreateGameGroupFragment`, `InterestGameFragment`, `JoinGameDialog`, `PvpGameLobbyFragment`, `GameTypeControllerFragment`).

**Private game** = **player vs player** with a **shareable code**. Two people, same SignalR GameHub as Judge/WDYK — **not** All-in-one, **not** Judge.

| | Value |
|--|--------|
| Mode id | `GameInterestModeEnum.PRIVATE_PVP` = **4** |
| Create router | `GameTypeControllerFragment.PVP_GAME_PLAY_ID` = **222** |
| Join router | `GameTypeControllerFragment.JOIN_PRIVATE_ID` = **333** |
| Feature flag | `create_game_option_pvp_enabled` |
| Hub | Main `connectionSignalR` (same as WDYK/Auction/Bell) |

All-in-one is a **different** lobby + hub. Join first calls REST `checkGame(code)`: `true` → All-in-one, `false` → this private PvP path.

---

## 1. High-level flow

```
CREATE
  Home → Create game → pick “Player vs player”
    → GameTypeController(222)
    → InterestGameFragment (pick categories/interests)
    → CreatePrivateGame(interestIds)
    → GameCreated { id, gameCode, players, mode=4 }
    → PvpGameLobbyFragment (isHost = true, default)

JOIN
  Home / deep link / notification → JoinGameDialog (OTP code)
    → REST checkGame(code)
    → if not All-in-one: JoinPrivateGame(code)
    → GameJoined { … mode=4 }
    → GameTypeController(333)
    → PvpGameLobbyFragment (isHost = false)

LOBBY
  Host shares code / link
  Both tap Ready → ReadyForGame(gameId)
  waiting-to-be-ready timer (server)
  GameStarted → GameControllerFragment
    → rounds 1–6 (WDYK → Auction → Bell → Comeback → Breaker → Impossible)
```

---

## 2. Create path (host)

1. Create-game sheet shows PvP only if `create_game_option_pvp_enabled`.
2. Selecting PvP does **not** call `CreateGame` (that is Judge). It navigates with `typeGame = 222`.
3. `InterestGameFragment`: user opens categories, selects interests. Confirm:
   - none selected → “choose interest first”
   - sum of `diamondsValue` on selected interests > 0 → diamond check / buy / pay dialog
   - else → `createGamePrivate()`
4. Hub:

```text
CreatePrivateGame( List<interestId> )
```

5. `GameCreated` (`CreatedGame`):
   - store `gameId`, `gameCode`
   - fill **your** `userId` / name / image from `players`
   - navigate `PvpGameLobbyFragment()` with **default `isHost = true`**

Friends “create private” also routes `typeGame = PVP_GAME_PLAY_ID` into the same interest → lobby path.

---

## 3. Join path (guest)

1. `JoinGameDialog`: OTP. May be prefilled (`args.code`) from home, deep link, or notification.
2. Join button:
   - `checkGameCode(otp.toInt())` (REST via `homeRepo.checkGame`)
   - **`true`** → All-in-one join API (not this doc)
   - **`false` / not All-in-one** → `JoinPrivateGame(code as String)`
3. Server events:
   - `WrongGameCode` → snackbar “game does not exist”, clear OTP
   - `GameJoined` (`CreatedGame`):
     - fill you vs opponent from `players`
     - `gameId`, `gameCode`
     - ready-timer fields (`waitingToBeReadyTimerStart` / `Value`)
     - optional `beforeMatchAdv`
     - if `mode == 4` → navigate `JOIN_PRIVATE_ID` (333) → lobby **`isHost = false`**, dismiss dialog

---

## 4. Lobby (`PvpGameLobbyFragment`)

UI: you vs opponent, **code digits** (T30 reverses characters in the recycler), share, Ready, banners, back.

| Arg | Host | Guest |
|-----|------|-------|
| `isHost` | `true` (nav default) | `false` (join router) |

Ready copy can differ by `isHost` (layout has a commented start vs ready string). **Both** still send the same hub method.

### Host share

`generateURL(type = 2, code = gameCode)` → share text + deep link.

### Ready

```text
ReadyForGame( gameId )
```

- `PlayerReady(playerId)`:
  - if **you** → `isReady = true`
  - if **them** and you are not ready → pulse the Ready button
- `GameUpdated`: opponent profile, `gameCode`, ready countdown:
  - `waitingToBeReadyTimerStart == true` → local ready timer from `waitingToBeReadyTimerValue`
  - else stop timer
  - flags `isUserReadyTimerView` / `isPlayerReadyTimerView` from each player’s `isReady`

### Start match

`GameStarted` (`CreatedGame`):

- stop ready timer
- load first question (localized title, shuffled answers, pass token, `n/total`)
- navigate **`GameControllerFragment`** (nested round graph, starts at What Do You Know)

Optional **before-match ad** on lobby open (`beforeMatchAdv`, type 1 image / else video). After match, lobby can still receive `GameOver` and show **after-match ad**.

### Leave / disconnect

- Back / exit → `LeaveGame("all")` → pop to home
- `PlayerLeft(id)`:
  - clear opponent
  - reset `isReady`
  - if **you** left → pop lobby
- `GameFinished` → “creator terminated the game” (not cancelable) → exit
- `GameRestore` if `status == IN_PROGRESS` → `gameStarted` + go to controller (nav id in code still mentions start-lobby; live path is PvP lobby)

---

## 5. Hub contract (lobby only)

### Client → server

| Method | Payload | When |
|--------|---------|------|
| `CreatePrivateGame` | `List<Int>` interest ids | Host confirms interests |
| `JoinPrivateGame` | `String` game code | Guest after REST says not All-in-one |
| `ReadyForGame` | `gameId` | Tap Ready |
| `LeaveGame` | `"all"` | Exit lobby |
| `generateURL` REST | `type = 2`, `code` | Share link |

### Server → client

| Event | Payload | Meaning |
|-------|---------|---------|
| `GameCreated` | `CreatedGame` | Host lobby |
| `GameJoined` | `CreatedGame` | Guest accepted; check `mode == 4` |
| `WrongGameCode` | — | Bad / expired code |
| `Error` | `{ message }` | Create/interest errors |
| `GameUpdated` | `CreatedGame` | Opponent joined, ready timer |
| `PlayerReady` | `string` playerId | Someone tapped Ready |
| `GameStarted` | `CreatedGame` + first question | Enter match |
| `PlayerLeft` | `string` playerId | Someone left lobby |
| `GameFinished` | — | Host killed the game |
| `GameRestore` | `CreatedGame` | Rejoin if already `IN_PROGRESS` |
| `ChangeTurn` / `GameOver` | — | Also subscribed on lobby (match / ads) |

### `CreatedGame` fields used here

```text
id, mode, status, isPrivate
gameCode
players[]          // id, name, image, isReady, passes, …
waitingToBeReadyTimerStart
waitingToBeReadyTimerValue
currentQuestion    // on GameStarted
beforeMatchAdv
```

`StatusGameEnum`: waiting players `1`, ready `2`, in progress `3`, ended `4`.

---

## 6. After the lobby (match)

Same **GameController** + round docs:

1. What Do You Know  
2. Auction  
3. Bell  
4. Comeback  
5. Breaker  
6. Impossible (if sent)

Private PvP does **not** use JudgeBid / JudgeRingBell / AuctionConfirmResult. Those are Judge mode (`mode = 3`).

---

## 7. Scenarios

| # | Scenario | Expect |
|---|----------|--------|
| 1 | Flag off | PvP missing from create sheet |
| 2 | Create, no interests | Block confirm |
| 3 | Create, paid interests, not enough diamonds | Buy diamonds |
| 4 | Create OK | Lobby + code, you are host, opponent empty |
| 5 | Share | Message with code + generated URL |
| 6 | Guest wrong code | `WrongGameCode`, OTP cleared |
| 7 | Guest All-in-one code | REST `true` → All-in-one, not this lobby |
| 8 | Guest private code | `GameJoined` mode 4 → lobby `isHost=false`, opponent = host |
| 9 | Guest arrives | Host `GameUpdated` fills opponent |
| 10 | One Ready | `PlayerReady`; other button pulses |
| 11 | Both Ready + timer | `GameStarted` → WDYK |
| 12 | Host leaves | Guest `GameFinished` / `PlayerLeft` |
| 13 | Guest leaves | Host opponent cleared, `isReady` reset |
| 14 | Deep link / notification with code | Join dialog prefilled |
| 15 | Restore in progress | Skip lobby into `GameController` |
| 16 | Before-match ad | Shown once on lobby, then cleared |

---

## 8. T30 file map

| Area | Path |
|------|------|
| Create picker | `ui/creategame/CreateGameGroupFragment.kt` (`P_V_P_ID = 4`) |
| Router | `ui/gamelobbyinterface/GameTypeControllerFragment.kt` |
| Interests + create hub | `ui/gamelobbyinterface/interestGame/InterestGameFragment.kt` |
| Join OTP | `ui/joingame/JoinGameDialog.kt` |
| Lobby | `ui/gamelobbyinterface/pvpGame/PvpGameLobbyFragment.kt` |
| Layout | `res/layout/fragment_pvp_gamelobby.xml` |
| Nav `isHost` | `onboarding_nav_graph.xml` default `true` |
| Match | `ui/gamelobbyinterface/game/GameControllerFragment.kt` |
| Hub names | `CREATE_PRIVATE_GAME_`, `JOIN_PRIVATE_GAME`, `READY_FOR_GAME`, … |

---

## 9. Porting plan

1. Mode `4` + create/join hub methods above.
2. Create: interests (optional diamonds) → `CreatePrivateGame` → lobby + code.
3. Join: resolve code type (PvP vs All-in-one) → `JoinPrivateGame` → same lobby, `isHost=false`.
4. Lobby: code, share link (`type=2`), Ready, ready timer, `GameStarted` → round shell.
5. Leave with `LeaveGame("all")`; handle `PlayerLeft` / `GameFinished`.
6. Do not mix Judge (`CreateGame(3)`) or All-in-one hub into this path.

### Suggested reducer

```text
CreatePrivateGame(ids)     → wait GameCreated → host lobby, store gameId+code
JoinPrivateGame(code)      → WrongGameCode | GameJoined(mode=4) → guest lobby
GameUpdated                → opponent, ready timer
ReadyForGame(gameId)       → PlayerReady
GameStarted                → load Q1 → GameController / WDYK
PlayerLeft / GameFinished  → clear or exit
GameRestore(IN_PROGRESS)   → skip to match
```

---

## 10. What not to copy blindly

- Join always hits `checkGameCode` first; skipping it sends private join into an All-in-one room (or the reverse).
- Host lobby navigation does not pass `isHost`; it relies on **nav default `true`**. Guest **must** `setIsHost(false)`.
- Code recycler **reverses** characters for RTL display.
- `LeaveGame("all")` leaves every game on the hub, not only this room.
- `CreateGame` without “Private” is **Judge**, not PvP.
- Ready timer lives on **GameUpdated**, not on `PlayerReady`.

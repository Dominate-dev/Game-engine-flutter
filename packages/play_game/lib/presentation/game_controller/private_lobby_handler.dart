part of 'game_controller.dart';

/// Private (invite-code) game handlers.
///
/// Creating a private game and joining one by its code. The two share the
/// session reset in [enterPrivateLobby] and nothing else — they are separate
/// hub methods with separate guards, so neither can suppress the other. The
/// invite URL is a separate flow and nothing here anticipates it.
extension PrivateLobbyHandler on GameController {
  /// Starts a fresh private session and shows its lobby.
  ///
  /// Called from [GameControllerScreen] as the private entry begins, before
  /// any server round-trip. The phase must be in place early: the default is
  /// [GamePhase.waiting], and [WaitingScreen] dispatches `JoinRandomGame` on
  /// its own first frame — the public flow, which must never run here.
  ///
  /// The session is **replaced**, not amended. Whatever a previous game left
  /// behind — a seated `me`/`opponent` with their names and profile images, a
  /// `game`, a result — is this session's state, and the private lobby reads
  /// it directly. Carrying it over rendered the *previous* game's players in
  /// the new lobby until `GameCreated` happened to overwrite them. A brand
  /// new private game starts from nothing, so the lobby shows nothing until
  /// its own `CreatedGame` arrives.
  ///
  /// Both dispatch guards are reset for the same reason: re-entering the
  /// private lobby on a controller that already created or joined one must
  /// still be able to create or join this one.
  void enterPrivateLobby() {
    _didCreatePrivateGame = false;
    _didJoinPrivateGame = false;
    // The public entry's guard, for the mirror of the reason
    // [WaitingScreenHandler.enterWaiting] releases the two above: this is a
    // whole new session, and a controller that outlives its route would
    // otherwise carry the previous public game's claim into it.
    _didJoinRandom = false;
    // Any create the previous entry still owed ends here too — a fresh entry
    // will record its own ids.
    _pendingPrivateInterestIds = null;
    // The previous session's leave must not suppress this one's dispatches.
    // `_leftGame` is otherwise never cleared because a controller is normally
    // per-entry, but a host that keeps one cached FlutterEngine across entries
    // arrives here on the same controller — and a stale `true` silences
    // createPrivateGame/joinPrivateGame below. Cleared at this single point,
    // where a genuinely new session begins, and nowhere else.
    _leftGame = false;
    _s = const GameSessionState(phase: GamePhase.lobbyPrivate);
  }

  /// Whether this device created the private game it is sitting in, rather
  /// than joining one by code.
  ///
  /// **There is no creator id to compare against.** `CreatedGame` carries no
  /// `creatorId`/`ownerId`, `GamePlayer` carries no `isHost`, and `isHost`
  /// itself is still an open item (docs/TASKS.md, PRIV-JOIN). The native
  /// reference does not read one either: it derives host-ness from the route
  /// that opened the lobby — the create router's nav default `isHost = true`,
  /// the join router's explicit `setIsHost(false)`
  /// (docs/tasks/private-game-workflow.md §4).
  ///
  /// This is that same signal, taken from the entry dispatch that actually
  /// happened rather than from a payload field that does not exist. In a
  /// two-seat lobby it answers the question the roster cannot: a `PlayerLeft`
  /// naming someone other than me is the creator when I joined, and the guest
  /// when I created.
  bool get isPrivateGameCreator => _didCreatePrivateGame;

  /// Invokes `CreatePrivateGame(interestIds)` once per screen entry, and only
  /// on a hub that is actually connected.
  ///
  /// The server answers with `GameCreated` carrying the [CreatedGame]; that
  /// arrives through the existing session-event pipeline and is routed by
  /// status like any other game payload, so nothing is applied here.
  ///
  /// Guarded exactly the way [WaitingScreenHandler.onWaitingShown] guards
  /// `JoinRandomGame`, and deferred the same way for the same reason:
  ///
  /// * The connection check is a **gate, not a starter**. This does not call
  ///   `connect()` or `recoverConnection()` — [GameControllerScreen] owns
  ///   that operation (`_ensureHubConnected`), and a second starter here is
  ///   how two connects came to run at once. When its connect lands,
  ///   `recoveredStream` fires `onRecovered`, which re-enters this method
  ///   with the guard still open.
  /// * `isConnected`, not `hasLiveConnection`: the latter is also true
  ///   mid-connect, and a create must not ride a connect still in flight.
  ///   Dispatching anyway was survivable — `invoke` returns false and the
  ///   guard reopens — but the call left as a no-op and the create was
  ///   silently lost, leaving the private lobby in front of a game the
  ///   server had never been asked to make.
  /// * The flag is claimed before the await so two callers in one tick
  ///   cannot both dispatch, and a dispatch that never left the device
  ///   reopens it for a retry.
  Future<bool> createPrivateGame(List<int> interestIds) async {
    if (_didCreatePrivateGame || _s.result != null || _leftGame) {
      return false;
    }
    // Recorded before the gate below, not after it: a deferred create is
    // still owed, and this is what onRecovered re-issues it from.
    _pendingPrivateInterestIds = List<int>.unmodifiable(interestIds);
    if (!ref.read(signalRServiceProvider).isConnected) {
      AppLogger.log(
        'GameController — ${PlayGameHubEvents.createPrivateGame} deferred, '
        'hub not connected; waiting for the entry connect to land',
      );
      return false;
    }
    _didCreatePrivateGame = true;
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.createPrivateGame} | '
      'interestIds: $interestIds',
    );
    final sent = await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.createPrivateGame,
          // One hub parameter, which is itself the list.
          args: [interestIds],
        );
    if (!sent) {
      _didCreatePrivateGame = false;
    }
    return sent;
  }

  /// Invokes `JoinPrivateGame(code)` once per screen entry.
  ///
  /// The server answers with either `GameJoined` — a `CreatedGame` carrying
  /// `mode` 4, which the existing session-event pipeline already routes to
  /// [GamePhase.lobbyPrivate] like any other private payload — or
  /// `WrongGameCode`. Neither is applied here.
  ///
  /// Guarded exactly the way [createPrivateGame] is: the flag is claimed
  /// before the await so two callers in one tick cannot both dispatch, and a
  /// dispatch that never left the device reopens it for a retry.
  ///
  /// A blank code is not a request. There is nothing for the server to look
  /// up, so it is refused here rather than sent and rejected remotely — and
  /// the guard stays open, since no attempt was made.
  Future<bool> joinPrivateGame(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || _didJoinPrivateGame || _s.result != null || _leftGame) {
      return false;
    }
    _didJoinPrivateGame = true;
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.joinPrivateGame} | '
      'code: $trimmed',
    );
    final sent = await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.joinPrivateGame,
          // One hub parameter: the code itself, as a String.
          args: [trimmed],
        );
    if (!sent) {
      _didJoinPrivateGame = false;
    }
    return sent;
  }
}

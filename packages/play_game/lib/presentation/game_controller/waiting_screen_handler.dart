part of 'game_controller.dart';

extension WaitingScreenHandler on GameController {
  /// Starts a fresh public session and shows its waiting screen.
  ///
  /// The mirror of [PrivateLobbyHandler.enterPrivateLobby], called from the
  /// same point in [GameControllerScreen]'s entry and for the same reason: a
  /// controller is normally per-entry (autoDispose), but a host that keeps
  /// one cached FlutterEngine across entries arrives here on the controller
  /// the previous game left behind. Its phase would route the entry to that
  /// game's screen instead of [WaitingScreen], and its `_leftGame` would
  /// silence the join this entry exists to make.
  ///
  /// The session is replaced rather than amended, exactly as the private
  /// entry replaces it: a new public game starts from nothing.
  void enterWaiting() {
    // A new session may join for itself. Reset here and nowhere else — within
    // a session the guard stays claimed, so one join per session still holds.
    _didJoinRandom = false;
    // The private entry's own guards, released for the same reason
    // [PrivateLobbyHandler.enterPrivateLobby] releases this one's: an entry
    // establishes a whole session, so it may not leave the other kind's
    // claims standing on a controller that outlives the route. Nothing reads
    // them during a public game today, which is why this was only ever
    // latent, but a stale `_didCreatePrivateGame` still reports a public
    // session as created-by-me through `isPrivateGameCreator`.
    _didCreatePrivateGame = false;
    _didJoinPrivateGame = false;
    _pendingPrivateInterestIds = null;
    _leftGame = false;
    _s = GameSessionState.initial();
  }

  Future<void> onWaitingShown() async {
    // R-07: endGame deliberately leaves `phase` untouched, so an abrupt
    // GameOver/GameTerminated that lands while still `waiting` (the client
    // missed the events that would normally have moved it past waiting)
    // sets `result` without ever leaving GamePhase.waiting. Both call sites
    // of this method (WaitingScreen's own mount, and onRecovered's retry)
    // key off `state.phase == waiting` alone — without this check, either
    // one could still dispatch a fresh JoinRandomGame behind an
    // already-showing result dialog for a game that is already over.
    // _leftGame: the dying screen must not queue the player into a new game
    // on its way out. See GameController._leftGame.
    if (_didJoinRandom || _s.result != null || _leftGame) {
      return;
    }
    // The join may only ride a hub that is *confirmed* connected.
    //
    // Dispatching while the hub is down was tolerated because `invoke`
    // returns false and the guard reopens — but the call still left as a
    // no-op and the join was silently lost, leaving Waiting in front of a
    // game it had never joined.
    //
    // This deliberately does **not** start a connection. Establishing one is
    // GameControllerScreen's job (`_ensureHubConnected`, from its own entry
    // post-frame), and it is the single owner of that operation — a second
    // starter here is exactly how two connects came to run at once. When its
    // connect lands, `recoveredStream` fires `onRecovered`, which runs
    // CheckPlayerGame and then re-enters this method with the guard still
    // open. `isConnected` rather than `hasLiveConnection`: the latter is also
    // true mid-connect, and a connect in flight must not carry a join.
    if (!ref.read(signalRServiceProvider).isConnected) {
      AppLogger.log(
        'GameController — ${PlayGameHubEvents.joinRandomGame} deferred, '
        'hub not connected; waiting for the entry connect to land',
      );
      return;
    }
    // N4: claimed synchronously, before the await below — this screen's own
    // mount and onRecovered's retry can both reach this check in the same
    // tick, and awaiting first left both able to pass it and double-dispatch.
    _didJoinRandom = true;
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.joinRandomGame}',
    );
    final sent = await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.joinRandomGame,
        );
    // A skipped dispatch reopens the guard so it can be retried.
    if (!sent) {
      _didJoinRandom = false;
    }
  }

  // Routes by status like onWaitingGameRestore; falls back to Lobby
  // (this event's own pre-existing default) when status is unresolved.
  void onWaitingGameUpdated(Map<String, dynamic>? data) {
    final game = _gameFromData(data);
    if (_routeByStatus(
      game: game,
      data: data,
      eventName: PlayGameHubEvents.gameUpdated,
    )) {
      return;
    }
    _refreshLobby(
      data: data,
      game: game,
      eventName: PlayGameHubEvents.gameUpdated,
    );
  }

  // [WaitingScreen] — GameRestore: route by status, then type for in-progress.
  void onWaitingGameRestore(Map<String, dynamic>? data) {
    final game = _gameFromData(data);
    if (_routeByStatus(
      game: game,
      data: data,
      eventName: PlayGameHubEvents.gameRestore,
    )) {
      return;
    }
    // The private lobby shares this handler: LobbyPrivateGameScreen routes
    // its GameRestore to onLobbyGameRestore, which delegates straight here.
    // The fallback below names GamePhase.waiting outright, so an
    // unresolvable restore (no usable status — see R-05) evicted a private
    // session to WaitingScreen, whose own mount dispatches JoinRandomGame:
    // the public matchmaking flow, inside a game that already has its own
    // code and roster. A restore that *can* be resolved never reaches this
    // line — _routeByStatus above handles it, and it already sends a private
    // waiting-for-players game to GamePhase.lobbyPrivate. So the only
    // question left here is which lobby the session is already in, and a
    // private one stays where it is. The public fallback is unchanged.
    if (_s.phase == GamePhase.lobbyPrivate) {
      showPhase(
        GamePhase.lobbyPrivate,
        data: data,
        game: game,
        eventName: PlayGameHubEvents.gameRestore,
      );
      return;
    }
    showPhase(
      GamePhase.waiting,
      data: data,
      game: game,
      eventName: PlayGameHubEvents.gameRestore,
    );
  }
}

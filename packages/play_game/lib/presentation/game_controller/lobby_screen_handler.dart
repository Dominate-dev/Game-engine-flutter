part of 'game_controller.dart';

/// Lobby screen SignalR handlers.
/// Called when [LobbyPlayGameScreen] receives hub events.
extension LobbyScreenHandler on GameController {
  /// Invoke ReadyForGame hub method.
  Future<void> readyForGame() async {
    final gameId = _s.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.readyForGame} | '
      'gameId: $gameId',
    );
    await ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.readyForGame,
          args: [gameId],
        );
  }

  /// [LobbyPlayGameScreen] — replace game state and refresh lobby UI.
  void onLobbyGameUpdated(Map<String, dynamic>? data) {
    final game = _gameFromData(data);
    final status = StatusGame.fromId(game?.status);
    if (status == StatusGame.inProgress) {
      _goToRound(
        data: data,
        game: game,
        stopReadyTimer: true,
        eventName: PlayGameHubEvents.gameUpdated,
      );
      return;
    }
    if (status == StatusGame.ended) {
      endGame(
        result: GameResult.ended,
        data: data,
        game: game,
        eventName: PlayGameHubEvents.gameUpdated,
      );
      return;
    }
    _refreshLobby(
      data: data,
      game: game,
      eventName: PlayGameHubEvents.gameUpdated,
      stopReadyTimer: GameSessionReducer.shouldStopReadyTimer(data, game),
      clearReadyTimerPlayerId: true,
      opponentCardPulse: _opponentCardPulseAfter(game),
      opponentReadyPulse: _readyButtonPulseAfter(game),
    );
  }

  /// Restore uses the same payload apply as updates, then status + type.
  void onLobbyGameRestore(Map<String, dynamic>? data) {
    onWaitingGameRestore(data);
  }

  void onLobbyGameStarted(Map<String, dynamic>? data) {
    final game = _gameFromData(data);
    _goToRound(
      data: data,
      game: game,
      stopReadyTimer: true,
      eventName: PlayGameHubEvents.gameStarted,
    );
  }

  void onLobbyPlayerReady(Map<String, dynamic>? data) {
    final parsed = _gameFromData(data);
    final game = GameSessionReducer.gameAfterPlayerReady(
      data,
      parsed,
      _s.game,
    );
    _refreshLobby(
      data: data,
      game: game,
      eventName: PlayGameHubEvents.playerReady,
      opponentCardPulse: _opponentCardPulseAfter(game),
      opponentReadyPulse: _readyButtonPulseAfter(game),
    );
  }

  /// True when the local user left — caller should pop to home.
  bool onLobbyPlayerLeft(Map<String, dynamic>? data) {
    final isMe = isLocalPlayerLeft(data);
    if (isMe) {
      return true;
    }
    final parsed = _gameFromData(data);
    final game = GameSessionReducer.gameAfterPlayerLeft(
      data,
      parsed,
      _s.game,
    );
    _refreshLobby(
      data: data,
      game: game,
      eventName: PlayGameHubEvents.playerLeft,
      clearOpponentEmote: true,
    );
    return false;
  }

  /// Called from lobby / host. Replaces only that player's emote.
  void applyPlayerEmoted(Map<String, dynamic>? data) {
    final emote = GameSessionReducer.emoteFrom(data);
    if (emote == null) {
      return;
    }
    final mine = _emoteIsMine(emote.playerId);
    if (mine) {
      _meEmoteTimer?.cancel();
      _s = _s.copyWith(
        data: data ?? _s.data,
        meEmote: emote,
      );
      _meEmoteTimer = Timer(const Duration(seconds: 3), () {
        _meEmoteTimer = null;
        _s = _s.copyWith(clearMeEmote: true);
      });
      return;
    }
    _opponentEmoteTimer?.cancel();
    _s = _s.copyWith(
      data: data ?? _s.data,
      opponentEmote: emote,
    );
    _opponentEmoteTimer = Timer(const Duration(seconds: 3), () {
      _opponentEmoteTimer = null;
      _s = _s.copyWith(clearOpponentEmote: true);
    });
  }

  /// I just became ready and they are not → throb their card.
  int _opponentCardPulseAfter(CreatedGame? game) {
    final players = _findPlayers(game?.players);
    final iJustReadied =
        _s.me?.isReady != true && players.me?.isReady == true;
    if (iJustReadied && players.opponent?.isReady != true) {
      return _s.opponentCardPulse + 1;
    }
    return _s.opponentCardPulse;
  }

  /// They just became ready and I am not → throb the Ready button.
  int _readyButtonPulseAfter(CreatedGame? game) {
    final players = _findPlayers(game?.players);
    final theyJustReadied =
        _s.opponent?.isReady != true && players.opponent?.isReady == true;
    if (theyJustReadied && players.me?.isReady != true) {
      return _s.opponentReadyPulse + 1;
    }
    return _s.opponentReadyPulse;
  }
}

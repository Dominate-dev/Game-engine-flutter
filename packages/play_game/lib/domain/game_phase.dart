import '../constants/play_game_hub_events.dart';
import 'game_type.dart';

enum GamePhase {
  waiting,
  lobbyPlay,

  /// The invite-code lobby for a private game.
  ///
  /// Deliberately absent from [fromHubValue]: no hub payload in this
  /// repository is known to name this screen. It is reached from the game's
  /// own `isPrivate`/`mode`, in `GameController._routeByStatus` and
  /// `_refreshLobby`, and from the private entry point before any event.
  lobbyPrivate,
  wdyk,
  auction,
  bell,
  comeBack,
  breaker,
  finishRound;

  static GamePhase? fromHubEvent(String eventName) {
    if (PlayGameHubEvents.gameOverEvents.contains(eventName)) {
      return null;
    }
    if (PlayGameHubEvents.auctionEvents.contains(eventName)) {
      return auction;
    }
    return switch (eventName) {
      PlayGameHubEvents.roundFinished => finishRound,
      PlayGameHubEvents.nextRoundStarted => null,
      _ => fromHubValue(eventName),
    };
  }

  static GamePhase? fromHubValue(Object? value) {
    final key = value?.toString().trim().toLowerCase();
    if (key == null || key.isEmpty) {
      return null;
    }
    return switch (key) {
      'waiting' || 'wait' => waiting,
      'lobby' || 'lobbyplay' || 'lobby_play' || 'playlobby' => lobbyPlay,
      'wdyk' || 'whatdoyouknow' || 'what_do_you_know' => wdyk,
      'auction' => auction,
      'bell' => bell,
      'comeback' || 'come_back' => comeBack,
      'breaker' => breaker,
      'finish' || 'finishround' || 'finish_round' => finishRound,
      _ => GameType.fromId(int.tryParse(key))?.phase,
    };
  }
}

enum GameResult { win, loss, ended }

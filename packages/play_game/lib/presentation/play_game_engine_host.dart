import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_controller/game_session_handle.dart';
import 'play_game_launcher.dart';

// The play_game half of the public API.
//
// coreapp declares GameEngineHost and never depends on a game plugin; this
// implements it, so the game flows stay owned here while the boundary stays
// there. Nothing new is dispatched: every method funnels into the existing
// PlayGame entry points and the existing single exit owner.
//
// The navigator key is the engine's own, not AppTheme.navigatorKey — that one
// is `kDebugMode ? ChuckerFlutter.navigatorKey : null`, so it is null in
// release and unusable for host-driven navigation.
class PlayGameEngineHost implements GameEngineHost {
  PlayGameEngineHost({
    required this.navigatorKey,
    required ProviderContainer container,
  }) : _container = container;

  final GlobalKey<NavigatorState> navigatorKey;
  final ProviderContainer _container;

  GameSessionHandle get _handle =>
      _container.read(gameSessionHandleProvider);

  @override
  bool get isGameActive => _handle.isGameActive;

  // Straight from the handle the single exit owner publishes to. Nothing is
  // re-broadcast or counted here: the one-shot that makes an exit singular
  // lives in GameControllerScreen._exitGame, where it belongs.
  @override
  Stream<void> get onGameExited => _handle.onGameExited;

  @override
  Future<void> joinRandomGame() async {
    final context = _hostContext;
    if (context == null) {
      return;
    }
    await _present(PlayGame.openWaiting(context, animated: false));
  }

  @override
  Future<void> createPrivateGame(List<int> interestIds) async {
    final context = _hostContext;
    if (context == null) {
      return;
    }
    // The ids are the host's, passed through untouched — no default, and no
    // debug id invented here.
    await _present(
      PlayGame.openPrivateGame(
        context,
        interestIds: interestIds,
        animated: false,
      ),
    );
  }

  @override
  Future<void> joinPrivateGame(String code) async {
    final context = _hostContext;
    if (context == null) {
      return;
    }
    // Trimming and the empty-code refusal already live in
    // GameController.joinPrivateGame; the code is forwarded as given.
    await _present(
      PlayGame.openPrivateGameByCode(
        context,
        gameCode: code,
        animated: false,
      ),
    );
  }

  /// Completes when the requested flow is on screen — not when the user later
  /// leaves it.
  ///
  /// `Navigator.push` returns the route's **pop** result, so awaiting it held
  /// the method call open for the whole game: native asked for a flow and did
  /// not hear back until the player had finished with it. What a host is
  /// waiting for is "the flow is mounted", and that is one frame away, so the
  /// frame is what is awaited.
  ///
  /// [popped] is deliberately kept rather than dropped — nothing acts on the
  /// pop result (leaving is reported through `onGameExited`, which is the
  /// contract for it), but discarding the reference outright is what makes a
  /// push fire-and-forget.
  Future<void> _present(Future<void> popped) async {
    unawaited(popped);
    await WidgetsBinding.instance.endOfFrame;
  }

  // Through the handle GameControllerScreen published, which is its own
  // _exitGame — one LeaveGame, one pop, the same cleanup a back gesture
  // performs. A no-op when no game is on screen.
  @override
  Future<void> leaveGame() async {
    _handle.leave();
  }

  BuildContext? get _hostContext {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      AppLogger.log('PlayGameEngineHost — no navigator yet; request ignored');
      return null;
    }
    return navigator.context;
  }
}

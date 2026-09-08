import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/play_game_hub_events.dart';
import '../../domain/game_phase.dart';
import '../../features/games/domain/entities/game_player.dart';
import '../../features/games/domain/entities/game_result_player.dart';
import '../../features/stickers/presentation/providers/stickers_providers.dart';
import '../../l10n/play_game_strings.dart';
import '../dialogs/end_game_dialog.dart';
import '../dialogs/loss_dialog.dart';
import '../dialogs/win_dialog.dart';
import '../pages/lobby_private/lobby_private_game_screen.dart';
import '../pages/lobby_public/lobby_play_game_screen.dart';
import '../pages/rounds/auction_round_screen.dart';
import '../pages/rounds/bell_round_screen.dart';
import '../pages/rounds/breaker_round_screen.dart';
import '../pages/rounds/come_back_round_screen.dart';
import '../pages/rounds/finish_round_screen.dart';
import '../pages/rounds/wdyk_round_screen.dart';
import '../pages/waiting/waiting_screen.dart';
import 'game_controller.dart';
import 'round_sub_panel.dart';
import 'game_exit_scope.dart';
import 'game_session_handle.dart';

class GameControllerScreen extends ConsumerStatefulWidget {
  const GameControllerScreen({
    super.key,
    this.privateInterestIds,
    this.privateGameCode,
  }) : assert(
          privateInterestIds == null || privateGameCode == null,
          'A private entry either creates a game from interests or joins one '
          'by code — never both.',
        );

  /// Non-null starts a **private** game instead of public matchmaking: the
  /// screen opens straight into the private lobby and invokes
  /// `CreatePrivateGame` with these ids once the hub is connected.
  ///
  /// The ids belong to the caller — this screen neither defaults nor invents
  /// them, so the native host can supply the real interest id later without
  /// touching the game engine.
  final List<int>? privateInterestIds;

  /// Non-null **joins** an existing private game instead of creating one: the
  /// screen opens straight into the private lobby and invokes
  /// `JoinPrivateGame` with this code once the hub is connected.
  ///
  /// The code belongs to the caller, the same way [privateInterestIds] does.
  /// Resolving where it came from — a dialog, a deep link, a notification —
  /// and whether it is a PvP code at all is the host's business, not this
  /// screen's.
  final String? privateGameCode;

  /// Either private entry — both must keep [WaitingScreen] off the first
  /// frame, since its own mount dispatches `JoinRandomGame`.
  bool get isPrivateEntry =>
      privateInterestIds != null || privateGameCode != null;

  @override
  ConsumerState<GameControllerScreen> createState() =>
      _GameControllerScreenState();
}

class _GameControllerScreenState extends BaseState<GameControllerScreen>
    with HubEventMixin {
  bool _resultDialogShown = false;
  bool _exitDialogShown = false;
  bool _leaving = false;

  // The round music showRoundIntro starts has no stop of its own — the
  // lobby/waiting screens stop theirs in dispose, the rounds never did. One
  // shot per entry: the game ends once, and a fresh entry gets a fresh
  // screen (and a fresh intro) from autoDispose.
  bool _musicStopped = false;
  bool _exitApiCalled = false;

  /// Whether the private entry has replaced the session yet. Until it has,
  /// the phase on screen belongs to whatever came before this entry.
  bool _privateEntryApplied = false;

  /// The same, for the public entry. Its reset lands post-frame too, and
  /// until it does the session still describes whatever came before.
  bool _publicEntryApplied = false;

  // Held from registration so dispose can unregister without touching `ref`,
  // which Riverpod forbids once the widget is disposed.
  GameSessionHandle? _sessionHandle;

  @override
  bool get handleSignalRConnection => true;

  @override
  List<String> get listenHubEvents => PlayGameHubEvents.hostScreenEvents;

  @override
  void onEventReceived(String name, Map<String, dynamic>? data) {
    final session = ref.read(gameControllerProvider);
    if (session.phase == GamePhase.lobbyPlay ||
        session.phase == GamePhase.lobbyPrivate ||
        session.phase == GamePhase.waiting) {
      return;
    }
    // This listener is the direct SignalR pipeline (HubEventMixin), separate
    // from GameController's reducer stream — a round dialog can still be
    // dispatched from here even once the game has ended, because endGame
    // deliberately leaves phase untouched (the round stays on screen behind
    // the result dialog). result is authoritative once set, so once the game
    // is over no further round overlay may show on top of / behind it.
    if (session.result != null) {
      return;
    }
    switch (name) {
      case PlayGameHubEvents.playerEmoted:
        ref.read(gameControllerProvider.notifier).applyPlayerEmoted(data);
      case PlayGameHubEvents.playerLeft:
        if (ref.read(gameControllerProvider.notifier).isLocalPlayerLeft(data)) {
          unawaited(_leaveGame());
        }
      case PlayGameHubEvents.changeTurn:
        ref.read(gameControllerProvider.notifier).onChangeTurn(data, _roundDialogPresenter);
      case PlayGameHubEvents.penalty:
        ref.read(gameControllerProvider.notifier).onPenalty(data, _roundDialogPresenter);
      case PlayGameHubEvents.timeStarted:
        ref.read(gameControllerProvider.notifier).onTimeStarted(data, _roundDialogPresenter);
      case PlayGameHubEvents.playerPassed:
        ref.read(gameControllerProvider.notifier).onPlayerPassed(data, _roundDialogPresenter);
      case PlayGameHubEvents.playerAnswered:
        ref.read(gameControllerProvider.notifier).onPlayerAnswered(data, _roundDialogPresenter);
      case PlayGameHubEvents.correctAnswer:
        ref.read(gameControllerProvider.notifier).onCorrectAnswer(data, _roundDialogPresenter);
    }
  }

  @override
  void initState() {
    super.initState();
    final interestIds = widget.privateInterestIds;
    final gameCode = widget.privateGameCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Published post-frame like everything else here — Riverpod forbids
        // writing a provider during a widget lifecycle callback. This is how
        // a host-initiated leave reaches _exitGame, the single exit owner.
        //
        // The notifier is held rather than re-read on the way out: `ref` is
        // unusable in dispose().
        final handle = ref.read(gameSessionHandleProvider);
        _sessionHandle = handle;
        handle.register(_exitGame);
        if (gameCode != null) {
          unawaited(_joinPrivateGame(gameCode));
        } else if (interestIds != null) {
          unawaited(_startPrivateGame(interestIds));
        } else {
          unawaited(_startPublicGame());
        }
        unawaited(_loadStickerCatalog());
      }
    });
  }

  @override
  void dispose() {
    _sessionHandle?.unregister(_exitGame);
    super.dispose();
  }

  /// Moves the session into a fresh waiting state, then connects.
  ///
  /// The public counterpart of [_startPrivateGame], and post-frame for the
  /// same reason. The reset comes first: [WaitingScreen] dispatches
  /// `JoinRandomGame` on its own mount, and mounting it on the session a
  /// previous game left behind is how a random entry after a private one
  /// opened that private lobby again and joined nothing.
  ///
  /// No dispatch of its own — WaitingScreen still owns the join, exactly as
  /// before.
  Future<void> _startPublicGame() async {
    ref.read(gameControllerProvider.notifier).enterWaiting();
    if (mounted) {
      setState(() => _publicEntryApplied = true);
    }
    await _ensureHubConnected();
  }

  /// Moves the session into the private lobby, then creates the game.
  ///
  /// Runs post-frame because Riverpod forbids modifying a provider during a
  /// widget lifecycle. The first frame is covered by [_bodyFor] instead, so
  /// [WaitingScreen] — whose only job is dispatching `JoinRandomGame`, the
  /// public matchmaking flow — is never built for a private entry.
  ///
  /// Creation needs a connection first, so the two are sequenced rather than
  /// fired together. The connect step is the one the public entry uses, with
  /// the same silent-failure behaviour.
  Future<void> _startPrivateGame(List<int> interestIds) async {
    final controller = ref.read(gameControllerProvider.notifier);
    controller.enterPrivateLobby();
    if (mounted) {
      setState(() => _privateEntryApplied = true);
    }
    await _ensureHubConnected();
    if (!mounted) {
      return;
    }
    await controller.createPrivateGame(interestIds);
  }

  /// Moves the session into the private lobby, then joins the game.
  ///
  /// The same shape as [_startPrivateGame], and deliberately not merged with
  /// it: the two dispatch different hub methods with different guards, and
  /// the only step they share is the session reset.
  ///
  /// [GameController.enterPrivateLobby] runs before the dispatch, not after,
  /// so a controller still holding a previous game cannot render that game's
  /// players while the join is in flight.
  Future<void> _joinPrivateGame(String gameCode) async {
    final controller = ref.read(gameControllerProvider.notifier);
    controller.enterPrivateLobby();
    if (mounted) {
      setState(() => _privateEntryApplied = true);
    }
    await _ensureHubConnected();
    if (!mounted) {
      return;
    }
    await controller.joinPrivateGame(gameCode);
  }

  // A1: this screen is the GameEngine's entry point — PlayGame.openWaiting
  // pushes it, and it hosts every phase from Waiting onward. The native host
  // may or may not have connected the hub before opening it, so entry has to
  // guarantee a connection rather than assume one.
  //
  // hasLiveConnection covers connected *and* connecting, so an existing
  // connection is reused and never duplicated. The guard also keeps the
  // reuse correct: while a connect is still in flight connectHub's own
  // connectIfNeeded no-ops and it would then report hubConnectFailed even
  // though nothing failed.
  //
  // Hub event binding is untouched — playGameHubBindingsProvider binds on
  // construction, and SignalRService re-attaches handlers after connecting.
  // A failed connect stays silent here — no modal over the screen being
  // entered. SignalRService still sets `failed` and schedules its own
  // backoff retry, and a later drop still raises the ConnectionLoader.
  Future<void> _ensureHubConnected() async {
    if (ref.read(signalRServiceProvider).hasLiveConnection) {
      return;
    }
    await connectHub(error: ErrorType.none);
  }

  /// The presenter every round handler is given.
  ///
  /// A [RoundLottieDialog] or [PlayerAnsweredDialog] is rendered in this
  /// screen's own subtree (see [RoundSubPanelLayer]), so any regular dialog
  /// route stays above it; everything else keeps its normal route, unchanged.
  Future<void> Function({required Widget child, bool barrierDismissible})
      get _roundDialogPresenter => roundDialogPresenter(
            ref,
            // The same guard showAppDialog applies before pushing a route.
            canPresent: () =>
                mounted && ModalRoute.of(context)?.isActive != false,
            fallback: ({
              required Widget child,
              bool barrierDismissible = true,
            }) =>
                showAppDialog<void>(
              child: child,
              barrierDismissible: barrierDismissible,
            ),
          );
  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);

    ref.listen(gameControllerProvider, (previous, next) {
      final result = next.result;
      if (result == null || _resultDialogShown) {
        return;
      }
      if (previous?.result == result) {
        return;
      }
      _resultDialogShown = true;
      // Captured now, at the moment the result actually lands — not re-read
      // from the provider inside the callback, where a later event could
      // have moved the roster on.
      final me = next.me;
      final opponent = next.opponent;
      final meResult = next.myResult;
      final opponentResult = next.opponentResult;
      // GameOver.gameResultPlayers leaves playerName/profileImageUrl empty
      // on real payloads — display identity comes from the roster.
      // winnerPlayer resolves it by winnerId; when that cannot be resolved
      // (no gameOver, no winnerId, or it names neither seated player), fall
      // back to whichever side this result already implies, rather than
      // showing a blank name.
      final winner = next.winnerPlayer ??
          (result == GameResult.win ? me : opponent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showResultDialog(
            result,
            winner: winner,
            me: me,
            opponent: opponent,
            meResult: meResult,
            opponentResult: opponentResult,
          );
        }
      });
    });

    ref.listen(gameControllerProvider, (previous, next) {
      if (!_isRoundIntroPhase(next.phase) || previous?.phase == next.phase) {
        return;
      }
      // Decided here, not inside the callback below: a backgrounded app
      // produces no frames, so the callback would not run until it returned —
      // and would then play an intro the round has moved past. WDYK only; the
      // other rounds keep their existing behaviour.
      if ((next.phase == GamePhase.wdyk || next.phase == GamePhase.auction) &&
          !ref.read(gameControllerProvider.notifier).isAppForeground) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          ref.read(gameControllerProvider.notifier).showRoundIntro(
                _roundDialogPresenter,
                audio,
              ),
        );
      });
    });

    final isImmersive = session.phase == GamePhase.waiting ||
        session.phase == GamePhase.lobbyPlay ||
        session.phase == GamePhase.lobbyPrivate ||
        session.phase == GamePhase.wdyk ||
        session.phase == GamePhase.auction ||
        session.phase == GamePhase.bell ||
        session.phase == GamePhase.comeBack ||
        session.phase == GamePhase.breaker ||
        session.phase == GamePhase.finishRound;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _leaving) {
          return;
        }
        // LobbyPlayGameScreen owns its own back-gesture handling for this
        // phase (its own nested PopScope -> _leaveToHome(), matching its
        // exit button's existing immediate-leave, no-confirmation
        // behavior). Both PopScopes register on the same ModalRoute — a
        // pop attempt notifies every registered PopEntry, not just one — so
        // without this guard _confirmExit() also fires on the same
        // gesture, racing LobbyPlayGameScreen's own leaveGame()/pop.
        if (session.phase == GamePhase.lobbyPlay ||
            session.phase == GamePhase.lobbyPrivate) {
          return;
        }
        _confirmExit();
      },
      // The one exit owner, handed to everything inside this route: Waiting
      // and the two lobbies leave through it instead of popping for
      // themselves, so there is exactly one pop and one LeaveGame however
      // many of them react to the same moment.
      child: GameExitScope(
        leave: ({bool dispatchLeaveGame = true}) =>
            _exitGame(dispatchLeaveGame: dispatchLeaveGame),
        isLeaving: () => _leaving,
        // The round overlay layer sits inside this page's subtree, above the
        // round content and below every dialog route — the whole point of the
        // sub-panel: a DialogRoute is structurally above the page route that
        // hosts this stack, so nothing has to maintain that ordering.
        child: Stack(
          children: [
            AppScaffold(
              scrollable: false,
              safeArea: !isImmersive,
              appBar: isImmersive
                  ? null
                  : AppToolbar(
                      title: strings.titleFor(session.phase),
                      showBackButton: false,
                    ),
              padding: isImmersive
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              backgroundColor: isImmersive ? Colors.transparent : null,
              body: _bodyFor(session.phase),
            ),
            const Positioned.fill(child: RoundSubPanelLayer()),
          ],
        ),
      ),
    );
  }

  Widget _bodyFor(GamePhase phase) {
    // The frames before _startPrivateGame's post-frame callback runs. The
    // session still describes whatever came before — the default `waiting`
    // phase on a fresh controller, or a previous game's phase on a reused
    // one — and neither may be built here: WaitingScreen would schedule its
    // JoinRandomGame dispatch, and a lobby or round screen would show the
    // previous game. A private entry opens straight into its own lobby.
    if (widget.isPrivateEntry && !_privateEntryApplied) {
      return const LobbyPrivateGameScreen();
    }
    // The public entry's own frame-zero case. Its reset has not run yet, so
    // the phase below is still the previous game's — routing on it opened
    // that game's screen, and WaitingScreen must not mount before the reset
    // either: it dispatches JoinRandomGame from whatever session it finds.
    // Nothing is drawn for the one frame; _startPublicGame lands on the next.
    if (!widget.isPrivateEntry && !_publicEntryApplied) {
      return const SizedBox.shrink();
    }
    return switch (phase) {
      GamePhase.waiting => const WaitingScreen(),
      GamePhase.lobbyPlay => const LobbyPlayGameScreen(),
      GamePhase.lobbyPrivate => const LobbyPrivateGameScreen(),
      GamePhase.wdyk => const WdykRoundScreen(),
      GamePhase.auction => const AuctionRoundScreen(),
      GamePhase.bell => const BellRoundScreen(),
      GamePhase.comeBack => const ComeBackRoundScreen(),
      GamePhase.breaker => const BreakerRoundScreen(),
      GamePhase.finishRound => const FinishRoundScreen(),
    };
  }

  Future<void> _confirmExit() async {
    if (_exitDialogShown || _resultDialogShown) {
      return;
    }
    _exitDialogShown = true;
    unawaited(audio.playExitTheGame());
    final strings = ref.read(playGameStringsProvider);
    final shouldExit = await showAppDialog<bool>(
      child: ShowDialogGame(
        title: strings.areYouSureYouWantToGoOut,
        buttonText: strings.exitTheGame,
      ),
    );
    _exitDialogShown = false;
    if (shouldExit == true && mounted) {
      await _leaveGame();
    }
  }

  Future<void> _showResultDialog(
    GameResult result, {
    GamePlayer? winner,
    GamePlayer? me,
    GamePlayer? opponent,
    GameResultPlayer? meResult,
    GameResultPlayer? opponentResult,
  }) async {
    // The game is over — the round music goes with it, before the result
    // overlay rather than when the player dismisses it. Music only, so the
    // win/loss SFX below still play over the silence.
    _stopGameMusic();
    // Win and loss only; the neutral end-of-game dialog stays silent. Played
    // here rather than inside the dialogs because this is the one place the
    // result overlay is raised, and both widgets are pure presentation.
    switch (result) {
      case GameResult.win:
        unawaited(audio.playWinningGame());
      case GameResult.loss:
        unawaited(audio.playLosingGame());
      case GameResult.ended:
        break;
    }
    await showAppDialog<void>(
      barrierDismissible: false,
      child: switch (result) {
        GameResult.win => WinDialog(
            winner: winner,
            me: me,
            opponent: opponent,
            meResult: meResult,
            opponentResult: opponentResult,
          ),
        GameResult.loss => LossDialog(
            winner: winner,
            me: me,
            opponent: opponent,
            meResult: meResult,
            opponentResult: opponentResult,
          ),
        GameResult.ended => const EndGameDialog(),
      },
    );
    if (mounted) {
      await _returnToHomeAfterResult();
    }
  }

  /// The one exit. Every leave in the game funnels here, from this screen's
  /// own back/result/PlayerLeft paths and, through [GameExitScope], from
  /// Waiting and the two lobbies.
  ///
  /// One-shot across all of them: `_leaving` is claimed synchronously, before
  /// anything async, so a back gesture and a hub event landing in the same
  /// tick cannot both leave. `mounted` is deliberately *not* the guard — a
  /// popped route stays mounted for its whole exit transition, which is
  /// exactly the window the duplicate pops were happening in.
  ///
  /// [dispatchLeaveGame] false records the leave without the hub call, for
  /// the exits the server already knows about. Either way the session is
  /// marked left, so nothing on the dying controller dispatches again.
  void _exitGame({bool dispatchLeaveGame = true}) {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _stopGameMusic();
    final controller = ref.read(gameControllerProvider.notifier);
    if (dispatchLeaveGame) {
      unawaited(_leaveAllGames());
    } else {
      controller.markLeftGame();
    }
    _popGameRoute();
    // The exit has happened — tell the public engine, which forwards it to
    // native as `onGameExited`. Inside the `_leaving` one-shot, and after the
    // pop, so every path that reaches this method reports exactly one exit and
    // reports it only once the route is actually gone. Reaching GameOver or
    // showing the result dialog does not come through here; closing that
    // dialog does, via _returnToHomeAfterResult.
    ref.read(gameSessionHandleProvider).notifyExited();
  }

  /// Removes this screen's own route, and only while it still has one.
  ///
  /// `Navigator.pop()` removes the topmost *present* route; a route already
  /// in `_RouteLifecycle.popping` is not present, so an unguarded second pop
  /// removed the page underneath instead — the black screen. `isActive` is
  /// false from the moment this route is popped, so this cannot run twice
  /// even if `_leaving` were somehow bypassed.
  void _popGameRoute() {
    if (!mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) {
      return;
    }
    Navigator.of(context).pop();
  }

  // Music only. stopMusic touches the music player alone, so the SFX players
  // carrying winningGame/losingGame and every dialog sound are untouched.
  void _stopGameMusic() {
    if (_musicStopped) {
      return;
    }
    _musicStopped = true;
    unawaited(audio.stop(type: AudioSourceType.music));
  }

  Future<void> _leaveGame() async {
    _exitGame();
  }

  // Closing the result dialog is not an explicit leave — GameOver/
  // GameFinished/GameTerminated already mean the server considers the match
  // concluded, so unlike _leaveGame() this dispatches no LeaveGame call.
  Future<void> _returnToHomeAfterResult() async {
    _exitGame(dispatchLeaveGame: false);
  }

  Future<void> _loadStickerCatalog() async {
    await runApi(
      () => loadStickerCatalog(ref.read(getStickerGroupsUseCaseProvider)),
      loading: LoadingType.none,
      onSuccess: (catalog) {
        ref.read(stickerCatalogProvider.notifier).state = catalog;
      },
    );
  }

  Future<void> _leaveAllGames() async {
    if (_exitApiCalled) {
      return;
    }
    _exitApiCalled = true;
    await ref.read(gameControllerProvider.notifier).leaveGame();
  }

  bool _isRoundIntroPhase(GamePhase phase) {
    return phase == GamePhase.wdyk ||
        phase == GamePhase.auction ||
        phase == GamePhase.bell ||
        phase == GamePhase.comeBack ||
        phase == GamePhase.breaker;
  }
}

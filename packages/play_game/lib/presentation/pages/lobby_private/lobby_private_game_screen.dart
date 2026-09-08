import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/play_game_hub_events.dart';
import '../../../domain/game_phase.dart';
import '../../../features/games/domain/entities/created_game.dart';
import '../../../features/games/domain/entities/game_player.dart';
import '../../../features/games/presentation/providers/game_providers.dart';
import '../../../l10n/play_game_strings.dart';
import '../../game_controller/game_controller.dart';
import '../../game_controller/game_exit_scope.dart';
import '../player_profile/player_profile_screen.dart';
import '../../widgets/lobby/lobby_players_row.dart';

class LobbyPrivateGameScreen extends ConsumerStatefulWidget {
  const LobbyPrivateGameScreen({super.key});

  @override
  ConsumerState<LobbyPrivateGameScreen> createState() =>
      _LobbyPrivateGameScreenState();
}

class _LobbyPrivateGameScreenState extends BaseState<LobbyPrivateGameScreen>
    with HubEventMixin {
  // The host (GameControllerScreen) owns the connection for this phase, the
  // same way it does for the public lobby.
  @override
  bool get handleInternetConnection => false;

  @override
  List<String> get listenHubEvents =>
      PlayGameHubEvents.privateLobbyScreenEvents;

  @override
  void onEventReceived(String name, Map<String, dynamic>? data) {
    final controller = ref.read(gameControllerProvider.notifier);
    switch (name) {
      case PlayGameHubEvents.playerEmoted:
        controller.applyPlayerEmoted(data);
      case PlayGameHubEvents.playerLeft:
        // Three cases, and only one of them ends this lobby.
        //
        // My own leave is already on its way out through the exit that
        // produced it — no telling, no dialog. Otherwise the leaver is the
        // other seat, and which one that is follows from which entry opened
        // this lobby: if I joined by code, they are the creator and the game
        // is over for me; if I created it, they are the guest and I stay,
        // with the seat `onLobbyPlayerLeft` has already cleared.
        if (controller.onLobbyPlayerLeft(data)) {
          unawaited(_leaveLobby());
        } else if (!controller.isPrivateGameCreator) {
          unawaited(_onCreatorLeft());
        }
      case PlayGameHubEvents.playerReady:
        controller.onLobbyPlayerReady(data);
      case PlayGameHubEvents.gameStarted:
        controller.onLobbyGameStarted(data);
      case PlayGameHubEvents.gameUpdated:
        controller.onLobbyGameUpdated(data);
      case PlayGameHubEvents.gameRestore:
        controller.onLobbyGameRestore(data);
      case PlayGameHubEvents.gameFinished:
        // The server sends this immediately behind the creator's PlayerLeft.
        // When that dialog is already up the exit belongs to its Confirm
        // button, and leaving here would take it away mid-question:
        // `_popGameRoute` pops the topmost route, which at that moment is the
        // dialog itself. Every other way a game finishes in this lobby keeps
        // the silent leave it has always had.
        if (!_creatorLeftShown) {
          unawaited(_leaveLobby());
        }
      case PlayGameHubEvents.wrongGameCode:
        _onWrongGameCode();
    }
  }

  /// The creator left the private lobby this device joined by code.
  ///
  /// There is no game left to sit in, so the player is told and then leaves
  /// through `_leaveLobby` — the same exit every other leave here uses, so
  /// there is still one pop and one LeaveGame.
  ///
  /// Shown once: a second PlayerLeft must not stack a second dialog on top,
  /// and `_leaving` alone cannot guard it because `_leaveLobby` only claims
  /// that flag after this dialog has been confirmed.
  ///
  /// Confirmation is the only way out, and all three routes around it are
  /// closed: `barrierDismissible: false` for a tap outside, `isCancelable:
  /// false` for the close icon, and `PopScope` for the system back gesture,
  /// which `GameDialog` does not otherwise guard. The leave happens after the
  /// await, so nothing moves until the player has pressed the button.
  Future<void> _onCreatorLeft() async {
    if (!mounted || _leaving || _creatorLeftShown) {
      return;
    }
    _creatorLeftShown = true;
    final confirmed = await showAppDialog<bool>(
      barrierDismissible: false,
      child: PopScope(
        canPop: false,
        child: ShowDialogGame(
          title: ref.read(playGameStringsProvider).creatorTerminatedGame,
          isCancelable: false,
        ),
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    await _leaveLobby();
  }

  bool _creatorLeftShown = false;

  /// The joined code does not name a game.
  ///
  /// Treated as a bare signal: the repository has no confirmed payload for
  /// this event, so `data` is deliberately not read. Without this the lobby
  /// simply sat there empty — the code was wrong, so no `GameJoined` was ever
  /// coming, and nothing else would have told the player.
  ///
  /// Leaves without invoking `LeaveGame`: the join was refused, so there is
  /// no game on the hub to leave.
  void _onWrongGameCode() {
    if (!mounted || _leaving) {
      return;
    }
    _leaving = true;
    showToast(
      ref.read(playGameStringsProvider).wrongGameCode,
      type: ToastType.error,
    );
    // No LeaveGame: the join was refused, so there is no game to leave. The
    // route still belongs to its owner.
    if (GameExitScope.leaveThrough(context, dispatchLeaveGame: false)) {
      return;
    }
    Navigator.of(context).pop();
  }

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(audio.startRunningMusic());
    // The game may already be created by the time this lobby mounts (a
    // GameCreated that landed before the phase switch), in which case no
    // later change to the code would fire the listener below.
    postFrame(this, _requestInviteLink);
  }

  /// Asks for the invite link for whatever code the session currently holds.
  ///
  /// Safe to call repeatedly: the notifier issues one request per code, so
  /// the mount path and the listener below cannot double-fetch, and a code
  /// that is still missing is simply not requested.
  void _requestInviteLink() {
    if (!mounted) {
      return;
    }
    final code = ref.read(gameControllerProvider).game?.gameCode;
    unawaited(ref.read(privateGameLinkProvider.notifier).ensureFor(code));
  }

  @override
  void dispose() {
    unawaited(audio.stop(type: AudioSourceType.music));
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);
    // The private session begins when the controller enters this phase, which
    // happens on the entry's first post-frame. Until then `session` still
    // describes whatever came before — a previous game's seated players,
    // their names and profile images — and this screen is already on screen
    // (see GameControllerScreen._bodyFor). Reading nothing from it until the
    // phase is ours keeps that data off the first frame; the entry itself
    // then replaces the session outright.
    final started = session.phase == GamePhase.lobbyPrivate;
    final game = started ? session.game : null;
    final user = started ? session.me : null;
    final opponent = started ? session.opponent : null;
    // Same ready-countdown derivation the public lobby uses — the server owns
    // every value; nothing is defaulted when it is absent.
    final timerOn = game?.waitingToBeReadyTimerStart == true;
    final currentTimer = game?.currentTimerValue ?? 0;
    final maxTimer = game?.waitingToBeReadyTimerValue ?? 0;
    final readySeconds = timerOn
        ? (currentTimer > 0 && currentTimer < maxTimer
            ? currentTimer.toInt()
            : maxTimer)
        : 0;
    final iAmReady = user?.isReady == true;
    final inviteLink = ref.watch(privateGameLinkProvider);

    // The code arrives with GameCreated, which can land after this screen is
    // already up. Keyed on the code itself, so the routine rebuilds every
    // other hub event causes never re-request.
    ref.listen(gameControllerProvider, (previous, next) {
      if (previous?.game?.gameCode != next.game?.gameCode) {
        _requestInviteLink();
      }
    });

    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _leaving) {
          return;
        }
        unawaited(_leaveLobby());
      },
      child: AppScaffold(
        scrollable: false,
        safeArea: false,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        body: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const AppImageView(
                assetPath: AppAssets.splashBackground,
                package: AppAssets.packageName,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
              SafeArea(
                left: false,
                right: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _backUi(),
                      const SizedBox(height: 8),
                      _titleCardUi(strings, game, inviteLink),
                      const SizedBox(height: 15),
                      LobbyPlayersRow(
                        userName: _nameOf(user),
                        opponentName: opponent == null
                            ? strings.waitingForPlayer
                            : _nameOf(opponent),
                        userHint: strings.readyCountdownHint,
                        opponentHint: strings.playerReplaceHint,
                        userImageUrl: _imageOf(user),
                        opponentImageUrl: _imageOf(opponent),
                        showUserAvatar: user != null,
                        showOpponentAvatar: opponent != null,
                        timerSeconds: readySeconds,
                        showUserTimer:
                            timerOn && readySeconds > 0 && !iAmReady,
                        showOpponentTimer: timerOn &&
                            readySeconds > 0 &&
                            opponent?.isReady == false,
                        // Emotes are player imagery too — gated the same way.
                        userEmoteUrl:
                            started ? session.meEmote?.imageUrl : null,
                        opponentEmoteUrl:
                            started ? session.opponentEmote?.imageUrl : null,
                        onUserAvatarTap: _avatarTap(user),
                        onOpponentAvatarTap: _avatarTap(opponent),
                        opponentCardPulse:
                            started ? session.opponentCardPulse : 0,
                      ),
                      const Spacer(),
                      _readyButtonUi(strings, iAmReady),
                      const SizedBox(height: 15),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveLobby() async {
    if (!mounted || _leaving) {
      return;
    }
    _leaving = true;
    // Through the route's owner — see WaitingScreen._leaveToPreviousScreen.
    if (GameExitScope.leaveThrough(context)) {
      return;
    }
    unawaited(ref.read(gameControllerProvider.notifier).leaveGame());
    Navigator.of(context).pop();
  }

  String _nameOf(GamePlayer? player) => player?.playerName.trim() ?? '';

  String? _imageOf(GamePlayer? player) =>
      AppUrl.httpOrNull(player?.profileImageUrl);

  /// Real seated player only — no debug id, and no tap when the hub has not
  /// named a usable one.
  VoidCallback? _avatarTap(GamePlayer? player) {
    if (player == null || player.isBot) {
      return null;
    }
    final raw = player.userId ?? player.id;
    final id = int.tryParse(raw.trim());
    if (id == null || id == 0) {
      return null;
    }
    return () => PlayerProfileScreen.show(context, playerId: id);
  }

  Widget _backUi() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AppImageView(
              assetPath: AppAssets.backLongIcon,
              package: AppAssets.packageName,
              size: 24,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleCardUi(
    PlayGameStrings strings,
    CreatedGame? game,
    PrivateGameLinkState inviteLink,
  ) {
    final tournamentName = game?.tournmentGameName?.trim() ?? '';
    final title =
        tournamentName.isEmpty ? strings.pitchNumber : tournamentName;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          AppTextView(
            title,
            fontWeight: AppFontWeight.bold,
            fontSize: 16,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _codeRowUi(game?.gameCode?.trim() ?? '', inviteLink),
        ],
      ),
    );
  }

  /// The server's own code. Until `GameCreated` lands there is nothing to
  /// show, and no placeholder is invented — the row simply holds its space.
  Widget _codeRowUi(String code, PrivateGameLinkState inviteLink) {
    final digits = code.split('');
    // Sharing needs both halves — the server's code and the server's link.
    // Until GenerateURL has answered there is nothing to send, and no link is
    // constructed locally to fill the gap.
    final canShare = code.isNotEmpty && inviteLink.hasUrl;

    return Stack(
      alignment: Alignment.center,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < digits.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _codeDigitUi(digits[i]),
              ],
            ],
          ),
        ),
        Align(
          // Physical, not directional: the share action sits on the right
          // edge in both languages. AlignmentDirectional.centerStart would
          // resolve against this screen's own Directionality (rtl for
          // Arabic, ltr for English) and so mirror the icon to the left in
          // English. Nothing else in the row changes — the digits keep their
          // own LTR run and the surrounding content keeps the round's
          // direction.
          alignment: Alignment.centerRight,
          child: Opacity(
            // The same dimmed-when-unavailable affordance the round screens
            // already use for their disabled actions.
            opacity: canShare ? 1 : 0.4,
            child: GestureDetector(
              onTap:
                  canShare ? () => _shareCode(code, inviteLink.url!) : null,
              child: const AppImageView(
                assetPath: AppAssets.replayIcon,
                package: AppAssets.packageName,
                width: 40,
                height: 40,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _codeDigitUi(String digit) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.circular(8),
      ),
      child: AppNumberTextView(
        digit,
        fontSize: 22,
        color: AppColors.card,
        fontWeight: AppFontWeight.enBold,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _readyButtonUi(PlayGameStrings strings, bool iAmReady) {
    return GameButton(
      label: strings.iAmReady,
      onPressed: iAmReady ? null : _onReady,
    );
  }

  /// The server owns readiness — the button reflects `me.isReady` coming back
  /// on PlayerReady, never a local flag.
  Future<void> _onReady() async {
    await ref.read(gameControllerProvider.notifier).readyForGame();
  }

  /// The existing localized message, then the server's link on its own line —
  /// the message already ends by inviting the reader to click it. Neither the
  /// wording nor the code formatting changes.
  Future<void> _shareCode(String code, String url) {
    final strings = ref.read(playGameStringsProvider);
    return AppShare.shareText(
      '${strings.shareGameMessage(code)}\n$url',
      context: context,
    );
  }
}

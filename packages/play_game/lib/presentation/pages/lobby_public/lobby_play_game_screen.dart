import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/play_game_hub_events.dart';
import '../../../features/games/domain/entities/created_game.dart';
import '../../../features/games/domain/entities/game_player.dart';
import '../../../l10n/play_game_strings.dart';
import '../../dialogs/interaction_dialog.dart';
import '../../dialogs/setting_game_dialog.dart';
import '../../game_controller/game_controller.dart';
import '../../game_controller/game_exit_scope.dart';
import '../player_profile/player_profile_screen.dart';
import '../../widgets/lobby/lobby_players_row.dart';

class LobbyPlayGameScreen extends ConsumerStatefulWidget {
  const LobbyPlayGameScreen({super.key});

  @override
  ConsumerState<LobbyPlayGameScreen> createState() =>
      _LobbyPlayGameScreenState();
}

class _LobbyPlayGameScreenState extends BaseState<LobbyPlayGameScreen>
    with HubEventMixin {
  @override
  bool get handleInternetConnection => false;

  @override
  List<String> get listenHubEvents => PlayGameHubEvents.lobbyScreenEvents;

  @override
  void onEventReceived(String name, Map<String, dynamic>? data) {
    final controller = ref.read(gameControllerProvider.notifier);
    switch (name) {
      case PlayGameHubEvents.playerEmoted:
        controller.applyPlayerEmoted(data);
      case PlayGameHubEvents.playerLeft:
        if (controller.onLobbyPlayerLeft(data)) {
          _leaveToHome();
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
        _leaveToHome();
    }
  }

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(audio.startRunningMusic());
  }

  @override
  void dispose() {
    unawaited(audio.stop(type: AudioSourceType.music));
    super.dispose();
  }

  // Leaves through the route's owner — see WaitingScreen._leaveToPreviousScreen.
  void _leaveToHome() {
    if (_leaving) {
      return;
    }
    _leaving = true;
    if (GameExitScope.leaveThrough(context)) {
      return;
    }
    unawaited(ref.read(gameControllerProvider.notifier).leaveGame());
    Navigator.of(context).pop();
  }

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final session = ref.watch(gameControllerProvider);
    final game = session.game;
    final user = session.me;
    final opponent = session.opponent;
    final timerOn = game?.waitingToBeReadyTimerStart == true;
    final currentTimer = game?.currentTimerValue ?? 0;
    final maxTimer = game?.waitingToBeReadyTimerValue ?? 0;
    final readySeconds = timerOn
        ? (currentTimer > 0 && currentTimer < maxTimer
            ? currentTimer.toInt()
            : maxTimer)
        : 0;
    final showUserTimer = timerOn &&
        readySeconds > 0 &&
        user?.isReady == false;
    final showOpponentTimer = timerOn &&
        readySeconds > 0 &&
        opponent?.isReady == false;
    final iAmReady = user?.isReady == true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _leaveToHome();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
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
                  const SizedBox(height: 10),
                  _headerUi(),
                  const SizedBox(height: 20),
                  _titleCardUi(strings, game),
                  const SizedBox(height: 15),
                  LobbyPlayersRow(
                    userName: _nameOf(user),
                    opponentName: _nameOf(opponent),
                    userHint: strings.readyCountdownHint,
                    opponentHint: opponent == null
                        ? strings.waitingForPlayer
                        : strings.playerReplaceHint,
                    userImageUrl: _imageOf(user),
                    opponentImageUrl: _imageOf(opponent),
                    showUserAvatar: user != null,
                    showOpponentAvatar: opponent != null,
                    timerSeconds: readySeconds,
                    showUserTimer: showUserTimer,
                    showOpponentTimer: showOpponentTimer,
                    userEmoteUrl: session.meEmote?.imageUrl,
                    opponentEmoteUrl: session.opponentEmote?.imageUrl,
                    onUserAvatarTap: _avatarTap(user),
                    onOpponentAvatarTap: _avatarTap(opponent),
                    opponentCardPulse: session.opponentCardPulse,
                  ),
                  const Spacer(),
                  _readyButtonUi(strings, iAmReady, session.opponentReadyPulse),
                  const SizedBox(height: 10),
                  _exitGameUi(context, strings),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _nameOf(GamePlayer? player) => player?.playerName.trim() ?? '';

  String? _imageOf(GamePlayer? player) =>
      AppUrl.httpOrNull(player?.profileImageUrl);

  Widget _headerUi() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => showAppDialog<void>(child: const SettingGameDialog()),
          child: const AppImageView(
            assetPath: AppAssets.settingsIcon,
            package: AppAssets.packageName,
            size: 20,
            fit: BoxFit.contain,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => showAppDialog<void>(child: const InteractionDialog()),
          child: const AppLottieView.emojis(
            size: 35,
            fit: BoxFit.contain,
            scale: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _titleCardUi(PlayGameStrings strings, CreatedGame? game) {
    final tournamentName = game?.tournmentGameName?.trim() ?? '';
    final title = tournamentName.isEmpty ? strings.generalGame : tournamentName;
    final subtitle = game?.isPrivate == true
        ? (game?.gameCode?.trim() ?? '')
        : strings.playerVersusPlayer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          AppTextView(
            title,
            fontSize: 12,
            textAlign: TextAlign.center,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            AppTextView(
              subtitle,
              fontWeight: AppFontWeight.bold,
              fontSize: 14,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _readyButtonUi(
    PlayGameStrings strings,
    bool iAmReady,
    int opponentReadyPulse,
  ) {
    final button = GameButton(
      label: strings.iAmReady,
      onPressed: iAmReady ? null : _onReady,
    );
    if (iAmReady || opponentReadyPulse == 0) {
      return button;
    }
    return AppThrob(
      key: ValueKey(opponentReadyPulse),
      count: 2,
      child: button,
    );
  }

  Future<void> _onReady() async {
    await ref.read(gameControllerProvider.notifier).readyForGame();
  }

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

  Widget _exitGameUi(BuildContext context, PlayGameStrings strings) {
    return GestureDetector(
      onTap: _leaveToHome,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 48,
        margin: const EdgeInsets.only(bottom: 20, right: 3, left: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.error),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppTextView(
          strings.exitTheGame,
          fontWeight: AppFontWeight.medium,
          fontSize: 12,
          color: AppColors.error,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

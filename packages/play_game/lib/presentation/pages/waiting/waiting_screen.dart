import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/play_game_hub_events.dart';
import '../../../l10n/play_game_strings.dart';
import '../../game_controller/game_controller.dart';
import '../../game_controller/game_exit_scope.dart';

class WaitingScreen extends ConsumerStatefulWidget {
  const WaitingScreen({super.key});

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends BaseState<WaitingScreen> with HubEventMixin {
  @override
  bool get handleInternetConnection => false;

  @override
  List<String> get listenHubEvents => PlayGameHubEvents.waitingScreenEvents;

  @override
  void onEventReceived(String name, Map<String, dynamic>? data) {
    switch (name) {
      case PlayGameHubEvents.gameUpdated:
        ref.read(gameControllerProvider.notifier).onWaitingGameUpdated(data);
      case PlayGameHubEvents.gameRestore:
        ref.read(gameControllerProvider.notifier).onWaitingGameRestore(data);
      // GameFinished is deliberately absent. It is an *active game* lifecycle
      // event: it says the match this client was playing has concluded, which
      // is meaningless for a screen still searching for one. A late or stale
      // one — the tail of a previous game arriving after a reconnect — used to
      // tear Waiting down, dispatching LeaveGame and popping the route out
      // from under a search the user had just started.
      //
      // It stays in `waitingScreenEvents` on purpose: that list is also what
      // `GameController._onHubEvent` uses to decide which events the waiting
      // phase leaves to this screen, so removing it there would instead route
      // it into `endGame` and put a result dialog over the search. Ignored
      // here means ignored by the waiting lifecycle, which is the intent.
      case PlayGameHubEvents.error:
        _leaveToPreviousScreen();
    }
  }

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(audio.startLobbyMusic());
    postFrame(this, () {
      unawaited(ref.read(gameControllerProvider.notifier).onWaitingShown());
    });
  }

  @override
  void dispose() {
    unawaited(audio.stop(type: AudioSourceType.music));
    super.dispose();
  }

  /// Leaves through the route's owner rather than popping for itself.
  ///
  /// This screen lives inside GameControllerScreen's route, so its own
  /// `Navigator.pop()` removed whatever was topmost — which, once that route
  /// was already popping, was the page underneath. The exit itself is
  /// unchanged: the same `LeaveGame` still goes out, from the one owner.
  void _leaveToPreviousScreen() {
    if (_leaving) {
      return;
    }
    _leaving = true;
    if (GameExitScope.leaveThrough(context)) {
      return;
    }
    // No owner above (a WaitingScreen mounted on its own, as some tests do):
    // the previous behaviour, unchanged.
    unawaited(ref.read(gameControllerProvider.notifier).leaveGame());
    Navigator.of(context).pop();
  }

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);

    return Stack(
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _lottieUi(),
                      const SizedBox(height: 8),
                      AppTextView(
                        strings.searchingPlayers,
                        fontWeight: AppFontWeight.bold,
                        fontSize: 13,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                _exitGameUi(context, strings),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lottieUi() {
    return const AppLottieView.lobby(
      size: 200,
      fit: BoxFit.cover,
    );
  }

  Widget _exitGameUi(BuildContext context, PlayGameStrings strings) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: AppTextView(
        strings.exitTheGame,
        fontWeight: AppFontWeight.medium,
        fontSize: 16,
        color: AppColors.error,
        textAlign: TextAlign.center,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 35),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:coreapp/coreapp.dart';
import 'package:play_game/play_game.dart';

import '../../../../core/constants/debug_config.dart';

  final homeLauncherRouteObserver = RouteObserver<PageRoute<dynamic>>();

class HomeLauncherPage extends ConsumerStatefulWidget {
  const HomeLauncherPage({super.key});

  @override
  ConsumerState<HomeLauncherPage> createState() => _HomeLauncherPageState();
}

class _HomeLauncherPageState extends BaseState<HomeLauncherPage>
    with RouteAware {
  late final TextEditingController _socialMediaIdController;
  late final TextEditingController _gameCodeController;

  @override
  void initState() {
    super.initState();
    _socialMediaIdController = TextEditingController(
      text: DebugConfig.socialMedia,
    );
    _gameCodeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(PlayGame.clearGameData(ref));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      homeLauncherRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    homeLauncherRouteObserver.unsubscribe(this);
    _socialMediaIdController.dispose();
    _gameCodeController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    unawaited(PlayGame.clearGameData(ref));
  }

  @override
  Widget buildPage(BuildContext context) {
    final appStrings = ref.watch(appStringsProvider);
    final isRegistering = ref.watch(authNotifierProvider).isLoading;
    final hubStatus = ref.watch(signalRStatusProvider).valueOrNull;
    final isHubBusy = hubStatus == SignalRStatus.connecting ||
        hubStatus == SignalRStatus.reconnecting;

    return AppScaffold(
      appBar: AppToolbar(
        title: appStrings.homeTitle,
        showBackButton: false,
        actions: [
          AppIconButton(
            icon: Icons.settings_outlined,
            onPressed: () => _openLanguageSettings(appStrings),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GameButton(
                  label: appStrings.loader,
                  onPressed: _onShowLoader,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GameButton(
                  label: appStrings.connectionLoader,
                  onPressed: _onShowConnectionLoader,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GameButton(label: appStrings.play, onPressed: _onPlayTapped),
          const SizedBox(height: 12),
          GameButton(label: appStrings.pvp, onPressed: _onPvpTapped),
          const SizedBox(height: 12),
          AppTextField(
            controller: _gameCodeController,
            hint: appStrings.gameCode,
            fontWeight: AppFontWeight.enBold,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          GameButton(
            label: appStrings.joinPrivateGame,
            onPressed: _onJoinPrivateGameTapped,
          ),
          const SizedBox(height: 12),
          GameButton(
            label: appStrings.playerProfile,
            onPressed: _onPlayerProfileTapped,
          ),
          const SizedBox(height: 12),
          GameButton(label: appStrings.judge, onPressed: _onGameTapped),
          const SizedBox(height: 12),
          GameButton(label: appStrings.allInOne, onPressed: _onGameTapped),
          const SizedBox(height: 12),
          AppTextField(
            controller: _socialMediaIdController,
            hint: appStrings.socialMediaId,
            fontWeight: AppFontWeight.enBold,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          GameButton(
            label: appStrings.register,
            onPressed: isRegistering ? null : _onRegister,
          ),
          const SizedBox(height: 12),
          GameButton(
            label: appStrings.startHub,
            onPressed: isHubBusy ? null : _onStartHub,
          ),
          const SizedBox(height: 12),
          GameButton(
            label: appStrings.clearData,
            onPressed: _onClearData,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _onRegister() async {
    final appStrings = ref.read(appStringsProvider);
    await runApi(
      () async {
        final failure = await ref.read(authNotifierProvider.notifier).login(
              userName: DebugConfig.debugUserName,
              password: DebugConfig.debugPassword,
              socialMediaId: _socialMediaIdController.text.trim(),
            );
        if (failure != null) {
          return Result<bool>.failure(failure);
        }
        return Result.success(true);
      },
      onSuccess: (_) {
        showToast(appStrings.registerSuccess, type: ToastType.success);
      },
    );
  }

  Future<void> _onStartHub() async {
    final connected = await connectHub(showLoader: true);
    if (connected) {
      ref.read(playGameHubBindingsProvider).bindAll();
    }
  }

  Future<void> _onClearData() async {
    final appStrings = ref.read(appStringsProvider);
    await ref.read(signalRServiceProvider).disconnect();
    await ref.read(sharedPrefsProvider).clear();
    await ref.read(authNotifierProvider.notifier).logout();
    if (!mounted) {
      return;
    }
    showToast(appStrings.clearDataSuccess, type: ToastType.success);
  }

  Future<void> _onShowLoader() async {
    showLoader();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) {
      hideLoader();
    }
  }

  Future<void> _onShowConnectionLoader() async {
    showConnectionLoader();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) {
      hideConnectionLoader();
    }
  }

  Future<void> _onPlayTapped() => PlayGame.openWaiting(context);

  Future<void> _onPvpTapped() => PlayGame.openPrivateGame(
        context,
        interestIds: const [88],
      );

  // The join half of the private flow, next to the PvP button that creates
  // one. Same layer as every other button here: PlayGameEngineHost.
  // joinPrivateGame — what GameEngine.joinPrivateGame reaches a host through
  // — is this call, and the engine is not mounted in the debug launcher.
  Future<void> _onJoinPrivateGameTapped() async {
    final appStrings = ref.read(appStringsProvider);
    final code = _gameCodeController.text.trim();
    if (code.isEmpty) {
      showToast(appStrings.gameCodeRequired, type: ToastType.error);
      return;
    }
    await PlayGame.openPrivateGameByCode(context, gameCode: code);
  }

  Future<void> _onPlayerProfileTapped() =>
      PlayGame.openPlayerProfile(context, playerId: testPublicProfileId);

  void _onGameTapped() {
    final appStrings = ref.read(appStringsProvider);
    showToast(appStrings.pluginComingSoon);
    showAppSnackBar("message");
  }

  Future<void> _openLanguageSettings(AppStrings appStrings) async {
    final current = ref.read(appLanguageProvider);

    await showAppBottomSheet<void>(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextView(
            appStrings.language,
            fontWeight: AppFontWeight.semiBold,
            fontSize: 18,
          ),
          const SizedBox(height: 12),
          _LanguageTile(
            label: appStrings.englishName,
            selected: current == AppLanguage.english,
            onTap: () => _setLanguage(AppLanguage.english),
          ),
          _LanguageTile(
            label: appStrings.arabicName,
            selected: current == AppLanguage.arabic,
            onTap: () => _setLanguage(AppLanguage.arabic),
          ),
        ],
      ),
    );
  }

  Future<void> _setLanguage(String languageCode) async {
    // Close the sheet before the language change rebuilds MaterialApp — a
    // root-navigator rebuild while a pop is in flight trips NavigatorState's
    // !_debugLocked assertion.
    Navigator.of(context).pop();
    await ref.read(appLanguageProvider.notifier).setLanguage(languageCode);
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: AppTextView(
                label,
                fontWeight:
                    selected ? AppFontWeight.bold : AppFontWeight.regular,
              ),
            ),
            if (selected) const Icon(Icons.check),
          ],
        ),
      ),
    );
  }
}

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/play_game_strings.dart';
import '../../dialogs/setting_game_dialog.dart';

class FinishRoundScreen extends ConsumerStatefulWidget {
  const FinishRoundScreen({super.key});

  @override
  ConsumerState<FinishRoundScreen> createState() => _FinishRoundScreenState();
}

class _FinishRoundScreenState extends BaseState<FinishRoundScreen> {
  @override
  bool get handleInternetConnection => false;

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return Directionality(
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
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppLottieView.sandClock(
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 10),
                          // The screen is laid out RTL like every round;
                          // its title still reads in the app language's own
                          // direction, or English trailing punctuation lands
                          // on the wrong side.
                          Directionality(
                            textDirection: isArabic
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: AppTextView(
                              strings.readyGameTitle,
                              fontWeight: AppFontWeight.bold,
                              fontSize: 14,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerUi() {
    return SizedBox(
      height: 35,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GestureDetector(
          onTap: () => showAppDialog<void>(child: const SettingGameDialog()),
          child: const AppImageView(
            assetPath: AppAssets.settingsIcon,
            package: AppAssets.packageName,
            size: 20,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/play_game_strings.dart';

class SettingGameDialog extends ConsumerStatefulWidget {
  const SettingGameDialog({super.key});

  @override
  ConsumerState<SettingGameDialog> createState() =>
      _SettingGameDialogState();
}

class _SettingGameDialogState extends ConsumerState<SettingGameDialog> {
  static const _dividerColor = Color(0xFFECEAEA);
  static const _textColor = Color(0xFF454545);

  late bool _isSound;
  late bool _isMusic;

  @override
  void initState() {
    super.initState();
    final audio = ref.read(audioServiceProvider);
    _isSound = audio.isSfxEnabled;
    _isMusic = audio.isMusicEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final audio = ref.read(audioServiceProvider);

    return GameDialog(
      child: GameDialogCard(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toggleRowUi(
                    label: strings.soundEffects,
                    value: _isSound,
                    onChanged: (value) {
                      setState(() => _isSound = value);
                      audio.setSfxEnabled(value);
                    },
                  ),
                  _toggleRowUi(
                    label: strings.music,
                    value: _isMusic,
                    onChanged: (value) {
                      setState(() => _isMusic = value);
                      audio.setMusicEnabled(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(height: 1.5, color: _dividerColor),
                  const SizedBox(height: 16),
                  GameButton(
                    label: strings.save,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 10),
                  _exitGameUi(context, strings),
                ],
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: AppImageView(
                    assetPath: AppAssets.closeIcon,
                    package: AppAssets.packageName,
                    size: 18,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRowUi({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: AppTextView(
            label,
            fontWeight: AppFontWeight.bold,
            fontSize: 14,
            color: _textColor,
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.blue,
          inactiveTrackColor: AppColors.hint,
        ),
      ],
    );
  }

  Widget _exitGameUi(BuildContext context, PlayGameStrings strings) {
    return GestureDetector(
      onTap: () {
        // The dialog route is gone after the first pop, so the navigator is
        // captured here and the screen pop is left to the next frame rather
        // than re-entering routing from a deactivating context.
        final navigator = Navigator.of(context);
        navigator.pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigator.maybePop();
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.error),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppTextView(
          strings.exitTheGame,
          fontWeight: AppFontWeight.medium,
          fontSize: 14,
          color: AppColors.error,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

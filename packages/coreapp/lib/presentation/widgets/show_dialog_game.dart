import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_assets.dart';
import '../../constants/app_fonts.dart';
import '../providers/app_language_provider.dart';
import 'app_image_view.dart';
import 'app_text_view.dart';
import 'game_button.dart';
import 'game_dialog.dart';

// Message dialog — Android `border_dialog` card with optional title,
// subtitle, action button, and close icon when [isCancelable].
//
// Pops `true` on the action button, `false` on close.
class ShowDialogGame extends ConsumerWidget {
  const ShowDialogGame({
    super.key,
    this.title,
    this.subTitle,
    this.buttonText,
    this.isCancelable = true,
  });

  final String? title;
  final String? subTitle;
  final String? buttonText;
  final bool isCancelable;

  static const _titleColor = Color(0xFF454545);
  static const _closeSize = 34.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final resolvedTitle = title ?? '';
    final resolvedButton = buttonText ?? strings.confirm;
    final hasTitle = resolvedTitle.trim().isNotEmpty;
    final hasSubTitle = subTitle?.trim().isNotEmpty ?? false;
    final hasButton = resolvedButton.trim().isNotEmpty;

    return GameDialog(
      child: GameDialogCard(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: _closeSize),
                  if (hasTitle)
                    AppTextView(
                      resolvedTitle,
                      fontWeight: AppFontWeight.bold,
                      fontSize: 13,
                      color: _titleColor,
                      textAlign: TextAlign.center,
                    ),
                  if (hasTitle && hasSubTitle) const SizedBox(height: 2),
                  if (hasSubTitle)
                    AppTextView(
                      subTitle!,
                      fontWeight: AppFontWeight.regular,
                      fontSize: 12,
                      color: Colors.black,
                      textAlign: TextAlign.center,
                    ),
                  if (hasButton) ...[
                    const SizedBox(height: 16),
                    GameButton(
                      label: resolvedButton,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ],
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: Opacity(
                opacity: isCancelable ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !isCancelable,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showDialogGame(
  BuildContext context, {
  String? title,
  String? subTitle,
  String? buttonText,
  bool isCancelable = true,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ShowDialogGame(
      title: title,
      subTitle: subTitle,
      buttonText: buttonText,
      isCancelable: isCancelable,
    ),
  );
}

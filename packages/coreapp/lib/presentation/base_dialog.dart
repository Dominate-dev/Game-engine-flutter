import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_fonts.dart';
import 'providers/app_language_provider.dart';
import 'widgets/app_text_view.dart';
import 'widgets/app_throb.dart';

class BaseDialog extends StatelessWidget {
  const BaseDialog({
    super.key,
    this.title,
    required this.content,
    this.actions,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(20),
  });

  final String? title;
  final Widget content;
  final List<Widget>? actions;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: AppThrob(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                AppTextView(
                  title!,
                  fontWeight: AppFontWeight.semiBold,
                  fontSize: 22,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              content,
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ConfirmDialog extends ConsumerWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText,
    this.cancelText,
  });

  final String title;
  final String message;
  final String? confirmText;
  final String? cancelText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(appStringsProvider);

    return BaseDialog(
      title: title,
      content: AppTextView(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: AppTextView(cancelText ?? l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: AppTextView(
            confirmText ?? l10n.confirm,
            fontWeight: AppFontWeight.medium,
          ),
        ),
      ],
    );
  }
}

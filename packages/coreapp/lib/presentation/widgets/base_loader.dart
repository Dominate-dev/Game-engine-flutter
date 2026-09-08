import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_fonts.dart';
import 'app_text_view.dart';

class BaseLoader extends StatelessWidget {
  const BaseLoader({super.key, this.message});

  static const size = 48.0;

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(
          dismissible: false,
          color: AppColors.scrim,
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpinKitSpinningLines(
                color: AppColors.onBackground,
                size: size,
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                AppTextView(
                  message!,
                  fontWeight: AppFontWeight.medium,
                  color: AppColors.onBackground,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

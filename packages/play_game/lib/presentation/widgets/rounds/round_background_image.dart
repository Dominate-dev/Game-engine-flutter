import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';

class RoundBackgroundImage extends StatelessWidget {
  const RoundBackgroundImage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppImageView(
      assetPath: AppAssets.gameBackground,
      package: AppAssets.packageName,
      backgroundColor: AppColors.background,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      showSkeleton: false,
    );
  }
}

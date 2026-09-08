import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/profile/domain/entities/user_profile.dart';
import '../../../features/profile/presentation/providers/profile_providers.dart';
import '../../../l10n/play_game_strings.dart';

part 'player_profile_widgets.dart';

class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({super.key, this.playerId});

  final int? playerId;

  static Future<void> show(BuildContext context, {int? playerId}) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BaseSheet(
        padding: EdgeInsets.zero,
        showHandle: false,
        child: SizedBox(
          height: height,
          child: PlayerProfileScreen(playerId: playerId),
        ),
      ),
    );
  }

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends BaseState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  @override
  bool get handleInternetConnection => false;

  static const _headerHeight = 120.0;
  static const _headerRadius = 18.0;
  static const _avatarSize = 93.0;
  static const _avatarRingSize = 100.0;

  late final AnimationController _avatarThrob;
  late final Animation<double> _avatarScale;

  @override
  void initState() {
    super.initState();
    _avatarThrob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _avatarScale = Tween<double>(begin: 1, end: 1.2).animate(
      CurvedAnimation(parent: _avatarThrob, curve: Curves.easeInOut),
    );
    _avatarThrob.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _avatarThrob.reverse();
      }
    });
    _avatarThrob.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadProfile());
      }
    });
  }

  Future<void> _loadProfile() async {
    final id = widget.playerId;
    if (id == null || id == 0) {
      return;
    }
    ref.read(publicProfileProvider.notifier).state = null;
    await runApi(
      () => ref.read(getPublicProfileUseCaseProvider)(id),
      loading: LoadingType.none,
      onSuccess: (profile) {
        ref.read(publicProfileProvider.notifier).state = profile;
      },
    );
  }

  @override
  void dispose() {
    _avatarThrob.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));
    final profile = ref.watch(publicProfileProvider);

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: _sheetUi(strings, profile),
    );
  }

  Widget _sheetUi(PlayGameStrings strings, UserProfile? profile) {
    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            children: [
              _headerUi(profile),
              const SizedBox(height: 10),
              AppTextView(
                profile?.displayName ?? '',
                fontWeight: AppFontWeight.bold,
                fontSize: 15,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              _levelChipUi(profile),
              const SizedBox(height: 10),
              _statsUi(profile),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 15, 16, 0),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: AppColors.divider,
                ),
              ),
              const SizedBox(height: 15),
              AppTextView(
                strings.interests,
                fontWeight: AppFontWeight.bold,
                fontSize: 13,
              ),
              const SizedBox(height: 12),
              _interestsUi(profile),
              const SizedBox(height: 24),
            ],
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: AppImageView(
                assetPath: AppAssets.closeIcon,
                package: AppAssets.packageName,
                size: 18,
                color: AppColors.onBackground,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerUi(UserProfile? profile) {
    return SizedBox(
      height: _headerHeight + _avatarRingSize / 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(_headerRadius),
            ),
            child: AppImageView(
              imageUrl: profile?.backgroundImageUrl,
              width: double.infinity,
              height: _headerHeight,
              fit: BoxFit.cover,
              showSkeleton: true,
              radius: _headerRadius,
            ),
          ),
          Positioned(
            top: _headerHeight - _avatarRingSize / 2,
            child: _avatarUi(profile),
          ),
        ],
      ),
    );
  }

  Widget _avatarUi(UserProfile? profile) {
    return ScaleTransition(
      scale: _avatarScale,
      child: SizedBox(
        width: _avatarRingSize,
        height: _avatarRingSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const AppImageView(
              assetPath: AppAssets.avatarRing,
              package: AppAssets.packageName,
              size: _avatarRingSize,
              fit: BoxFit.contain,
            ),
            AppImageView(
              imageUrl: profile?.profileImageUrl,
              size: _avatarSize,
              isCircle: true,
              fit: BoxFit.cover,
            ),
          ],
        ),
      ),
    );
  }

  Widget _levelChipUi(UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppTextView(
        profile?.displayLevelTitle ?? '',
        fontWeight: AppFontWeight.regular,
        fontSize: 12,
      ),
    );
  }

  Widget _statsUi(UserProfile? profile) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: _StatPill(
                icon: AppAssets.diamondIcon,
                value: profile?.diamonds.toString() ?? '',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _StatPill(
                icon: AppAssets.coinIcon,
                value: profile?.coins.toString() ?? '',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _StatPill(
                icon: AppAssets.levelMaskIcon,
                value: profile?.displayXp ?? '',
                overlayText: profile?.displayLevel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _interestsUi(UserProfile? profile) {
    final interests = profile?.categories ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: interests.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          return _InterestTile(item: interests[index]);
        },
      ),
    );
  }
}

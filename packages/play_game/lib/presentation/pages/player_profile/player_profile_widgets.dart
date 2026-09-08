part of 'player_profile_screen.dart';

// The screen's two leaf widgets. Neither reads the screen's state —
// each takes what it draws as a constructor argument — so they sit
// here rather than inside the 300-line screen file. A part, not a
// separate library, so both stay private to the screen.

class _InterestTile extends StatelessWidget {
  const _InterestTile({required this.item});

  final ProfileInterest item;

  static const _size = 55.0;
  static const _iconSize = 35.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: item.isActive
            ? Center(
                child: AppImageView(
                  imageUrl: item.imageUrl,
                  size: _iconSize,
                  fit: BoxFit.contain,
                  showSkeleton: false,
                ),
              )
            : null,
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    this.overlayText,
  });

  final String icon;
  final String value;
  final String? overlayText;

  static const _iconSize = 25.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 10),
              child: Container(
                alignment: AlignmentDirectional.centerEnd,
                padding: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppColors.answerChip,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.statStroke),
                ),
                child: AppNumberTextView(
                  value,
                  fontWeight: AppFontWeight.enBold,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: _iconSize,
              height: _iconSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AppImageView(
                    assetPath: icon,
                    package: AppAssets.packageName,
                    size: _iconSize,
                    fit: BoxFit.contain,
                    showSkeleton: false,
                  ),
                  if (overlayText != null)
                    AppNumberTextView(
                      overlayText!,
                      fontWeight: AppFontWeight.enBold,
                      fontSize: 12,
                      color: Colors.black,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

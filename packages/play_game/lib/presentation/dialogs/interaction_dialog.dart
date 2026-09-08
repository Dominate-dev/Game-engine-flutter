import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/stickers/domain/entities/sticker_asset.dart';
import '../../features/stickers/presentation/providers/stickers_providers.dart';
import '../../l10n/play_game_strings.dart';
import '../game_controller/game_controller.dart';

class _InteractionItem {
  const _InteractionItem({
    required this.path,
    this.imageUrl,
    this.owned = true,
  });

  final String path;
  final String? imageUrl;
  final bool owned;
}

class _InteractionGroup {
  const _InteractionGroup({
    required this.name,
    required this.items,
    this.id = 0,
    this.owned = true,
    this.price = 0,
  });

  final int id;
  final String name;
  final List<_InteractionItem> items;
  final bool owned;
  final int price;
}

class InteractionDialog extends ConsumerStatefulWidget {
  const InteractionDialog({super.key});

  @override
  ConsumerState<InteractionDialog> createState() => _InteractionDialogState();
}

class _InteractionDialogState extends BaseState<InteractionDialog> {
  static const _grayColor = Color(0xFF9B9B9B);
  static const _listHeight = 300.0;

  late final PageController _pageController;
  bool _isBuying = false;
  int? _payingGroupId;

  @override
  bool get handleInternetConnection => false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(bool buying) {
    if (_isBuying == buying) {
      return;
    }
    _pageController.animateToPage(
      buying ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget buildPage(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);
    final catalog = ref.watch(stickerCatalogProvider);
    final ownedGroups =
        catalog?.owned.map(_groupFromAsset).toList() ?? const [];
    final buyingGroups =
        catalog?.buying.map(_groupFromAsset).toList() ?? const [];

    return GameDialog(
      child: GameDialogCard(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  _tabsUi(strings),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: _listHeight,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) =>
                          setState(() => _isBuying = index == 1),
                      children: [
                        _groupsListUi(strings, ownedGroups),
                        _groupsListUi(strings, buyingGroups),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
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

  Widget _tabsUi(PlayGameStrings strings) {
    return Container(
      height: 45,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blue),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _tabButtonUi(
              label: strings.owned,
              selected: !_isBuying,
              onTap: () => _selectTab(false),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _tabButtonUi(
              label: strings.buying,
              selected: _isBuying,
              onTap: () => _selectTab(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButtonUi({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AppTextView(
          label,
          fontWeight: AppFontWeight.bold,
          color: selected ? Colors.white : _grayColor,
        ),
      ),
    );
  }

  Widget _groupsListUi(
    PlayGameStrings strings,
    List<_InteractionGroup> groups,
  ) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _groupCardUi(strings, groups[index]),
    );
  }

  Widget _groupCardUi(PlayGameStrings strings, _InteractionGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextView(
                group.name,
                fontWeight: AppFontWeight.bold,
                fontSize: 12,
                color: AppColors.blue,
              ),
            ),
            if (!group.owned) ...[
              const AppImageView(
                assetPath: AppAssets.coinIcon,
                package: AppAssets.packageName,
                size: 13,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 5),
              AppNumberTextView(
                '${group.price}',
                fontSize: 11,
                color: AppColors.yellow,
              ),
              const SizedBox(width: 10),
              _buyButtonUi(strings, group),
            ],
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemBuilder: (context, index) => _itemTileUi(
            group.items[index],
            isLoading: _payingGroupId == group.id,
          ),
        ),
      ],
    );
  }

  Widget _buyButtonUi(PlayGameStrings strings, _InteractionGroup group) {
    final isPaying = _payingGroupId != null;
    return GestureDetector(
      onTap: isPaying ? null : () => _showBuyConfirm(strings, group.id),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AppTextView(
          strings.buy,
          fontWeight: AppFontWeight.medium,
          fontSize: 10,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _showBuyConfirm(PlayGameStrings strings, int groupId) async {
    final confirmed = await showDialogGame(
      context,
      title: strings.areYouSureYouWantToBuy,
      buttonText: strings.confirm,
    );
    if (confirmed != true || !mounted || groupId <= 0) {
      return;
    }

    setState(() => _payingGroupId = groupId);
    await runApi(
      () => ref.read(payStickerGroupUseCaseProvider)(groupId),
      loading: LoadingType.none,
      onSuccess: (_) => _refreshCatalog(),
    );
    if (mounted) {
      setState(() => _payingGroupId = null);
    }
  }

  Future<void> _refreshCatalog() async {
    await runApi(
      () => loadStickerCatalog(ref.read(getStickerGroupsUseCaseProvider)),
      loading: LoadingType.none,
      onSuccess: (catalog) {
        ref.read(stickerCatalogProvider.notifier).state = catalog;
      },
    );
  }

  Widget _itemTileUi(_InteractionItem item, {required bool isLoading}) {
    final tile = Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.blue),
          ),
          padding: const EdgeInsets.all(12),
          child: AppImageView(
            imageUrl: item.imageUrl,
            size: 55,
            fit: BoxFit.contain,
            showSkeleton: false,
            showLoader: !isLoading,
          ),
        ),
        if (isLoading)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
    if (!item.owned || isLoading) {
      return tile;
    }
    return GestureDetector(
      onTap: () => unawaited(_onItemTap(item)),
      child: tile,
    );
  }

  Future<void> _onItemTap(_InteractionItem item) async {
    Navigator.of(context).pop();
    final path = item.path.trim();
    if (path.isEmpty) {
      return;
    }
    await ref.read(gameControllerProvider.notifier).sendEmoji(path);
    if (mounted) {
      // it you want wait a to receive the emoji from the server before showing it in the game
    }
  }

  static _InteractionGroup _groupFromAsset(StickerAsset group) {
    final stickers = group.assets.isNotEmpty ? group.assets : [group];
    return _InteractionGroup(
      id: group.id,
      name: group.name,
      owned: group.owned,
      price: group.price,
      items: [
        for (final sticker in stickers)
          _InteractionItem(
            path: sticker.path,
            imageUrl: sticker.imageUrl,
            owned: sticker.owned || group.owned,
          ),
      ],
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/sticker_asset.dart';
import 'stickers_providers.dart';

// Paging3-style sticker groups list: first page on [refresh], next pages
// on [loadNext]. Not wired to a screen yet — watch this provider when ready.
final stickerGroupsPagingProvider = NotifierProvider.autoDispose<
    StickerGroupsPagingNotifier, StickerGroupsPagingState>(
  StickerGroupsPagingNotifier.new,
);

class StickerGroupsPagingNotifier
    extends AutoDisposeNotifier<StickerGroupsPagingState> {
  static const pageSize = 20;

  bool _canUse = false;

  @override
  StickerGroupsPagingState build() => const StickerGroupsPagingState();

  Future<void> refresh({bool canUse = false}) async {
    if (state.isLoading) {
      return;
    }
    _canUse = canUse;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      pageIndex: 0,
      clearFailure: true,
    );
    await _loadPage(pageIndex: 0, append: false);
  }

  Future<void> loadNext() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }
    state = state.copyWith(isLoadingMore: true, clearFailure: true);
    await _loadPage(pageIndex: state.pageIndex + 1, append: true);
  }

  Future<void> _loadPage({
    required int pageIndex,
    required bool append,
  }) async {
    final result = await ref.read(getStickerGroupsUseCaseProvider)(
      StickerFilterParams(
        canUse: _canUse,
        pageIndex: pageIndex,
        pageSize: pageSize,
      ),
    );

    result.when(
      success: (page) {
        state = state.copyWith(
          items: append ? [...state.items, ...page.items] : page.items,
          pageIndex: page.pageIndex,
          fullCount: page.fullCount,
          hasMore: page.hasMore,
          isLoading: false,
          isLoadingMore: false,
          clearFailure: true,
        );
      },
      failure: (failure) {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          failure: failure,
        );
      },
    );
  }
}

import 'package:coreapp/coreapp.dart';
import 'package:equatable/equatable.dart';

class StickerAsset extends Equatable {
  const StickerAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.price,
    required this.isActive,
    required this.type,
    required this.isUserOrderAssets,
    required this.canUse,
    this.assets = const [],
  });

  final int id;
  final String name;
  final String path;
  final int price;
  final bool isActive;
  final int type;
  final bool isUserOrderAssets;
  final bool canUse;
  final List<StickerAsset> assets;

  bool get owned => canUse || isUserOrderAssets;

  String? get imageUrl {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final http = AppUrl.httpOrNull(trimmed);
    if (http != null) {
      return http;
    }
    if (trimmed.startsWith('/')) {
      return '${ApiEndpoints.baseUrl}$trimmed';
    }
    return '${ApiEndpoints.baseUrl}/$trimmed';
  }

  @override
  List<Object?> get props => [id];
}

class StickerCatalog {
  const StickerCatalog({
    this.owned = const [],
    this.buying = const [],
  });

  final List<StickerAsset> owned;
  final List<StickerAsset> buying;
}

class StickerFilterParams extends Equatable {
  const StickerFilterParams({
    this.canUse = false,
    this.pageIndex = 0,
    this.pageSize = 20,
  });

  final bool canUse;
  final int pageIndex;
  final int pageSize;

  @override
  List<Object?> get props => [canUse, pageIndex, pageSize];
}

class StickerPage extends Equatable {
  const StickerPage({
    required this.items,
    required this.pageIndex,
    required this.pageSize,
    this.fullCount,
  });

  final List<StickerAsset> items;
  final int pageIndex;
  final int pageSize;
  final int? fullCount;

  bool get hasMore {
    if (fullCount != null) {
      return (pageIndex + 1) * pageSize < fullCount!;
    }
    return items.length >= pageSize;
  }

  @override
  List<Object?> get props => [items, pageIndex, pageSize, fullCount];
}

class StickerGroupsPagingState extends Equatable {
  const StickerGroupsPagingState({
    this.items = const [],
    this.pageIndex = 0,
    this.fullCount,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.failure,
  });

  final List<StickerAsset> items;
  final int pageIndex;
  final int? fullCount;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Failure? failure;

  StickerGroupsPagingState copyWith({
    List<StickerAsset>? items,
    int? pageIndex,
    int? fullCount,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return StickerGroupsPagingState(
      items: items ?? this.items,
      pageIndex: pageIndex ?? this.pageIndex,
      fullCount: fullCount ?? this.fullCount,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => [
        items,
        pageIndex,
        fullCount,
        isLoading,
        isLoadingMore,
        hasMore,
        failure,
      ];
}

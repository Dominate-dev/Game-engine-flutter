/// Play-specific REST paths. Shared auth stays in coreapp.
abstract final class PlayGameEndpoints {
  /// Backend path uses the historical typo "Porfile".
  static String publicProfile(int id) => '/api/Users/PublicPorfile/$id';

  /// Backend path uses the historical typo "Assetss".
  static const stickerGroupsFilter = '/api/Assetss/StickersGroups/Filter';

  static String payStickerGroup(int id) =>
      '/api/Assetss/StickersGroups/$id/Pay';

  /// Shareable invite link for a game code. Takes `type` and `code` as query
  /// parameters — see `GameRemoteDataSource.generateUrl`.
  static const generateUrl = '/api/Home/GenerateURL';
}

import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/profile/presentation/providers/profile_providers.dart';
import '../features/stickers/presentation/providers/stickers_paging_notifier.dart';
import '../features/stickers/presentation/providers/stickers_providers.dart';
import 'game_controller/game_controller_screen.dart';
import 'game_controller/play_game_hub_bindings.dart';
import 'pages/player_profile/player_profile_screen.dart';

/// A [MaterialPageRoute] that arrives already there.
///
/// For a host-driven entry the push is not a user gesture and nothing is on
/// screen to slide away from — the native side navigates to its Flutter
/// surface once the flow is ready, so the slide would only be a blank frame
/// with an animation over it. A user tapping Play in the debug launcher still
/// gets the normal transition; only the entries the host drives opt out.
class _NoTransitionPageRoute<T> extends MaterialPageRoute<T> {
  _NoTransitionPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

Route<void> _entryRoute(WidgetBuilder builder, {required bool animated}) =>
    animated
        ? MaterialPageRoute<void>(builder: builder)
        : _NoTransitionPageRoute<void>(builder: builder);

abstract final class PlayGame {
  /// Opens the public matchmaking flow.
  ///
  /// [animated] is false for host-driven entries — see [_NoTransitionPageRoute].
  /// The returned Future is `Navigator.push`'s, so it completes when the route
  /// is **popped**, not when it is shown; a caller that needs "it is on
  /// screen" must not await this (see `PlayGameEngineHost`).
  static Future<void> openWaiting(
    BuildContext context, {
    bool animated = true,
  }) {
    return Navigator.of(context).push<void>(
      _entryRoute((_) => const GameControllerScreen(), animated: animated),
    );
  }

  /// Creates a private (invite-code) game and opens its lobby.
  ///
  /// [interestIds] is the caller's — the native host supplies the real
  /// interest id, so nothing is defaulted here. The lobby runs inside
  /// [GameControllerScreen] like every other phase, which is what lets
  /// `GameStarted` / `GameRestore` hand straight over to the rounds.
  static Future<void> openPrivateGame(
    BuildContext context, {
    required List<int> interestIds,
    bool animated = true,
  }) {
    return Navigator.of(context).push<void>(
      _entryRoute(
        (_) => GameControllerScreen(privateInterestIds: interestIds),
        animated: animated,
      ),
    );
  }

  /// Joins an existing private game by its invite code and opens its lobby.
  ///
  /// [gameCode] is the caller's — wherever it came from (a code dialog, a
  /// deep link, a notification) and whether it belongs to this game type at
  /// all are the host's business. The engine sends it as given.
  ///
  /// Deliberately a separate entry from [openPrivateGame]: creating and
  /// joining are different hub methods, and collapsing them into one call
  /// with two optional arguments would make the invalid "both" case
  /// expressible.
  static Future<void> openPrivateGameByCode(
    BuildContext context, {
    required String gameCode,
    bool animated = true,
  }) {
    return Navigator.of(context).push<void>(
      _entryRoute(
        (_) => GameControllerScreen(privateGameCode: gameCode),
        animated: animated,
      ),
    );
  }

  static Future<void> openPlayerProfile(BuildContext context, {int? playerId}) {
    return PlayerProfileScreen.show(context, playerId: playerId);
  }

  /// Drops the launcher's own cached Play data.
  ///
  /// Deliberately **not** a game-exit path any more. It used to also invoke
  /// `LeaveGame('all')` and `ref.invalidate(gameControllerProvider)`, and the
  /// debug launcher calls it from `RouteAware.didPopNext()` — which Flutter
  /// fires while the popped route is still `_RouteLifecycle.popping`, i.e.
  /// with GameControllerScreen still mounted and still watching that
  /// provider. Invalidating it there rebuilt the dying screen into
  /// `GameSessionState.initial()` (phase `waiting`), which mounted a fresh
  /// WaitingScreen inside it and dispatched `JoinRandomGame` — queueing the
  /// player into a game they had just left. The `LeaveGame` was a duplicate
  /// of the one the exit path already sends.
  ///
  /// Both responsibilities now belong to the one exit owner
  /// (GameControllerScreen). A clean session for the next entry is still
  /// guaranteed without them: `gameControllerProvider` is autoDispose, so it
  /// is recreated once GameControllerScreen's subtree is unmounted — the
  /// primary guarantee `cross_game_reset_test.dart` already pins.
  static Future<void> clearGameData(WidgetRef ref) async {
    AppLogger.log('PlayGame — clear game data');
    ref.read(playGameHubBindingsProvider).lastEvent = null;
    ref.read(publicProfileProvider.notifier).state = null;
    ref.read(stickerCatalogProvider.notifier).state = null;
    ref.invalidate(stickerGroupsPagingProvider);
  }
}

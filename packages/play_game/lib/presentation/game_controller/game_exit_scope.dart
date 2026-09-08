/// The one owner of leaving the game and removing its route.
///
/// [GameControllerScreen] is the widget the game route was pushed with, so it
/// is the only thing that may remove it. Every other screen in the game — the
/// Waiting search, the public and private lobbies — is a *descendant* of that
/// one route, and each used to leave by calling `leaveGame()` and a bare
/// `Navigator.of(context).pop()` of its own, guarded by nothing but its own
/// private `_leaving` bool.
///
/// Two things went wrong with that:
///
///  * `Navigator.pop()` removes the topmost **present** route, not the
///    caller's own. `_RouteEntry.isPresent` is false once a route reaches
///    `_RouteLifecycle.popping`, so a second pop issued during the game
///    route's ~300ms exit transition skipped it and removed the screen
///    underneath — the host page — leaving an empty navigator and a black
///    screen.
///  * Independent `_leaving` flags cannot see each other, so two owners
///    reacting to the same moment (a back gesture and a hub event, say) each
///    believed it was the first.
///
/// Delegating through this scope makes the exit one-shot across every caller,
/// and keeps the pop with the route's owner. Nothing else about those screens
/// changes: the same `LeaveGame` goes out, at the same point, with the same
/// payload.
library;

import 'package:flutter/widgets.dart';

/// Handed down by [GameControllerScreen] to everything inside its route.
class GameExitScope extends InheritedWidget {
  const GameExitScope({
    super.key,
    required this.leave,
    required this.isLeaving,
    required super.child,
  });

  /// Leaves the game and removes the route, once.
  ///
  /// [dispatchLeaveGame] is false for the exits the server already knows
  /// about — a concluded game's result dialog, or a private join it refused —
  /// which is exactly the distinction those call sites already made.
  final void Function({bool dispatchLeaveGame}) leave;

  /// Whether an exit has already started. Callers that do more than pop (a
  /// toast, a dispatch) check this before doing that work.
  final bool Function() isLeaving;

  static GameExitScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameExitScope>();

  /// Whether an exit is already under way, for a context that may or may not
  /// be inside the scope. `false` when there is no scope — a screen mounted
  /// outside the game route (as some tests do) has no exit to be part of.
  static bool isLeavingOf(BuildContext context) =>
      maybeOf(context)?.isLeaving() ?? false;

  /// Leaves through the owner, or returns false when there is no owner to
  /// leave through — the caller then keeps whatever it did before.
  static bool leaveThrough(
    BuildContext context, {
    bool dispatchLeaveGame = true,
  }) {
    final scope = maybeOf(context);
    if (scope == null) {
      return false;
    }
    scope.leave(dispatchLeaveGame: dispatchLeaveGame);
    return true;
  }

  @override
  bool updateShouldNotify(GameExitScope oldWidget) =>
      leave != oldWidget.leave || isLeaving != oldWidget.isLeaving;
}

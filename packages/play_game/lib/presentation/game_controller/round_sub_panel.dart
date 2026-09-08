/// The round overlay layer — a [RoundLottieDialog] or [PlayerAnsweredDialog]
/// rendered *inside* the game page's own subtree instead of on a `DialogRoute`
/// of its own.
///
/// Why it exists: every dialog in this app is a route on the one root
/// Navigator, and a route's z-order is its position in the Navigator's
/// history. A round overlay pushed while another dialog is open therefore
/// landed on top of it, and there is no supported way to insert a route
/// *below* one already in the history (`replaceRouteBelow` would replace the
/// page itself, and an `Overlay.insert(below:)` entry is re-appended to the
/// top by `Overlay.rearrange` on the next route push or pop).
///
/// Rendering the overlay as a widget in the page subtree sidesteps the
/// ordering problem entirely: every `DialogRoute` is, structurally, above the
/// page route that hosts this layer. No ordering has to be maintained, so
/// nothing can invert it.
///
/// Only the two round informational overlays use this. Everything else —
/// the result, settings, interaction and confirmation dialogs — keeps the
/// normal dialog route, and their barriers stay authoritative over this layer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/player_answered_dialog.dart';
import '../dialogs/round_lottie_dialog.dart';

/// One showing overlay, identified by [token].
///
/// The token, not the widget, is what a dismissal names: two round overlays
/// can be equal widgets, and a timer that fires late must never close the
/// overlay that replaced its own.
@immutable
class RoundSubPanel {
  const RoundSubPanel({required this.token, required this.child});

  final int token;
  final Widget child;
}

/// Holds the overlay currently on screen, and the future the round-dialog
/// queue is waiting on.
///
/// The queue's contract is the only thing that matters here: `show` returns a
/// future that completes when the overlay leaves the screen, exactly as
/// `showDialog`'s did. `_enqueueRoundDialog` / `_roundDialogChain` are
/// untouched and cannot tell the difference.
class RoundSubPanelController extends AutoDisposeNotifier<RoundSubPanel?> {
  Completer<void>? _completer;
  int _nextToken = 0;

  @override
  RoundSubPanel? build() {
    ref.onDispose(_finish);
    return null;
  }

  /// Shows [child] and returns the future the caller awaits.
  Future<void> show(Widget child) {
    // The queue never asks for two at once, but an unqueued caller could:
    // release the previous waiter rather than leaving its future hanging
    // forever, which would stall the round's whole chain.
    _finish();
    final completer = Completer<void>();
    _completer = completer;
    state = RoundSubPanel(token: _nextToken++, child: child);
    return completer.future;
  }

  /// Removes the overlay [token] names, if it is still the one showing.
  void dismiss(int token) {
    if (state?.token != token) {
      return;
    }
    _finish();
    state = null;
  }

  void _finish() {
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

final roundSubPanelProvider =
    NotifierProvider.autoDispose<RoundSubPanelController, RoundSubPanel?>(
  RoundSubPanelController.new,
);

/// Hands the hosted overlay its own dismissal, so it never has to reach for
/// the Navigator to close itself.
class RoundSubPanelScope extends InheritedWidget {
  const RoundSubPanelScope({
    super.key,
    required this.dismiss,
    required super.child,
  });

  final VoidCallback dismiss;

  static VoidCallback? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RoundSubPanelScope>()
      ?.dismiss;

  @override
  bool updateShouldNotify(RoundSubPanelScope oldWidget) =>
      dismiss != oldWidget.dismiss;
}

/// The layer itself. Render it as the last child of the game page's stack.
///
/// It reproduces what the dialog route gave the overlay and nothing more: the
/// same `Colors.black54` scrim, and a barrier that swallows taps so the round
/// underneath stays untouchable while an overlay is up — the
/// `barrierDismissible: false` behaviour every round overlay already had. A
/// regular dialog opened on top brings its own barrier, which is above this
/// one and therefore stays the authoritative one.
class RoundSubPanelLayer extends ConsumerStatefulWidget {
  const RoundSubPanelLayer({super.key});

  /// Matches the Material dialog route's own entrance (`Curves.easeOut`).
  static const fadeDuration = Duration(milliseconds: 150);

  @override
  ConsumerState<RoundSubPanelLayer> createState() => _RoundSubPanelLayerState();
}

class _RoundSubPanelLayerState extends ConsumerState<RoundSubPanelLayer> {
  /// The page route hosting this layer, watched so the overlay leaves with
  /// it.
  ///
  /// A dialog route used to be removed by whatever popped the game screen —
  /// `popUntil` took it along. A sub-panel is not a route, so nothing pops it:
  /// this listener is what replaces that. The route's animation reverses the
  /// moment it is popped, which is the earliest signal available and lands in
  /// the same frame.
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) {
      return;
    }
    _route?.animation?.removeStatusListener(_onRouteStatusChanged);
    _route = route;
    _route?.animation?.addStatusListener(_onRouteStatusChanged);
  }

  void _onRouteStatusChanged(AnimationStatus status) {
    if (!mounted || _route?.isActive != false) {
      return;
    }
    // Completing rather than merely hiding: the queue is waiting on this
    // overlay's future, and everything still behind it in the chain then
    // resolves through the presenter's own canPresent guard — which is
    // already false for a route on its way out. Same outcome the forced pop
    // of a dialog route produced.
    final panel = ref.read(roundSubPanelProvider);
    if (panel != null) {
      ref.read(roundSubPanelProvider.notifier).dismiss(panel.token);
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_onRouteStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(roundSubPanelProvider);
    // A route on its way out takes its overlay with it, in the same frame the
    // pop happens — before the exit transition, not after it.
    if (panel == null || _route?.isActive == false) {
      return const SizedBox.shrink();
    }
    return RoundSubPanelScope(
      dismiss: () =>
          ref.read(roundSubPanelProvider.notifier).dismiss(panel.token),
      // Keyed by token so a replacement overlay gets a fresh State — its
      // auto-dismiss timer starts from the beginning, the way a new dialog
      // route's would.
      child: TweenAnimationBuilder<double>(
        key: ValueKey(panel.token),
        tween: Tween<double>(begin: 0, end: 1),
        duration: RoundSubPanelLayer.fadeDuration,
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: child,
        ),
        child: Stack(
          children: [
            const ModalBarrier(dismissible: false, color: Colors.black54),
            panel.child,
          ],
        ),
      ),
    );
  }
}

/// The presenter the round handlers are given in place of `showAppDialog`.
///
/// Routing is by widget type, deliberately: a handler can build either a
/// [RoundLottieDialog] or a `PlayerAnsweredDialog` for the same event (see
/// `onPlayerPassed`), so the decision cannot live at a call site. Deciding it
/// here also means no round overlay can be missed — there is one presenter,
/// and every handler receives it.
///
/// [canPresent] is the screen's own liveness check, the same one
/// `showAppDialog` applies before pushing a route: a dialog still queued
/// behind one already showing must resolve to nothing once the screen it
/// belongs to is on its way out, rather than orphaning itself onto whatever
/// replaced it. The sub-panel path has no Navigator to enforce that for it,
/// so the check is explicit here.
///
/// [fallback] is the screen's own `showAppDialog`, used unchanged for
/// everything that is not a round overlay.
Future<void> Function({required Widget child, bool barrierDismissible})
    roundDialogPresenter(
  WidgetRef ref, {
  required bool Function() canPresent,
  required Future<void> Function({
    required Widget child,
    bool barrierDismissible,
  }) fallback,
}) {
  return ({required Widget child, bool barrierDismissible = true}) {
    if (child is RoundLottieDialog || child is PlayerAnsweredDialog) {
      if (!canPresent()) {
        return Future<void>.value();
      }
      return ref.read(roundSubPanelProvider.notifier).show(child);
    }
    return fallback(child: child, barrierDismissible: barrierDismissible);
  };
}

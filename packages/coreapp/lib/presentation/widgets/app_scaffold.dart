import 'package:flutter/material.dart';

/// Shared screen scaffold — [SafeArea] + a body that scrolls instead of
/// overflowing, same building block for every screen.
///
/// [scrollable] (on by default) wraps [body] in a [SingleChildScrollView].
/// This is what stops the classic "A RenderFlex overflowed by N pixels"
/// (yellow/black stripes) error the instant the on-screen keyboard opens
/// behind a [TextField] sitting in a fixed-height [Column] — the body
/// scrolls out from under the keyboard instead of erroring.
///
/// Tapping anywhere outside a focused field also closes the keyboard (via
/// [dismissKeyboardOnTap], on by default) so opening one field and tapping
/// elsewhere doesn't leave the keyboard covering the UI.
///
/// Note: while [scrollable] is true, [body] must not rely on
/// [Expanded]/[Spacer] — they need a bounded height, which a scroll view
/// can't give them (`RenderFlex children have non-zero flex but incoming
/// height constraints are unbounded`). Use fixed gaps instead.
///
/// When [scrollable] is false (e.g. because [body] does use
/// [Expanded]/[Spacer]), [resizeToAvoidBottomInset] defaults to false
/// instead of Flutter's usual true — so the keyboard opening simply
/// overlays [body] instead of shrinking it, which is what actually causes
/// the overflow in a fixed, non-scrollable layout. Pass
/// `resizeToAvoidBottomInset: true` explicitly to opt back in if [body]
/// can genuinely shrink safely. As a last-resort safety net, [body] is
/// also wrapped in a [ClipRect] so even an unexpected overflow is clipped
/// silently instead of painting the yellow/black debug stripes.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.scrollable = true,
    this.safeArea = true,
    this.resizeToAvoidBottomInset,
    this.backgroundColor,
    this.padding = EdgeInsets.zero,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.drawer,
    this.endDrawer,
    this.dismissKeyboardOnTap = true,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    this.physics,
    this.scrollController,
    this.top = true,
    this.bottomSafeArea = true,
    this.left = true,
    this.right = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;

  /// Wraps [body] in a scroll view so it scrolls instead of overflowing
  /// when it doesn't fit (e.g. once the keyboard opens). Set false for
  /// screens that manage their own scrolling (e.g. a full-screen
  /// [ListView]) or that need [Expanded]/[Spacer] to fill the screen.
  final bool scrollable;

  final bool safeArea;

  /// Defaults to [scrollable] when null — see class doc for why.
  final bool? resizeToAvoidBottomInset;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final Widget? drawer;
  final Widget? endDrawer;

  final bool dismissKeyboardOnTap;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final ScrollPhysics? physics;
  final ScrollController? scrollController;

  final bool top;
  final bool bottomSafeArea;
  final bool left;
  final bool right;

  @override
  Widget build(BuildContext context) {
    Widget content = padding == EdgeInsets.zero
        ? body
        : Padding(padding: padding, child: body);

    if (scrollable) {
      content = SingleChildScrollView(
        controller: scrollController,
        keyboardDismissBehavior: keyboardDismissBehavior,
        physics: physics ?? const ClampingScrollPhysics(),
        child: content,
      );
    }

    if (safeArea) {
      content = SafeArea(
        top: top,
        bottom: bottomSafeArea,
        left: left,
        right: right,
        child: content,
      );
    }

    final scaffold = Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset ?? scrollable,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      bottomSheet: bottomSheet,
      drawer: drawer,
      endDrawer: endDrawer,
      // Safety net: clips away the debug overflow indicator (yellow/black
      // stripes) instead of letting it paint if body somehow doesn't fit.
      body: ClipRect(child: content),
    );

    if (!dismissKeyboardOnTap) {
      return scaffold;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: scaffold,
    );
  }
}

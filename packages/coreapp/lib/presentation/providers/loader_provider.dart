import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the global loader overlay — see [LoaderOverlay] +
/// [BaseLoader] in `presentation/widgets/`.
class LoaderState {
  const LoaderState({this.isVisible = false, this.message});

  final bool isVisible;
  final String? message;

  static const hidden = LoaderState();
}

/// Reference-counted so nested/concurrent `showLoader()` calls (e.g. two
/// API calls in flight at once) don't let the first `hideLoader()` hide it
/// out from under the second one still in progress.
class LoaderVisibilityNotifier extends Notifier<LoaderState> {
  int _count = 0;

  @override
  LoaderState build() => LoaderState.hidden;

  void show({String? message}) {
    _count++;
    state = LoaderState(isVisible: true, message: message);
  }

  void hide() {
    if (_count > 0) {
      _count--;
    }
    if (_count == 0) {
      state = LoaderState.hidden;
    }
  }

  /// Escape hatch — clears the count and hides immediately regardless of
  /// how many `show()` calls are outstanding. Use sparingly (e.g. on a
  /// hard navigation reset).
  void forceHide() {
    _count = 0;
    state = LoaderState.hidden;
  }
}

/// Every screen shows/hides this through [BaseState.showLoader] /
/// [BaseState.hideLoader] — never watch/mutate it directly from a game
/// screen, go through those helpers so the reference-counting stays
/// correct.
final loaderVisibleProvider =
    NotifierProvider<LoaderVisibilityNotifier, LoaderState>(
  LoaderVisibilityNotifier.new,
);

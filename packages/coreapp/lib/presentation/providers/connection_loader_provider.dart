import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loader_provider.dart';

// Separate from [loaderVisibleProvider] so API work and reconnect UI
// never hide each other.
final connectionLoaderVisibleProvider =
    NotifierProvider<LoaderVisibilityNotifier, LoaderState>(
  LoaderVisibilityNotifier.new,
);

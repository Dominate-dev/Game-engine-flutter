import 'package:flutter/widgets.dart';

void postFrame(State state, VoidCallback callback) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    callback();
  });
}

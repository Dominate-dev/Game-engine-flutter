import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_info.dart';

final networkInfoProvider = Provider<NetworkInfo>((ref) {
  final networkInfo = NetworkInfo();
  ref.onDispose(networkInfo.dispose);
  return networkInfo;
});

final hasInternetProvider = StreamProvider<bool>((ref) {
  final networkInfo = ref.watch(networkInfoProvider);
  return Stream<bool>.multi((listener) {
    listener.add(networkInfo.isOnline);
    final subscription = networkInfo.onStatusChange.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = subscription.cancel;
  });
});

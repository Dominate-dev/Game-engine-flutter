import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../network/network_info_provider.dart';
import 'signalr_service.dart';
import 'signalr_status.dart';

final signalRServiceProvider = Provider<SignalRService>((ref) {
  final headersBuilder = ref.watch(apiHeadersBuilderProvider);
  final networkInfo = ref.watch(networkInfoProvider);
  final service = SignalRService(
    headersBuilder: headersBuilder,
    networkInfo: networkInfo,
    // P1a: same shared refresher the REST interceptor uses. Read lazily —
    // only on an actual hub 401 — so this provider does not depend on the
    // API client at build time.
    obtainRefreshedAccessToken: () => ref.read(authTokenRefresherProvider)(),
  );

  StreamSubscription<bool>? subscription;
  subscription = networkInfo.onStatusChange.listen(
    service.onInternetStatusChanged,
  );

  ref.onDispose(() async {
    await subscription?.cancel();
    await service.dispose();
  });

  return service;
});

final signalRStatusProvider = StreamProvider<SignalRStatus>((ref) {
  final service = ref.watch(signalRServiceProvider);
  return service.statusStream;
});

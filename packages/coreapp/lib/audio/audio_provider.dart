import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import 'audio_service.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService(prefs: ref.watch(sharedPrefsProvider));
  ref.onDispose(service.dispose);
  return service;
});

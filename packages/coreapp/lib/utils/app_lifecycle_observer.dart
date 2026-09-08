import 'package:flutter/widgets.dart';

import '../signalr/signalr_service.dart';

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver(this._signalRService);

  final SignalRService _signalRService;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _signalRService.onAppResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _signalRService.onAppPaused();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

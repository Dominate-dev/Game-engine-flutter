import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// How a host-initiated leave reaches the game's single exit owner.
//
// GameControllerScreen publishes its own `_exitGame` here while it is mounted
// and clears it on the way out. The public engine reads it to answer "is a
// game active" and to leave — without a BuildContext, without a Navigator
// lookup, and without seeing GameController or GameSessionState.
//
// A plain object behind a Provider, not provider *state*: registering and
// clearing happen in initState/dispose, and Riverpod forbids writing provider
// state in either. Mutating a field on an object the provider hands out is
// not a provider write. Nothing watches this — the engine reads it on demand
// — so there is nothing to notify either.
typedef GameLeaveRequest = void Function({bool dispatchLeaveGame});

final gameSessionHandleProvider = Provider<GameSessionHandle>((ref) {
  final handle = GameSessionHandle();
  ref.onDispose(handle.dispose);
  return handle;
});

class GameSessionHandle {
  GameLeaveRequest? _leave;

  // Exits, on their way out to the public engine. Broadcast, so the engine and
  // any Flutter-side glue can both listen; it carries nothing, because what
  // crosses here is "the game surface is gone", not game state.
  final _exits = StreamController<void>.broadcast();

  Stream<void> get onGameExited => _exits.stream;

  bool get isGameActive => _leave != null;

  void register(GameLeaveRequest leave) => _leave = leave;

  // Only the screen that registered may clear it, so one tearing down after
  // its replacement has registered cannot clear the new one. Compared with
  // `==`, not `identical`: Dart guarantees equality for instance method
  // tear-offs of the same method on the same receiver, not identity.
  void unregister(GameLeaveRequest leave) {
    if (_leave == leave) {
      _leave = null;
    }
  }

  // Returns whether a game was there to leave.
  bool leave({bool dispatchLeaveGame = true}) {
    final request = _leave;
    if (request == null) {
      return false;
    }
    request(dispatchLeaveGame: dispatchLeaveGame);
    return true;
  }

  // Called by the single exit owner — GameControllerScreen._exitGame — once
  // the game route has actually been removed. Deliberately not called from
  // [leave]: a host-initiated leave funnels into that same owner, and emitting
  // here as well would report one exit twice.
  void notifyExited() {
    if (_exits.isClosed) {
      return;
    }
    _exits.add(null);
  }

  void dispose() => unawaited(_exits.close());
}

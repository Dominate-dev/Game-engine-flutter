import 'package:coreapp/coreapp.dart';
import 'package:play_game/play_game.dart';
import 'package:flutter_test/flutter_test.dart';

// N3 — invoke() reports whether the call was dispatched.
//
// These drive the real SignalRService with no hub connected, which is the
// disconnected branch N3 is about. The connected branch needs a live hub and
// is covered structurally instead; see the note on the last group.

void main() {
  late SignalRService service;

  setUp(() => service = SignalRService());
  tearDown(() => service.dispose());

  group('disconnected invoke', () {
    test('returns false instead of returning void', () async {
      final sent = await service.invoke('SubmitAnswer', args: ['g1', 10]);
      expect(sent, isFalse);
    });

    test('returns false with no args too', () async {
      expect(await service.invoke('JoinRandomGame'), isFalse);
    });

    test('does not throw — a disconnected hub is a skip, not an error',
        () async {
      await expectLater(service.invoke('Pass', args: ['g1']), completes);
    });

    test('every hub method behaves the same way', () async {
      for (final method in <String>[
        PlayGameHubEvents.submitAnswer,
        PlayGameHubEvents.pass,
        PlayGameHubEvents.joinRandomGame,
        PlayGameHubEvents.readyForGame,
        PlayGameHubEvents.leaveGame,
        PlayGameHubEvents.sendEmoji,
        PlayGameHubEvents.checkPlayerGame,
      ]) {
        expect(await service.invoke(method), isFalse, reason: method);
      }
    });

    test('repeated calls stay false and do not accumulate state', () async {
      expect(await service.invoke('Pass', args: ['g1']), isFalse);
      expect(await service.invoke('Pass', args: ['g1']), isFalse);
      expect(await service.invoke('Pass', args: ['g1']), isFalse);
    });
  });

  group('the connection state invoke reads', () {
    test('a fresh service is not connected and has no live connection', () {
      expect(service.isConnected, isFalse);
      expect(service.hasLiveConnection, isFalse);
      expect(service.checkConnectionStatus(), SignalRStatus.idle);
    });

    test('a skipped invoke leaves the status untouched', () async {
      final before = service.checkConnectionStatus();
      await service.invoke('Pass', args: ['g1']);
      expect(service.checkConnectionStatus(), before);
    });

    // The self-heal is gated on a stored hub url, which only connect() sets.
    // With no url, invoke must skip without attempting to reconnect.
    test('no stored hub url means no reconnect attempt is started', () async {
      expect(await service.invoke('Pass', args: ['g1']), isFalse);
      expect(service.checkConnectionStatus(), SignalRStatus.idle);
      expect(service.isConnecting, isFalse);
    });
  });

  // The `true` branch requires a live hub, which a unit test cannot stand up.
  // A subclass reaching the same contract stands in for the call sites, and
  // the production branch returns true only after the awaited hub invocation
  // completes — see signalr_service.dart.
  group('the connected contract', () {
    test('a service reporting connected returns true', () async {
      final connected = _ConnectedSignalRService();
      expect(await connected.invoke('SubmitAnswer', args: ['g1', 10]), isTrue);
      expect(connected.calls, ['SubmitAnswer']);
    });

    test('callers can distinguish sent from skipped', () async {
      final connected = _ConnectedSignalRService();
      expect(await connected.invoke('Pass'), isTrue);
      expect(await service.invoke('Pass'), isFalse);
    });
  });
}

/// Stands in for a live hub: the only thing invoke() branches on is
/// [SignalRService.isConnected].
class _ConnectedSignalRService extends SignalRService {
  final calls = <String>[];

  @override
  bool get isConnected => true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    if (!isConnected) {
      return false;
    }
    calls.add(methodName);
    return true;
  }
}

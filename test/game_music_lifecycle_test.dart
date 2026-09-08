import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The round music showRoundIntro starts has no stop of its own — the lobby
// and waiting screens stop theirs in dispose, the rounds never did, so it
// carried on after the game ended or the player left.
//
// GameControllerScreen now stops it at both ends of the lifecycle: when the
// result lands, and on any exit. Music only — stopMusic touches the music
// player alone, so the win/loss SFX still play over the silence.

const _localId = '47';
const _opponentId = '211403';

typedef HubHandler = void Function(List<Object?>?);

class _FiringSignalRService extends SignalRService {
  final _handlers = <String, List<HubHandler>>{};

  @override
  bool get isConnected => true;

  @override
  bool get hasLiveConnection => true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    final list = _handlers.putIfAbsent(eventName, () => []);
    list.add(handler);
    return () => list.remove(handler);
  }

  @override
  void reattachEventHandlers() {}

  void fire(String eventName, [List<Object?>? args]) {
    for (final handler
        in List.of(_handlers[eventName] ?? const <HubHandler>[])) {
      handler(args);
    }
  }
}

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast();

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(const StickerPage(items: [], pageIndex: 0, pageSize: 20));

  @override
  Future<Result<bool>> payStickerGroup(int id) async => Result.success(true);
}

class _FakeNetworkInfo implements NetworkInfo {
  @override
  bool get isOnline => true;
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();
  @override
  void dispose() {}
}

/// Records what was started and what was stopped, keeping music and SFX
/// apart — the whole point is that stopping one leaves the other alone.
class _RecordingAudioService extends AudioService {
  final musicStarted = <String>[];
  final sfxPlayed = <String>[];

  /// Every stop(), with the type it named. A null entry is "stop everything",
  /// which would take the dialog SFX down with the music.
  final stops = <AudioSourceType?>[];

  int get musicStops =>
      stops.where((t) => t == AudioSourceType.music).length;

  int get untypedStops => stops.where((t) => t == null).length;

  int get sfxStops => stops.where((t) => t == AudioSourceType.sfx).length;

  @override
  Future<void> start(
    String asset, {
    AudioSourceType type = AudioSourceType.sfx,
    String? package,
    bool? loop,
    double? volume,
  }) async {
    if (type == AudioSourceType.music) {
      musicStarted.add(asset);
    } else {
      sfxPlayed.add(asset);
    }
  }

  @override
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {
    musicStarted.add(asset);
  }

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {
    sfxPlayed.add(asset);
  }

  @override
  Future<void> stop({AudioSourceType? type}) async {
    stops.add(type);
  }

  @override
  Future<void> stopMusic() async {
    stops.add(AudioSourceType.music);
  }

  @override
  Future<void> dispose() async {}
}

class _HostPage extends ConsumerStatefulWidget {
  const _HostPage();

  @override
  ConsumerState<_HostPage> createState() => _HostPageState();
}

class _HostPageState extends ConsumerState<_HostPage> {
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('home')),
      );
}

Map<String, dynamic> _roundGame() => {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q1',
        'textEn': 'q1',
        'questionNumber': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

Map<String, dynamic> _gameOver({required bool iWin}) => {
      'id': 'g1',
      'status': 4,
      'type': 1,
      'winnerId': iWin ? _localId : _opponentId,
      'gameResultPlayers': [
        {'playerId': _localId, 'points': iWin ? 3 : 1},
        {'playerId': _opponentId, 'points': iWin ? 1 : 3},
      ],
    };

void main() {
  late ProviderContainer container;
  late _FiringSignalRService signalR;
  late _FakeHubBindings bindings;
  late _RecordingAudioService audio;
  late GlobalKey<NavigatorState> navigatorKey;

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FiringSignalRService();
    bindings = _FakeHubBindings(signalR);
    audio = _RecordingAudioService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
        stickersRepositoryProvider.overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(audio),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        signalRStatusProvider.overrideWith(
          (ref) => Stream<SignalRStatus>.value(SignalRStatus.connected),
        ),
      ],
    );
    addTearDown(container.dispose);

    navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const _HostPage(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Enters the game and drives it into a round, so the intro has started
  /// the looping round music.
  Future<void> enterRound(WidgetTester tester) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
    await tester.pump();
    // The intro overlay runs 2000ms and showRoundIntro only starts the loop
    // once the dialog chain behind it has drained.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  }

  Future<void> backAndConfirm(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final strings = PlayGameStrings.forLanguage(AppLanguage.english);
    final button = find.widgetWithText(GameButton, strings.exitTheGame);
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  group('the round music starts as it always did', () {
    testWidgets('the intro starts it', (tester) async {
      await pumpHome(tester);
      await enterRound(tester);

      expect(audio.musicStarted, contains(AppSounds.musicRunning),
          reason: 'sanity: showRoundIntro still starts the loop');
      expect(audio.musicStarted.last, AppSounds.musicRunning,
          reason: 'and it is the loop still playing when the round begins — '
              'WaitingScreen.dispose stops its own lobby track on the way '
              'out, which is unchanged and happens before this');
    });
  });

  group('Back / Exit stops the music', () {
    testWidgets('leaving stops it exactly once, music only', (tester) async {
      await pumpHome(tester);
      await enterRound(tester);
      audio.stops.clear();

      await backAndConfirm(tester);

      expect(audio.musicStops, 1);
      expect(audio.untypedStops, 0,
          reason: 'an untyped stop would take the dialog SFX with it');
      expect(audio.sfxStops, 0);
    });

    testWidgets('a second exit attempt does not stop again', (tester) async {
      await pumpHome(tester);
      await enterRound(tester);
      audio.stops.clear();

      await backAndConfirm(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(audio.musicStops, 1, reason: 'one-shot');
    });
  });

  group('the game finishing stops the music', () {
    testWidgets('a win stops it, and the win SFX still plays',
        (tester) async {
      await pumpHome(tester);
      await enterRound(tester);
      audio.stops.clear();
      audio.sfxPlayed.clear();

      bindings.emit(PlayGameHubEvents.gameOver, _gameOver(iWin: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(audio.musicStops, 1, reason: 'stopped when the result landed');
      expect(audio.untypedStops, 0);
      expect(audio.sfxPlayed, contains(AppSounds.winningGame),
          reason: 'the result SFX is unaffected by stopping the music');
    });

    testWidgets('a loss stops it, and the loss SFX still plays',
        (tester) async {
      await pumpHome(tester);
      await enterRound(tester);
      audio.stops.clear();
      audio.sfxPlayed.clear();

      bindings.emit(PlayGameHubEvents.gameOver, _gameOver(iWin: false));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(audio.musicStops, 1);
      expect(audio.sfxPlayed, contains(AppSounds.losingGame));
    });

    testWidgets('the music is stopped before the result dialog is dismissed',
        (tester) async {
      await pumpHome(tester);
      await enterRound(tester);
      audio.stops.clear();

      bindings.emit(PlayGameHubEvents.gameFinished, _gameOver(iWin: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(audio.musicStops, 1,
          reason: 'not deferred to the return-to-home pop');
    });

    testWidgets('finishing then leaving still stops only once',
        (tester) async {
      await pumpHome(tester);
      await enterRound(tester);
      audio.stops.clear();

      bindings.emit(PlayGameHubEvents.gameOver, _gameOver(iWin: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await backAndConfirm(tester);

      expect(audio.musicStops, 1,
          reason: 'the result stop already ran; the exit must not repeat it');
    });
  });

  group('dialog SFX are never stopped', () {
    testWidgets('no code path issues an sfx or untyped stop', (tester) async {
      await pumpHome(tester);
      await enterRound(tester);

      bindings.emit(PlayGameHubEvents.gameOver, _gameOver(iWin: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await backAndConfirm(tester);

      expect(audio.sfxStops, 0);
      expect(audio.untypedStops, 0);
      expect(
        audio.stops.every((t) => t == AudioSourceType.music),
        isTrue,
        reason: 'every stop in the game lifecycle is music-only',
      );
    });
  });
}

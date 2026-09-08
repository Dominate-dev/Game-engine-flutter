import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../constants/app_sounds.dart';
import '../storage/prefs_keys.dart';
import '../storage/shared_prefs_service.dart';
import '../utils/app_logger.dart';
import 'audio_source_type.dart';

/// Global audio handler for music and sound effects.
///
/// Get it from Riverpod, or via [AudioService.instance] after the first read:
///
/// ```dart
/// final audio = ref.read(audioServiceProvider);
///
/// await audio.start(AppSounds.rightAnswer);
/// await audio.start(AppSounds.musicRunning, type: AudioSourceType.music);
///
/// await audio.pause();
/// await audio.resume();
/// await audio.stop();
/// ```
class AudioService with WidgetsBindingObserver {
  AudioService({SharedPrefsService? prefs}) : _prefs = prefs {
    _sfxEnabled = _prefs?.getBool(PrefsKeys.soundEnabled) ?? true;
    _musicEnabled = _prefs?.getBool(PrefsKeys.musicEnabled) ?? true;
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
  }

  static AudioService? _instance;

  /// Set once [audioServiceProvider] (or this constructor) has run.
  static AudioService get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        'AudioService is not ready. Read audioServiceProvider first.',
      );
    }
    return current;
  }

  static const _sfxPoolSize = 4;
  static const _logName = AppLogger.audio;

  final SharedPrefsService? _prefs;

  final AudioPlayer _musicPlayer = AudioPlayer(handleInterruptions: false);
  final List<AudioPlayer> _sfxPlayers = List<AudioPlayer>.generate(
    _sfxPoolSize,
    (_) => AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    ),
  );

  int _nextSfxIndex = 0;
  int _musicGeneration = 0;

  String? _currentMusicAsset;
  String? _currentMusicPackage;
  bool _currentMusicLoop = true;
  double? _currentMusicVolume;

  bool _sfxEnabled = true;
  bool _musicEnabled = true;
  double _sfxVolume = 1;
  double _musicVolume = 0.5;

  bool _musicPausedByUser = false;
  bool _pausedByLifecycle = false;
  bool _disposed = false;

  bool get isSfxEnabled => _sfxEnabled;
  bool get isMusicEnabled => _musicEnabled;
  double get sfxVolume => _sfxVolume;
  double get musicVolume => _musicVolume;
  bool get isMusicPlaying => _musicPlayer.playing;
  bool get isMusicPaused =>
      _currentMusicAsset != null && !_musicPlayer.playing;
  String? get currentMusicAsset => _currentMusicAsset;

  /// Starts a sound. Music replaces the current track; SFX can overlap.
  Future<void> start(
    String asset, {
    AudioSourceType type = AudioSourceType.sfx,
    String? package,
    bool? loop,
    double? volume,
  }) {
    return switch (type) {
      AudioSourceType.music => playMusic(
          asset,
          package: package,
          loop: loop ?? true,
          volume: volume,
        ),
      AudioSourceType.sfx => playSfx(
          asset,
          package: package,
          volume: volume,
        ),
    };
  }

  /// Pauses music. Short SFX are left to finish.
  Future<void> pause({AudioSourceType? type}) async {
    if (type == AudioSourceType.sfx) {
      await _pauseSfx();
      return;
    }
    await pauseMusic();
  }

  /// Resumes music that was paused by [pause] or by leaving the app.
  Future<void> resume({AudioSourceType? type}) async {
    if (type == AudioSourceType.sfx) {
      return;
    }
    await resumeMusic();
  }

  /// Stops music, SFX, or both (when [type] is omitted).
  Future<void> stop({AudioSourceType? type}) async {
    if (type == null || type == AudioSourceType.music) {
      await stopMusic();
    }
    if (type == null || type == AudioSourceType.sfx) {
      await stopSfx();
    }
  }

  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {
    if (_disposed) {
      return;
    }

    final resolvedPackage = _resolvePackage(package);
    if (_currentMusicAsset == asset &&
        _currentMusicPackage == resolvedPackage &&
        _currentMusicLoop == loop &&
        _musicPlayer.playing) {
      return;
    }

    _currentMusicAsset = asset;
    _currentMusicPackage = resolvedPackage;
    _currentMusicLoop = loop;
    _currentMusicVolume = volume;
    _musicPausedByUser = false;

    if (!_musicEnabled) {
      return;
    }

    final generation = ++_musicGeneration;
    try {
      await _musicPlayer.setVolume(volume ?? _musicVolume);
      await _musicPlayer.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await _musicPlayer.setAudioSource(
        AudioSource.asset(asset, package: resolvedPackage),
      );
      if (_disposed || generation != _musicGeneration) {
        return;
      }
      await _musicPlayer.play();
    } catch (error) {
      AppLogger.log('playMusic failed — $error', name: _logName);
    }
  }

  Future<void> pauseMusic() async {
    if (_disposed || _currentMusicAsset == null) {
      return;
    }
    _musicPausedByUser = true;
    await _safe(() => _musicPlayer.pause());
  }

  Future<void> resumeMusic() async {
    if (_disposed || !_musicEnabled || _currentMusicAsset == null) {
      return;
    }
    _musicPausedByUser = false;
    if (_musicPlayer.audioSource == null) {
      await playMusic(
        _currentMusicAsset!,
        package: _currentMusicPackage,
        loop: _currentMusicLoop,
        volume: _currentMusicVolume,
      );
      return;
    }
    await _safe(() => _musicPlayer.play());
  }

  Future<void> stopMusic() async {
    _musicGeneration++;
    _currentMusicAsset = null;
    _currentMusicPackage = null;
    _currentMusicVolume = null;
    _musicPausedByUser = false;
    await _safe(() => _musicPlayer.stop());
  }

  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {
    if (_disposed || !_sfxEnabled) {
      return;
    }

    final player = _sfxPlayers[_nextSfxIndex];
    _nextSfxIndex = (_nextSfxIndex + 1) % _sfxPlayers.length;

    try {
      await player.setVolume(volume ?? _sfxVolume);
      await player.setLoopMode(LoopMode.off);
      await player.setAudioSource(
        AudioSource.asset(asset, package: _resolvePackage(package)),
      );
      if (_disposed) {
        return;
      }
      await player.play();
    } catch (error) {
      AppLogger.log('playSfx failed — $error', name: _logName);
    }
  }

  Future<void> stopSfx() async {
    await Future.wait(_sfxPlayers.map((player) => _safe(player.stop)));
  }

  Future<void> setSfxEnabled(bool enabled) async {
    _sfxEnabled = enabled;
    await _prefs?.setBool(PrefsKeys.soundEnabled, enabled);
    if (!enabled) {
      await stopSfx();
    }
  }

  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;
    await _prefs?.setBool(PrefsKeys.musicEnabled, enabled);
    if (!enabled) {
      await _safe(() => _musicPlayer.pause());
      return;
    }
    if (_currentMusicAsset != null && !_musicPausedByUser) {
      await resumeMusic();
    }
  }

  Future<void> setSfxVolume(double volume) async {
    _sfxVolume = volume.clamp(0.0, 1.0);
    await Future.wait(
      _sfxPlayers.map((player) => _safe(() => player.setVolume(_sfxVolume))),
    );
  }

  Future<void> setMusicVolume(double volume) async {
    _musicVolume = volume.clamp(0.0, 1.0);
    await _safe(() => _musicPlayer.setVolume(_musicVolume));
  }

  Future<void> startRunningMusic() => playMusic(AppSounds.musicRunning);

  Future<void> startLobbyMusic() => playMusic(AppSounds.waitingInLobby);

  Future<void> startSuddenDeathLobby() => playMusic(AppSounds.sdWaitingLobby);

  Future<void> playAnswerClick() => playSfx(AppSounds.answerClickChoice);

  Future<void> playBellRound() => playSfx(AppSounds.bellRound);

  Future<void> playCollectingRewards() =>
      playSfx(AppSounds.collectingRewardsSd);

  Future<void> playExitTheGame() => playSfx(AppSounds.exitTheGame);

  Future<void> playGetStrike() => playSfx(AppSounds.getStrike);

  Future<void> playLosingGame() => playSfx(AppSounds.losingGame);

  Future<void> playMinor() => playSfx(AppSounds.minor);

  Future<void> playPass() => playSfx(AppSounds.pass);

  Future<void> playRaisingLevel() => playSfx(AppSounds.raisingLevel);

  Future<void> playRightAnswer() => playSfx(AppSounds.rightAnswer);

  Future<void> playStartRound() => playSfx(AppSounds.startRound);

  Future<void> playStartTime() => playSfx(AppSounds.startTime);

  Future<void> playStartingGamerTurn() => playSfx(AppSounds.startingGamerTurn);

  Future<void> playTimeOver() => playSfx(AppSounds.timeOver);

  Future<void> playWinningGame() => playSfx(AppSounds.winningGame);

  Future<void> playWrongAnswer() => playSfx(AppSounds.wrongAnswer);

  Future<void> playYouFaster() => playSfx(AppSounds.youFaster);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(onAppResumed());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(onAppPaused());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> onAppPaused() async {
    if (_disposed) {
      return;
    }
    if (_musicPlayer.playing) {
      _pausedByLifecycle = true;
      await _safe(() => _musicPlayer.pause());
    }
    await stopSfx();
  }

  Future<void> onAppResumed() async {
    if (_disposed ||
        !_pausedByLifecycle ||
        _musicPausedByUser ||
        !_musicEnabled ||
        _currentMusicAsset == null) {
      _pausedByLifecycle = false;
      return;
    }
    _pausedByLifecycle = false;
    await _safe(() => _musicPlayer.play());
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_instance, this)) {
      _instance = null;
    }
    await Future.wait([
      _musicPlayer.dispose(),
      ..._sfxPlayers.map((player) => player.dispose()),
    ]);
  }

  String? _resolvePackage(String? package) {
    if (package == '') {
      return null;
    }
    return package ?? AppSounds.packageName;
  }

  Future<void> _pauseSfx() async {
    await Future.wait(_sfxPlayers.map((player) => _safe(player.pause)));
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      AppLogger.log('audio op failed — $error', name: _logName);
    }
  }
}

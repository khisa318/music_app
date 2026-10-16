import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class MediaKitPlayerAdapter {
  Player _player;

  Player? _nextPlayer;

  bool _nextPlayerReady = false;

  final StreamController<bool> _playingSC = StreamController<bool>.broadcast();
  final StreamController<Duration> _positionSC =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationSC =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _bufferSC =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _completedSC =
      StreamController<bool>.broadcast();
  final StreamController<bool> _bufferingSC =
      StreamController<bool>.broadcast();

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _bufferingSub;

  bool _crossfading = false;
  bool _crossfadeCancelRequested = false;
  Completer<void>? _crossfadeCompleter;

  MediaKitPlayerAdapter({Player? player})
    : _player =
          player ??
          Player(
            configuration: const PlayerConfiguration(
              bufferSize: 24 * 1024 * 1024,
            ),
          ) {
    _bindPlayerStreams(_player);
  }

  Player get rawPlayer => _player;

  bool get isNextTrackReady => _nextPlayerReady;

  bool get isCrossfading => _crossfading;

  Future<void> openUri(String uri, {bool play = false}) async {
    _cancelPrebuffer();
    await _player.open(Media(uri), play: play);
  }

  Future<void> openPath(String path, {bool play = false}) async {
    _cancelPrebuffer();
    await _player.open(Media(path), play: play);
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    await cancelCrossfade();
    await _player.pause();
  }

  Future<void> stop() async {
    await cancelCrossfade();
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.5);
    await _player.setVolume(clamped * 100.0);
    if (_nextPlayer != null) {
      try {
        await _nextPlayer!.setVolume(clamped * 100.0);
      } catch (_) {}
    }
  }

  Future<void> setAudioFilterGraph(String graph) async {
    await _applyFilterGraphToPlayer(_player, graph);
  }

  Future<void> prebufferUri(String uri, {double? volume}) async {
    await _initNextPlayer(volume: volume);
    try {
      await _nextPlayer!.open(Media(uri), play: false);
      _nextPlayerReady = true;
      debugPrint('[Prebuffer] URI ready');
    } catch (e) {
      debugPrint('[Prebuffer] Failed to prebuffer URI: $e');
      _cancelPrebuffer();
    }
  }

  Future<void> prebufferPath(String path, {double? volume}) async {
    await _initNextPlayer(volume: volume);
    try {
      await _nextPlayer!.open(Media(path), play: false);
      _nextPlayerReady = true;
      debugPrint('[Prebuffer] Path ready');
    } catch (e) {
      debugPrint('[Prebuffer] Failed to prebuffer path: $e');
      _cancelPrebuffer();
    }
  }

  Future<bool> swapToPrebuffered() async {
    if (!_nextPlayerReady || _nextPlayer == null) {
      debugPrint('[Prebuffer] No prebuffered track to swap to');
      return false;
    }

    final oldPlayer = _player;
    _player = _nextPlayer!;
    _nextPlayer = null;
    _nextPlayerReady = false;

    _bindPlayerStreams(_player);

    await _player.play();

    unawaited(
      Future.delayed(const Duration(milliseconds: 200), () async {
        try {
          await oldPlayer.stop();
          await oldPlayer.dispose();
        } catch (_) {}
      }),
    );

    debugPrint('[Prebuffer] Swapped to prebuffered player');
    return true;
  }

  /// Plays the prebuffered player from silence while fading the current
  /// player out, then promotes the prebuffered player to primary.
  ///
  /// Returns false (leaving state untouched) when there is nothing
  /// prebuffered or when [cancelCrossfade] interrupts the ramp.
  Future<bool> crossfadeToPrebuffered({
    required double targetVolume,
    required Duration duration,
  }) async {
    if (_crossfading) return false;
    if (!_nextPlayerReady || _nextPlayer == null) return false;
    if (duration <= Duration.zero) return false;

    _crossfading = true;
    _crossfadeCancelRequested = false;
    final completer = Completer<void>();
    _crossfadeCompleter = completer;

    final oldPlayer = _player;
    final nextPlayer = _nextPlayer!;
    final base = targetVolume.clamp(0.0, 1.5);

    try {
      await nextPlayer.setVolume(0);
      await nextPlayer.play();

      const steps = 20;
      final stepMs = duration.inMilliseconds ~/ steps;

      for (int i = 1; i <= steps; i++) {
        if (_crossfadeCancelRequested) break;

        final t = i / steps;
        try {
          await oldPlayer.setVolume(base * (1 - t) * 100.0);
          await nextPlayer.setVolume(base * t * 100.0);
        } catch (_) {}

        if (i < steps) {
          await Future.delayed(Duration(milliseconds: stepMs));
        }
      }

      if (_crossfadeCancelRequested) {
        try {
          await oldPlayer.setVolume(base * 100.0);
          await nextPlayer.stop();
          await nextPlayer.dispose();
        } catch (_) {}

        if (_nextPlayer == nextPlayer) {
          _nextPlayer = null;
          _nextPlayerReady = false;
        }

        debugPrint('[Crossfade] Cancelled');
        return false;
      }

      _player = nextPlayer;
      _nextPlayer = null;
      _nextPlayerReady = false;

      _bindPlayerStreams(_player);

      try {
        await _player.setVolume(base * 100.0);
      } catch (_) {}

      unawaited(
        Future.delayed(const Duration(milliseconds: 200), () async {
          try {
            await oldPlayer.stop();
            await oldPlayer.dispose();
          } catch (_) {}
        }),
      );

      debugPrint('[Crossfade] Swapped to crossfaded player');
      return true;
    } catch (e) {
      debugPrint('[Crossfade] Failed: $e');
      return false;
    } finally {
      _crossfading = false;
      _crossfadeCancelRequested = false;
      _crossfadeCompleter = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Interrupts an in-progress [crossfadeToPrebuffered] ramp, restoring the
  /// current player's volume and disposing the half-faded next player.
  Future<void> cancelCrossfade() async {
    if (!_crossfading) return;

    _crossfadeCancelRequested = true;

    final completer = _crossfadeCompleter;
    if (completer != null && !completer.isCompleted) {
      try {
        await completer.future.timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }

  void _cancelPrebuffer() {
    _nextPlayerReady = false;
    if (_nextPlayer != null) {
      final old = _nextPlayer!;
      _nextPlayer = null;
      unawaited(
        Future(() async {
          try {
            await old.stop();
            await old.dispose();
          } catch (_) {}
        }),
      );
    }
  }

  Future<void> _initNextPlayer({double? volume}) async {
    _cancelPrebuffer();
    _nextPlayer = Player(
      configuration: const PlayerConfiguration(bufferSize: 24 * 1024 * 1024),
    );
    if (volume != null) {
      final clamped = volume.clamp(0.0, 1.5);
      await _nextPlayer!.setVolume(clamped * 100.0);
    }
  }

  void _bindPlayerStreams(Player player) {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();

    _playingSub = (player as dynamic).stream.playing.listen((bool v) {
      _playingSC.add(v);
    });
    _positionSub = (player as dynamic).stream.position.listen((Duration v) {
      _positionSC.add(v);
    });
    _durationSub = (player as dynamic).stream.duration.listen((Duration v) {
      _durationSC.add(v);
    });
    _bufferSub = (player as dynamic).stream.buffer.listen((Duration v) {
      _bufferSC.add(v);
    });
    _completedSub = (player as dynamic).stream.completed.listen((bool v) {
      _completedSC.add(v);
    });
    _bufferingSub = (player as dynamic).stream.buffering.listen((bool v) {
      _bufferingSC.add(v);
    });
  }

  Stream<bool> get playingStream => _playingSC.stream;
  Stream<Duration> get positionStream => _positionSC.stream;
  Stream<Duration> get durationStream => _durationSC.stream;
  Stream<Duration> get bufferedPositionStream => _bufferSC.stream;
  Stream<bool> get completedStream => _completedSC.stream;
  Stream<bool> get bufferingStream => _bufferingSC.stream;

  Stream<int> get playlistIndexStream =>
      (_player as dynamic).stream.index as Stream<int>;

  bool get currentPlaying {
    try {
      return (_player as dynamic).state.playing as bool;
    } catch (_) {
      return false;
    }
  }

  Duration get currentPosition {
    try {
      return (_player as dynamic).state.position as Duration;
    } catch (_) {
      return Duration.zero;
    }
  }

  Duration get currentBuffered {
    try {
      return (_player as dynamic).state.buffer as Duration;
    } catch (_) {
      return Duration.zero;
    }
  }

  Duration? get currentDuration {
    try {
      return (_player as dynamic).state.duration as Duration?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyFilterGraphToPlayer(Player player, String graph) async {
    Future<void> apply(String value) async {
      final platform = (player as dynamic).platform;
      if (platform is NativePlayer) {
        await platform
            .setProperty('af', value)
            .timeout(const Duration(milliseconds: 800));
        return;
      }
      await platform
          .setProperty('af', value)
          .timeout(const Duration(milliseconds: 800));
    }

    try {
      await apply(graph);
      return;
    } catch (_) {}

    if (graph.isNotEmpty) {
      try {
        await apply('lavfi=[$graph]');
      } catch (_) {}
    }
  }

  Future<void> applyFilterGraphToNextPlayer(String graph) async {
    if (_nextPlayer != null) {
      await _applyFilterGraphToPlayer(_nextPlayer!, graph);
    }
  }

  Future<void> dispose() async {
    _cancelPrebuffer();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    await _playingSC.close();
    await _positionSC.close();
    await _durationSC.close();
    await _bufferSC.close();
    await _completedSC.close();
    await _bufferingSC.close();
    await _player.dispose();
  }
}

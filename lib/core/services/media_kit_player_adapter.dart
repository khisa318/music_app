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

  MediaKitPlayerAdapter({Player? player})
      : _player = player ??
            Player(
              configuration: const PlayerConfiguration(
                bufferSize: 64 * 1024 * 1024, // 64 MB to cache more eagerly
              ),
            ) {
    _bindPlayerStreams(_player);
  }

  Player get rawPlayer => _player;

  bool get isNextTrackReady => _nextPlayerReady;

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
    await _player.pause();
  }

  Future<void> stop() async {
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
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64 MB to cache more eagerly
      ),
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

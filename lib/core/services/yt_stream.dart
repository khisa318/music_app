import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;

  final String statusMSG;
  final String errorType;

  StreamProvider({
    required this.playable,
    this.audioFormats,
    this.statusMSG = '',
    this.errorType = '',
  });

  /// YouTube clients to rotate through when resolving a stream manifest.
  ///
  /// YouTube serves each client a different manifest and applies its bot
  /// check / rate limiting unevenly, so falling back across several clients
  /// recovers many songs the default client alone fails on. Ordered
  /// "most reliable for logged-out playback" first.
  static final List<List<YoutubeApiClient>> _clientRotation = [
    [YoutubeApiClient.visionos],
    [YoutubeApiClient.androidVr],
    [YoutubeApiClient.ios],
    [YoutubeApiClient.androidMusic],
    [YoutubeApiClient.android],
    [YoutubeApiClient.tv],
    [YoutubeApiClient.mweb],
  ];

  static Future<StreamProvider> fetch(String videoId) async {
    final yt = YoutubeExplode();

    try {
      debugPrint('StreamProvider.fetch: fetching manifest for $videoId');

      Object? lastError;
      var botCheckDetected = false;

      for (var i = 0; i < _clientRotation.length; i++) {
        final clients = _clientRotation[i];

        try {
          final res = await yt.videos.streamsClient.getManifest(
            videoId,
            ytClients: clients,
          );

          final formats = _mapAudio(res.audioOnly);

          debugPrint(
            'StreamProvider.fetch: manifest fetched with '
            '${_clientLabel(clients)} '
            '- audioOnly count=${formats.length}',
          );

          if (formats.isNotEmpty) {
            return StreamProvider(
              playable: true,
              statusMSG: 'OK',
              errorType: '',
              audioFormats: formats,
            );
          }
        } catch (e, st) {
          lastError = e;

          if (_isBotCheck(e)) {
            botCheckDetected = true;
          }

          debugPrint(
            'StreamProvider.fetch: ${_clientLabel(clients)} '
            'failed: $e\n$st',
          );
        }

        if (i < _clientRotation.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      debugPrint(
        'StreamProvider.fetch: all clients failed for $videoId '
        '(botCheck: $botCheckDetected)',
      );

      return _failureResult(lastError, botCheckDetected: botCheckDetected);
    } catch (e, st) {
      debugPrint('StreamProvider.fetch: unexpected exception: $e\n$st');

      return _failureResult(e, botCheckDetected: _isBotCheck(e));
    } finally {
      yt.close();
    }
  }

  static List<Audio> _mapAudio(Iterable<AudioOnlyStreamInfo> audio) {
    try {
      final formats = <Audio>[];

      for (final e in audio) {
        formats.add(
          Audio(
            itag: e.tag,
            audioCodec: e.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
            bitrate: e.bitrate.bitsPerSecond,
            duration: 0,
            loudnessDb: 0.0,
            url: e.url.toString(),
            size: e.size.totalBytes,
          ),
        );
      }

      return formats;
    } catch (e) {
      throw _AudioMappingException(e.toString());
    }
  }

  static String _clientLabel(List<YoutubeApiClient> clients) => clients
      .map((c) => c.payload['context']['client']['clientName'])
      .join('+');

  /// True when the failure looks like YouTube's bot / sign-in check or a rate
  /// limit rather than a genuinely unavailable video.
  static bool _isBotCheck(Object? error) {
    final text = error?.toString().toLowerCase() ?? '';

    return text.contains('not a bot') ||
        text.contains('confirm you') ||
        text.contains('sign in to') ||
        text.contains('login_required') ||
        text.contains('login required') ||
        text.contains('rate limit') ||
        text.contains('too many requests') ||
        text.contains('429') ||
        text.contains('/sorry/');
  }

  static StreamProvider _failureResult(
    Object? error, {
    required bool botCheckDetected,
  }) {
    if (botCheckDetected || error is RequestLimitExceededException) {
      return StreamProvider(
        playable: false,
        statusMSG:
            'YouTube is asking to verify you are not a bot. '
            'Please try again in a moment.',
        errorType: 'bot_check',
      );
    }

    if (error is SocketException) {
      return StreamProvider(
        playable: false,
        statusMSG: 'Unable to connect to the internet.',
        errorType: 'network',
      );
    }

    if (error is VideoUnavailableException) {
      return StreamProvider(
        playable: false,
        statusMSG: 'This song is currently unavailable.',
        errorType: 'unavailable',
      );
    }

    if (error is VideoUnplayableException) {
      return StreamProvider(
        playable: false,
        statusMSG: 'This song cannot be played.',
        errorType: 'unplayable',
      );
    }

    if (error is VideoRequiresPurchaseException) {
      return StreamProvider(
        playable: false,
        statusMSG: 'This song requires a purchase.',
        errorType: 'purchase_required',
      );
    }

    if (error is _AudioMappingException) {
      return StreamProvider(
        playable: false,
        statusMSG: 'Unable to process the audio stream.',
        errorType: 'mapping_error',
      );
    }

    if (error is YoutubeExplodeException) {
      return StreamProvider(
        playable: false,
        statusMSG: 'Unable to load this song.',
        errorType: 'youtube_error',
      );
    }

    return StreamProvider(
      playable: false,
      statusMSG: 'Unable to play this song right now.',
      errorType: 'unknown',
    );
  }

  Audio? get highestQualityAudio {
    if (audioFormats == null || audioFormats!.isEmpty) {
      return null;
    }

    return audioFormats!.lastWhere(
      (item) => item.itag == 251 || item.itag == 140,
      orElse: () => audioFormats!.first,
    );
  }

  Audio? get highestBitrateMp4aAudio {
    if (audioFormats == null || audioFormats!.isEmpty) {
      return null;
    }

    return audioFormats!.lastWhere(
      (item) => item.itag == 140 || item.itag == 139,
      orElse: () => audioFormats!.first,
    );
  }

  Audio? get highestBitrateOpusAudio {
    if (audioFormats == null || audioFormats!.isEmpty) {
      return null;
    }

    return audioFormats!.lastWhere(
      (item) => item.itag == 251 || item.itag == 250,
      orElse: () => audioFormats!.first,
    );
  }

  Audio? get lowQualityAudio {
    if (audioFormats == null || audioFormats!.isEmpty) {
      return null;
    }

    return audioFormats!.lastWhere(
      (item) => item.itag == 249 || item.itag == 139,
      orElse: () => audioFormats!.first,
    );
  }
}

class _AudioMappingException implements Exception {
  final String message;

  _AudioMappingException(this.message);

  @override
  String toString() => 'AudioMappingException: $message';
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;

  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
    'itag': itag,
    'audioCodec': audioCodec.toString(),
    'url': url,
    'bitrate': bitrate,
    'loudnessDb': loudnessDb,
    'approxDurationMs': duration,
    'size': size,
  };

  factory Audio.fromJson(dynamic json) {
    return Audio(
      audioCodec: (json['audioCodec'] as String).contains('mp4a')
          ? Codec.mp4a
          : Codec.opus,
      itag: json['itag'],
      duration: json['approxDurationMs'] ?? 0,
      bitrate: json['bitrate'] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json['size'] ?? 0,
    );
  }
}

enum Codec { mp4a, opus }

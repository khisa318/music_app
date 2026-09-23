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

  static Future<StreamProvider> fetch(String videoId) async {
    final yt = YoutubeExplode();

    try {
      debugPrint('StreamProvider.fetch: fetching manifest for $videoId');

      final res = await yt.videos.streamsClient.getManifest(videoId);

      final audio = res.audioOnly;

      debugPrint(
        'StreamProvider.fetch: manifest fetched '
        '- audioOnly count=${audio.length}',
      );

      if (audio.isEmpty) {
        return StreamProvider(
          playable: false,
          statusMSG: 'No playable audio was found.',
          errorType: 'no_audio',
        );
      }

      final List<Audio> formats = [];

      try {
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
      } catch (mapError, st) {
        debugPrint(
          'StreamProvider.fetch: mapping error: '
          '$mapError\n$st',
        );

        return StreamProvider(
          playable: false,
          statusMSG: 'Unable to process the audio stream.',
          errorType: 'mapping_error',
        );
      }

      if (formats.isEmpty) {
        return StreamProvider(
          playable: false,
          statusMSG: 'No playable audio was found.',
          errorType: 'no_audio',
        );
      }

      return StreamProvider(
        playable: true,
        statusMSG: 'OK',
        errorType: '',
        audioFormats: formats,
      );
    } catch (e, st) {
      debugPrint('StreamProvider.fetch: exception: $e\n$st');

      if (e is SocketException) {
        return StreamProvider(
          playable: false,
          statusMSG: 'Unable to connect to the internet.',
          errorType: 'network',
        );
      }

      if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: 'This song is currently unavailable.',
          errorType: 'unavailable',
        );
      }

      if (e is VideoUnplayableException) {
        return StreamProvider(
          playable: false,
          statusMSG: 'This song cannot be played.',
          errorType: 'unplayable',
        );
      }

      if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: 'This song requires a purchase.',
          errorType: 'purchase_required',
        );
      }

      if (e is YoutubeExplodeException) {
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
    } finally {
      yt.close();
    }
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

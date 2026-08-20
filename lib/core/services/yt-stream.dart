import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider({
    required this.playable,
    this.audioFormats,
    this.statusMSG = "",
  });

  static Future<StreamProvider> fetch(String videoId) async {
    final yt = YoutubeExplode();

    try {
      debugPrint('StreamProvider.fetch: fetching manifest for $videoId');
      final res = await yt.videos.streamsClient.getManifest(videoId);
      final audio = res.audioOnly;
      debugPrint(
        'StreamProvider.fetch: manifest fetched - audioOnly count=${audio.length}',
      );
      final List<Audio> formats = [];
      try {
        for (final e in audio) {
          formats.add(
            Audio(
              itag: e.tag,
              audioCodec: (e.audioCodec).contains('mp')
                  ? Codec.mp4a
                  : Codec.opus,
              bitrate: e.bitrate.bitsPerSecond,
              duration: 0,
              loudnessDb: 0.0,
              url: e.url.toString(),
              size: e.size.totalBytes,
            ),
          );
        }
      } catch (mapError, st) {
        debugPrint('StreamProvider.fetch: mapping error: $mapError\n$st');
        return StreamProvider(
          playable: false,
          statusMSG: 'mappingError: $mapError',
        );
      }

      return StreamProvider(
        playable: true,
        statusMSG: "OK",
        audioFormats: formats,
      );
    } catch (e, st) {
      debugPrint('StreamProvider.fetch: exception: $e\n$st');
      if (e is SocketException) {
        return StreamProvider(playable: false, statusMSG: "networkError: $e");
      } else if (e is VideoUnplayableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song is unplayable: $e",
        );
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song requires purchase",
        );
      } else if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song is unavailable",
        );
      } else if (e is YoutubeExplodeException) {
        return StreamProvider(playable: false, statusMSG: e.message);
      } else {
        return StreamProvider(playable: false, statusMSG: e.toString());
      }
    } finally {
      yt.close();
    }
  }

  Audio? get highestQualityAudio {
    if (audioFormats == null || audioFormats!.isEmpty) return null;
    return audioFormats!.lastWhere(
      (item) => item.itag == 251 || item.itag == 140,
      orElse: () => audioFormats!.first,
    );
  }

  Audio? get highestBitrateMp4aAudio {
    if (audioFormats == null || audioFormats!.isEmpty) return null;
    return audioFormats!.lastWhere(
      (item) => item.itag == 140 || item.itag == 139,
      orElse: () => audioFormats!.first,
    );
  }

  Audio? get highestBitrateOpusAudio {
    if (audioFormats == null || audioFormats!.isEmpty) return null;
    return audioFormats!.lastWhere(
      (item) => item.itag == 251 || item.itag == 250,
      orElse: () => audioFormats!.first,
    );
  }

  Audio? get lowQualityAudio {
    if (audioFormats == null || audioFormats!.isEmpty) return null;
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
    "itag": itag,
    "audioCodec": audioCodec.toString(),
    "bitrate": bitrate,
    "loudnessDb": loudnessDb,
    "url": url,
    "approxDurationMs": duration,
    "size": size,
  };

  factory Audio.fromJson(json) => Audio(
    audioCodec: (json["audioCodec"] as String).contains("mp4a")
        ? Codec.mp4a
        : Codec.opus,
    itag: json['itag'],
    duration: json["approxDurationMs"] ?? 0,
    bitrate: json["bitrate"] ?? 0,
    loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
    url: json['url'],
    size: json["size"] ?? 0,
  );
}

enum Codec { mp4a, opus }

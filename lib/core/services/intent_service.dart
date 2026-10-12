import 'dart:async';
import 'dart:io';
import '../../../../core/providers/queued_provider.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Thumbnail;
import '../models/song_model.dart';
import '../providers/player_provider.dart';

class IntentService {
  final PlayerProvider _playerProvider;
  final QueueProvider _queueProvider;
  StreamSubscription? _intentDataStreamSubscription;

  IntentService(this._playerProvider, this._queueProvider);

  Future<void> init() async {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (value) {
            if (value.isNotEmpty) {
              final sharedFile = value.first;
              if (sharedFile.path.endsWith('.mp3') ||
                  sharedFile.path.endsWith('.m4a') ||
                  sharedFile.path.endsWith('.wav') ||
                  sharedFile.path.endsWith('.flac')) {
                _handleAudioFile(sharedFile.path);
              }
            }
          },
          onError: (err) {
            debugPrint("getMediaStream error: $err");
          },
        );

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        final sharedFile = value.first;
        if (sharedFile.path.endsWith('.mp3') ||
            sharedFile.path.endsWith('.m4a') ||
            sharedFile.path.endsWith('.wav') ||
            sharedFile.path.endsWith('.flac')) {
          _handleAudioFile(sharedFile.path);
        }
        ReceiveSharingIntent.instance.reset();
      }
    });

    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (value) {
            if (value.isNotEmpty) {
              final sharedFile = value.first;
              if (sharedFile.type == SharedMediaType.text) {
                _handleYoutubeUrl(sharedFile.path);
              }
            }
          },
          onError: (err) {
            debugPrint("getMediaStream error: $err");
          },
        );

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        final sharedFile = value.first;
        if (sharedFile.type == SharedMediaType.text) {
          _handleYoutubeUrl(sharedFile.path);
        }
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  Future<void> _handleAudioFile(String path) async {
    String resolvedPath = path;
    try {
      if (path.startsWith('content://')) {
        final uri = Uri.parse(path);
        final tmpDir = await getTemporaryDirectory();
        final ext = p.extension(uri.path).isNotEmpty
            ? p.extension(uri.path)
            : '.mp3';
        final name = p.basenameWithoutExtension(uri.path.isNotEmpty
            ? uri.path
            : 'audio');
        final tmpFile = File('${tmpDir.path}/intent_$name$ext');
        if (await tmpFile.exists()) {
          try {
            await tmpFile.delete();
          } catch (_) {}
        }
        final bytes = await File.fromUri(uri).readAsBytes();
        await tmpFile.writeAsBytes(bytes);
        resolvedPath = tmpFile.path;
      }
    } catch (e) {
      debugPrint('Failed to resolve content URI: $e');
      resolvedPath = path;
    }

    Map<String, dynamic> songData;
    try {
      final metadata = await MetadataGod.readMetadata(file: resolvedPath);
      Uint8List? artwork;
      final picData = metadata.picture?.data;
      if (picData != null) {
        artwork = picData;
      }

      String? thumbnailUri;
      if (artwork != null) {
        try {
          final tempDir = await getTemporaryDirectory();
          final hash = resolvedPath.hashCode.toRadixString(16);
          final artFile = File('${tempDir.path}/artwork_$hash.jpg');
          if (!await artFile.exists()) {
            await artFile.writeAsBytes(artwork);
          }
          thumbnailUri = artFile.path;
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to write artwork file: $e');
        }
      }

      final dynamic rawDuration = metadata.durationMs ?? metadata.duration?.inMilliseconds;
      int? durationMsInt;
      if (rawDuration is num) {
        durationMsInt = rawDuration.toInt();
      } else if (rawDuration is String) {
        durationMsInt = int.tryParse(rawDuration);
      } else {
        durationMsInt = null;
      }

      final title = metadata.title?.trim().isNotEmpty == true
          ? metadata.title!
          : (path.startsWith('content://')
              ? p.basenameWithoutExtension(Uri.parse(path).path)
              : p.basenameWithoutExtension(resolvedPath));
      final artist = metadata.artist?.trim().isNotEmpty == true
          ? metadata.artist!
          : 'Unknown Artist';
      final album = metadata.album?.trim().isNotEmpty == true
          ? metadata.album!
          : 'Unknown Album';

      songData = {
        'id': resolvedPath,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': durationMsInt,
        'thumbnail': thumbnailUri,
        'localPath': resolvedPath,
        'isLocal': true,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Metadata read error for $resolvedPath: $e');
      }
      String fallbackTitle;
      if (path.startsWith('content://')) {
        fallbackTitle = p.basenameWithoutExtension(Uri.parse(path).path);
      } else {
        final base = resolvedPath.isNotEmpty ? resolvedPath : path;
        fallbackTitle = p.basenameWithoutExtension(base);
      }
      songData = {
        'id': resolvedPath,
        'title': fallbackTitle.isNotEmpty ? fallbackTitle : 'Unknown Title',
        'artist': 'Unknown Artist',
        'album': 'Unknown Album',
        'duration': null,
        'thumbnail': null,
        'localPath': resolvedPath,
        'isLocal': true,
      };
    }
    final songQueue = [songData];
    const currentIndex = 0;

    try {
      await _playerProvider.playerService.playLocalAudioWithQueue(
        resolvedPath,
        songData,
        songQueue,
        currentIndex,
      );
    } catch (e) {
      debugPrint('Failed to play local song from intent: $e');
    }
  }

  Future<void> _handleYoutubeUrl(String url) async {
    final videoId = VideoId.parseVideoId(url);
    if (videoId != null) {
      final yt = YoutubeExplode();
      final video = await yt.videos.get(videoId);

      final cleanedAuthor = video.author.endsWith(' - Topic')
          ? video.author.substring(0, video.author.length - ' - Topic'.length)
          : video.author;
      final song = SongInfo(
        videoId: video.id.value,
        name: video.title,
        artists: [Artist(name: cleanedAuthor, id: video.channelId.value)],
        thumbnails: [
          Thumbnail(url: video.thumbnails.highResUrl, width: 720, height: 1280),
        ],
        duration: video.duration ?? Duration.zero,
      );
      _queueProvider.clearQueue();
      _playerProvider.setCurrentSong(song);
      _playerProvider.playerService.playSong(song);
    }
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}

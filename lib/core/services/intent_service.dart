import 'dart:async';
import 'dart:io';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Thumbnail;

import '../../features/playlist_album_content/presentation/screens/playlist_album_content_screen.dart';
import '../../features/playlists/data/providers/playlist_album_library_provider.dart';
import '../models/song_model.dart';
import '../providers/player_provider.dart';
import '../providers/queued_provider.dart';
import '../providers/settings_provider.dart';
import 'content_details_service.dart';

class IntentService {
  final PlayerProvider _playerProvider;
  final QueueProvider _queueProvider;
  final PlaylistAlbumLibraryProvider _libraryProvider;
  final ContentDetailsService _contentDetailsService = ContentDetailsService();

  StreamSubscription? _intentDataStreamSubscription;

  IntentService(
    this._playerProvider,
    this._queueProvider,
    this._libraryProvider,
  );

  Future<void> init() async {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedMedia, onError: (err) {
          debugPrint("getMediaStream error: $err");
        });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      _handleSharedMedia(value);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> value) {
    if (value.isEmpty) return;

    final sharedFile = value.first;

    if (sharedFile.type == SharedMediaType.text) {
      _handleSharedText(sharedFile.path);
      return;
    }

    if (_isAudioPath(sharedFile.path)) {
      _handleAudioFile(sharedFile.path);
    }
  }

  bool _isAudioPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.opus');
  }

  // ============================================================
  // SHARED TEXT (YouTube video / playlist links)
  // ============================================================

  Future<void> _handleSharedText(String text) async {
    final url = _extractUrl(text) ?? text.trim();
    if (url.isEmpty) return;

    final playlistId = _contentDetailsService.extractPlaylistId(url);
    final videoId = VideoId.parseVideoId(url);
    final looksLikePlaylist = url.toLowerCase().contains('/playlist');

    if (playlistId != null && (looksLikePlaylist || videoId == null)) {
      await _handleYoutubePlaylist(playlistId);
      return;
    }

    if (videoId != null) {
      await _handleYoutubeUrl(url);
      return;
    }

    if (playlistId != null) {
      await _handleYoutubePlaylist(playlistId);
    }
  }

  String? _extractUrl(String text) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(text);
    return match?.group(0);
  }

  Future<void> _handleYoutubeUrl(String url) async {
    final videoId = VideoId.parseVideoId(url);
    if (videoId == null) return;

    try {
      final yt = YoutubeExplode();
      final video = await yt.videos.get(videoId);
      yt.close();

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
    } catch (e) {
      debugPrint('Failed to play shared YouTube video: $e');
    }
  }

  // ============================================================
  // SHARED PLAYLIST
  // ============================================================

  Future<void> _handleYoutubePlaylist(String playlistId) async {
    try {
      final details = await _contentDetailsService.getPlaylistDetails(
        playlistId,
      );

      if (details == null) return;

      final isAlbum =
          (details['contentType'] as String?)?.toLowerCase() == 'album';

      final saveData = <String, dynamic>{
        'name': details['name'],
        'thumbnail': details['thumbnail'],
        'duration': details['duration'],
        if (isAlbum)
          'albumId': details['playlistId']
        else
          'playlistId': details['playlistId'],
        'contentType': isAlbum ? 'Album' : 'Playlist',
        'artist': details['artist'],
      };

      if (isAlbum) {
        await _libraryProvider.saveAlbum(saveData);
      } else {
        await _libraryProvider.savePlaylist(saveData);
      }

      await _openPlaylistScreen(details, isAlbum);
    } catch (e) {
      debugPrint('Failed to save shared playlist: $e');
    }
  }

  Future<void> _openPlaylistScreen(
    Map<String, dynamic> details,
    bool isAlbum,
  ) async {
    final navigator = await _waitForNavigator();
    if (navigator == null) return;

    final id = details['playlistId']?.toString() ?? '';
    final name = details['name']?.toString() ?? '';
    final thumbnail = details['thumbnail']?.toString() ?? '';
    final artist = details['artist']?.toString() ?? '';

    final content = isAlbum
        ? AlbumDetailed(
            playlistId: id,
            name: name,
            artist: ArtistBasic(name: artist),
            thumbnails: [
              ThumbnailFull(url: thumbnail, width: 1280, height: 720),
            ],
            type: 'Album',
            albumId: id,
          )
        : PlaylistDetailed(
            playlistId: id,
            name: name,
            artist: ArtistBasic(name: artist),
            thumbnails: [
              ThumbnailFull(url: thumbnail, width: 1280, height: 720),
            ],
            type: 'Playlist',
          );

    await navigator.push(
      MaterialPageRoute(
        builder: (context) => PlaylistAlbumContent(content: content),
      ),
    );
  }

  /// The share intent can be delivered before [MaterialApp] has built, so wait
  /// for the navigator to be ready before opening the playlist.
  Future<NavigatorState?> _waitForNavigator() async {
    final key = GetIt.I<SettingsProvider>().navigatorKey;

    for (var i = 0; i < 50; i++) {
      if (key.currentState != null) return key.currentState;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return key.currentState;
  }

  // ============================================================
  // SHARED AUDIO FILE
  // ============================================================

  Future<void> _handleAudioFile(String path) async {
    String resolvedPath = path;
    try {
      if (path.startsWith('content://')) {
        final uri = Uri.parse(path);
        final tmpDir = await getTemporaryDirectory();
        final ext = p.extension(uri.path).isNotEmpty
            ? p.extension(uri.path)
            : '.mp3';
        final name = p.basenameWithoutExtension(
          uri.path.isNotEmpty ? uri.path : 'audio',
        );
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

      final dynamic rawDuration =
          metadata.durationMs ?? metadata.duration?.inMilliseconds;
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

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}

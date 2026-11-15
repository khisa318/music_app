import 'package:dart_ytmusic_api/types.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/models/song_model.dart';
import '../../../../core/providers/favorite_song_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/video_info_provider.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../../core/services/queue_builder_service.dart';

class HomeScreenQueueService {
  final BuildContext context;

  final ContentDetailsService _contentDetailsService = ContentDetailsService();

  final QueueBuilderService _queueBuilderService = QueueBuilderService();

  HomeScreenQueueService(this.context);

  Future<void> playAndQueueSongs(Map<String, dynamic> song) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    final videoInfoProvider = Provider.of<VideoInfoProvider>(
      context,
      listen: false,
    );

    try {
      final dynamic rawVideoId = song['id'] ?? song['videoId'];

      if (rawVideoId == null || rawVideoId.toString().trim().isEmpty) {
        throw Exception('Video ID not found');
      }

      final String videoId = rawVideoId.toString().trim();

      final videoInfo = await videoInfoProvider.getVideoInfo(videoId);

      if (videoInfo == null) {
        throw Exception('Video details not found');
      }

      final String cleanedAuthor = videoInfo.author.endsWith(' - Topic')
          ? videoInfo.author.substring(
              0,
              videoInfo.author.length - ' - Topic'.length,
            )
          : videoInfo.author;

      final SongInfo clickedSong = SongInfo(
        videoId: videoInfo.videoId,
        name: videoInfo.title,
        artists: [Artist(name: cleanedAuthor, id: videoInfo.channelId)],
        thumbnails: [
          Thumbnail(url: videoInfo.thumbnailUrl, width: 1280, height: 720),
        ],
        duration: videoInfo.duration ?? Duration.zero,
      );

      queueProvider.setQueue(
        [clickedSong],
        currentIndex: 0,
        playlistId: 'speed_dial',
        playlistName: 'Speed Dial',
      );

      await queueProvider.saveQueue();

      await playerProvider.playerService.playSong(clickedSong);

      _queueBuilderService.buildInBackground(
        currentSong: clickedSong,
        queueProvider: queueProvider,
        playlistId: 'speed_dial',
        playlistName: 'Speed Dial',
      );
    } catch (e, stackTrace) {
      debugPrint('Home play request failed: $e');
      debugPrint('$stackTrace');

      throw Exception('Error playing and queuing songs: ${e.toString()}');
    }
  }

  Future<void> playSongFromMap(
    Map<String, dynamic> song,
    String playlistId, {
    String playlistName = 'Personalized',
  }) async {
    final SongInfo? songInfo = _convertRecentSong(song);

    if (songInfo == null) {
      throw Exception('Invalid song data');
    }

    await playSong(songInfo, playlistId, playlistName: playlistName);
  }

  Future<void> playSong(
    SongInfo song,
    String playlistId, {
    String playlistName = 'Personalized',
  }) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    try {
      queueProvider.setQueue(
        [song],
        currentIndex: 0,
        playlistId: playlistId,
        playlistName: playlistName,
      );

      await queueProvider.saveQueue();

      await playerProvider.playerService.playSong(song);

      _queueBuilderService.buildInBackground(
        currentSong: song,
        queueProvider: queueProvider,
        playlistId: playlistId,
        playlistName: playlistName,
      );
    } catch (e, stackTrace) {
      debugPrint('Home song play request failed: $e');
      debugPrint('$stackTrace');

      throw Exception('Error playing song: ${e.toString()}');
    }
  }

  Future<void> playArtistSongs(String artistId) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    try {
      final songsData = await _contentDetailsService.loadArtistSongs(artistId);

      final dynamic rawSongs = songsData['allSongs'];

      if (rawSongs is! List || rawSongs.isEmpty) {
        throw Exception('No songs found for this artist.');
      }

      final List<SongInfo> convertedSongs = rawSongs.map<SongInfo>((s) {
        if (s is SongDetailed) {
          return SongInfo(
            videoId: s.videoId,
            name: s.name,
            artists: [Artist(name: s.artist.name, id: s.artist.artistId ?? '')],
            thumbnails: s.thumbnails
                .map(
                  (t) =>
                      Thumbnail(url: t.url, width: t.width, height: t.height),
                )
                .toList(),
            duration: s.duration != null
                ? Duration(seconds: s.duration!)
                : Duration.zero,
          );
        }

        if (s is SongInfo) {
          return s;
        }

        throw Exception(
          'Invalid song type in list: '
          '${s.runtimeType}',
        );
      }).toList();

      if (convertedSongs.isEmpty) {
        throw Exception('No valid songs found for this artist.');
      }

      final String playlistName = convertedSongs.first.artists.isNotEmpty
          ? convertedSongs.first.artists.first.name
          : 'Unknown Artist';

      await _contentDetailsService.playSong(
        convertedSongs.first,
        playerProvider,
        queueProvider,
        convertedSongs,
        playlistId: artistId,
        playlistName: playlistName,
      );

      await queueProvider.saveQueue();
    } catch (e) {
      throw Exception('Error playing artist songs: ${e.toString()}');
    }
  }

  Future<void> playAll(String playlistType, {int currentIndex = 0}) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    try {
      List<Map<String, dynamic>> songsData = [];

      String playlistId = '';

      if (playlistType == 'recently_played') {
        songsData = playerProvider.lastPlayedSongs;
        playlistId = 'recently_played';
      } else if (playlistType == 'liked_songs') {
        final favoriteSongProvider = Provider.of<FavoriteSongProvider>(
          context,
          listen: false,
        );

        songsData = favoriteSongProvider.likedSongs;
        playlistId = 'liked_songs';
      } else {
        throw Exception('Unknown playlist type: $playlistType');
      }

      if (songsData.isEmpty) {
        throw Exception('No songs found in $playlistType.');
      }

      final List<SongInfo> convertedSongs = songsData
          .map<SongInfo?>((song) => _convertRecentSong(song))
          .whereType<SongInfo>()
          .toList();

      if (convertedSongs.isEmpty) {
        throw Exception('No valid songs found in $playlistType.');
      }

      if (currentIndex < 0 || currentIndex >= convertedSongs.length) {
        currentIndex = 0;
      }

      final String playlistName = playlistType == 'recently_played'
          ? 'Recently'
          : playlistType == 'liked_songs'
          ? 'favorites'
          : playlistId;

      await _contentDetailsService.playSong(
        convertedSongs[currentIndex],
        playerProvider,
        queueProvider,
        convertedSongs,
        playlistId: playlistId,
        playlistName: playlistName,
      );

      queueProvider.setQueue(
        convertedSongs,
        currentIndex: currentIndex,
        playlistId: playlistId,
        playlistName: playlistName,
      );

      await queueProvider.saveQueue();
    } catch (e) {
      throw Exception('Error playing $playlistType: ${e.toString()}');
    }
  }

  SongInfo? _convertRecentSong(Map<String, dynamic> song) {
    try {
      final dynamic rawId = song['id'] ?? song['videoId'];

      if (rawId == null || rawId.toString().trim().isEmpty) {
        return null;
      }

      final String videoId = rawId.toString().trim();

      final String title = (song['title'] ?? song['name'] ?? 'Unknown Title')
          .toString();

      final String artist =
          (song['artist'] ?? _getFirstArtistName(song) ?? 'Unknown Artist')
              .toString();

      final String artistId =
          (song['artistId'] ?? _getFirstArtistId(song) ?? '').toString();

      final String thumbnail =
          (song['thumbnail'] ??
                  song['thumbnailUrl'] ??
                  'assets/default_artwork.png')
              .toString();

      final int durationSeconds = _safeInt(song['duration']);

      return SongInfo(
        videoId: videoId,
        name: title,
        artists: [Artist(name: artist, id: artistId)],
        thumbnails: [Thumbnail(url: thumbnail, width: 1280, height: 720)],
        duration: Duration(seconds: durationSeconds),
      );
    } catch (e) {
      debugPrint('Failed converting recent song: $e');

      return null;
    }
  }

  String? _getFirstArtistName(Map<String, dynamic> song) {
    try {
      final dynamic artists = song['artists'];

      if (artists is! List || artists.isEmpty) {
        return null;
      }

      final dynamic first = artists.first;

      if (first is Map) {
        return first['name']?.toString();
      }
    } catch (_) {}

    return null;
  }

  String? _getFirstArtistId(Map<String, dynamic> song) {
    try {
      final dynamic artists = song['artists'];

      if (artists is! List || artists.isEmpty) {
        return null;
      }

      final dynamic first = artists.first;

      if (first is Map) {
        return first['id']?.toString();
      }
    } catch (_) {}

    return null;
  }

  int _safeInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    return int.tryParse(value.toString().trim()) ?? 0;
  }
}

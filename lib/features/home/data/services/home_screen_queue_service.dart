import 'package:dart_ytmusic_api/types.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Thumbnail;

import '../../../../core/models/song_model.dart';
import '../../../../core/providers/favorite_song_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/video_info_provider.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../../core/services/related_song_service.dart';

class HomeScreenQueueService {
  final BuildContext context;

  final YoutubeExplode _yt;

  final ContentDetailsService _contentDetailsService = ContentDetailsService();

  final RelatedSongService _relatedSongService = RelatedSongService();

  HomeScreenQueueService(this.context) : _yt = GetIt.I<YoutubeExplode>();

  // ============================================================
  // PLAY CLICKED SONG + BUILD SMART QUEUE
  // ============================================================

  Future<void> playAndQueueSongs(Map<String, dynamic> song) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    final videoInfoProvider = Provider.of<VideoInfoProvider>(
      context,
      listen: false,
    );

    try {
      debugPrint('');
      debugPrint('====================================================');
      debugPrint('▶ SPEED DIAL PLAY REQUEST');

      // ----------------------------------------------------------
      // GET VIDEO ID
      // ----------------------------------------------------------

      final dynamic rawVideoId = song['id'] ?? song['videoId'];

      if (rawVideoId == null || rawVideoId.toString().trim().isEmpty) {
        throw Exception('Video ID not found');
      }

      final String videoId = rawVideoId.toString().trim();

      debugPrint('▶ Video ID: $videoId');

      // ----------------------------------------------------------
      // GET VIDEO INFORMATION
      // ----------------------------------------------------------

      debugPrint('▶ Fetching video information for $videoId');

      final videoInfo = await videoInfoProvider.getVideoInfo(videoId);

      if (videoInfo == null) {
        throw Exception('Video details not found');
      }

      // ----------------------------------------------------------
      // CLEAN AUTHOR
      // ----------------------------------------------------------

      final String cleanedAuthor = videoInfo.author.endsWith(' - Topic')
          ? videoInfo.author.substring(
              0,
              videoInfo.author.length - ' - Topic'.length,
            )
          : videoInfo.author;

      // ----------------------------------------------------------
      // CREATE SONG INFO
      // ----------------------------------------------------------

      final SongInfo clickedSong = SongInfo(
        videoId: videoInfo.videoId,
        name: videoInfo.title,
        artists: [Artist(name: cleanedAuthor, id: videoInfo.channelId)],
        thumbnails: [
          Thumbnail(url: videoInfo.thumbnailUrl, width: 1280, height: 720),
        ],
        duration: videoInfo.duration ?? Duration.zero,
      );

      debugPrint('√ Song resolved: ${clickedSong.name}');

      debugPrint('√ Artist: $cleanedAuthor');

      // ----------------------------------------------------------
      // IMPORTANT:
      // PLAY CLICKED SONG FIRST.
      //
      // DO NOT WAIT FOR RELATED SONGS.
      // ----------------------------------------------------------

      debugPrint('▶ Starting player: ${clickedSong.videoId}');

      await playerProvider.playerService.playSong(clickedSong);

      debugPrint('√ Player playSong() completed');

      // ----------------------------------------------------------
      // INITIAL QUEUE
      //
      // At this point the clicked song is guaranteed to be
      // in the queue even if every related request fails.
      // ----------------------------------------------------------

      queueProvider.setQueue(
        [clickedSong],
        currentIndex: 0,
        playlistId: 'speed_dial',
        playlistName: 'Speed Dial',
      );

      await queueProvider.saveQueue();

      debugPrint('√ Initial Speed Dial queue created');

      // ----------------------------------------------------------
      // FIND RELATED SONGS
      //
      // This is deliberately done AFTER playback starts.
      // ----------------------------------------------------------

      final List<SongInfo> finalQueue = await _findRelatedWithRecentFallback(
        clickedSong: clickedSong,
        clickedVideoId: videoId,
        playerProvider: playerProvider,
      );

      // ----------------------------------------------------------
      // UPDATE QUEUE
      // ----------------------------------------------------------

      queueProvider.setQueue(
        finalQueue,
        currentIndex: 0,
        playlistId: 'speed_dial',
        playlistName: 'Speed Dial',
      );

      await queueProvider.saveQueue();

      debugPrint('√ Speed Dial queue saved');

      debugPrint('√ Final queue size: ${finalQueue.length}');

      debugPrint('√ SPEED DIAL PLAY REQUEST FINISHED');

      debugPrint('====================================================');
      debugPrint('');
    } catch (e, stackTrace) {
      debugPrint('❌ SPEED DIAL PLAY REQUEST FAILED');

      debugPrint('❌ $e');

      debugPrint('$stackTrace');

      throw Exception('Error playing and queuing songs: ${e.toString()}');
    }
  }

  // ============================================================
  // SMART RELATED FALLBACK
  //
  // ORDER:
  //
  // CLICKED SONG
  //   attempt 1
  //   attempt 2
  //   attempt 3
  //   attempt 4
  //
  // RECENT SONG #1
  //   attempt 1
  //   attempt 2
  //   attempt 3
  //   attempt 4
  //
  // RECENT SONG #2
  //   attempt 1
  //   ...
  //
  // FIRST SUCCESS = STOP
  // ============================================================

  Future<List<SongInfo>> _findRelatedWithRecentFallback({
    required SongInfo clickedSong,
    required String clickedVideoId,
    required PlayerProvider playerProvider,
  }) async {
    // ----------------------------------------------------------
    // ALWAYS START WITH CLICKED SONG
    // ----------------------------------------------------------

    debugPrint('▶ Searching related songs for ${clickedSong.name}');

    final List<SongInfo> clickedRelated = await _tryRelatedFourTimes(
      seedSong: clickedSong,
      videoId: clickedVideoId,
    );

    // ----------------------------------------------------------
    // CLICKED SONG WORKED
    // ----------------------------------------------------------

    if (clickedRelated.isNotEmpty) {
      debugPrint('√ Clicked song produced related songs');

      return _buildQueue(
        clickedSong: clickedSong,
        seedSong: null,
        relatedSongs: clickedRelated,
      );
    }

    // ----------------------------------------------------------
    // CLICKED SONG FAILED ALL 4 ATTEMPTS
    // ----------------------------------------------------------

    debugPrint('⚠ Clicked song failed all 4 attempts');

    // ----------------------------------------------------------
    // GET RECENT SONGS
    // ----------------------------------------------------------

    final List<Map<String, dynamic>> recentSongs =
        List<Map<String, dynamic>>.from(playerProvider.lastPlayedSongs);

    if (recentSongs.isEmpty) {
      debugPrint('⚠ No recent played songs available');

      debugPrint('⚠ No related songs found anywhere');

      return [clickedSong];
    }

    // ----------------------------------------------------------
    // PREVENT SAME VIDEO FROM BEING TRIED AGAIN
    // ----------------------------------------------------------

    final Set<String> triedVideoIds = {clickedVideoId};

    // ----------------------------------------------------------
    // TRY EACH RECENT SONG
    // ----------------------------------------------------------

    for (final recentData in recentSongs) {
      try {
        final SongInfo? recentSong = _convertRecentSong(recentData);

        if (recentSong == null) {
          debugPrint('⚠ Invalid recent song - skipping');

          continue;
        }

        final String recentVideoId = recentSong.videoId;

        // ------------------------------------------------------
        // DON'T TRY THE SAME VIDEO TWICE
        // ------------------------------------------------------

        if (recentVideoId.isEmpty) {
          continue;
        }

        if (triedVideoIds.contains(recentVideoId)) {
          debugPrint('⚠ Already tried ${recentSong.name} - skipping');

          continue;
        }

        triedVideoIds.add(recentVideoId);

        debugPrint('');
        debugPrint('▶ Trying recent seed: ${recentSong.name}');

        debugPrint('▶ Recent seed video ID: $recentVideoId');

        // ------------------------------------------------------
        // FOUR ATTEMPTS FOR THIS RECENT SONG
        // ------------------------------------------------------

        final List<SongInfo> recentRelated = await _tryRelatedFourTimes(
          seedSong: recentSong,
          videoId: recentVideoId,
        );

        // ------------------------------------------------------
        // SUCCESS
        //
        // STOP SEARCHING.
        // ------------------------------------------------------

        if (recentRelated.isNotEmpty) {
          debugPrint('√ Recent seed worked: ${recentSong.name}');

          debugPrint('√ Stopping fallback search');

          return _buildQueue(
            clickedSong: clickedSong,
            seedSong: recentSong,
            relatedSongs: recentRelated,
          );
        }

        // ------------------------------------------------------
        // THIS RECENT SONG FAILED ALL 4
        //
        // MOVE TO NEXT RECENT SONG.
        // ------------------------------------------------------

        debugPrint(
          '⚠ Recent seed failed all 4 attempts: '
          '${recentSong.name}',
        );

        debugPrint('▶ Moving to next recent song...');
      } catch (e) {
        // ------------------------------------------------------
        // ONE BAD RECENT SONG MUST NOT STOP THE WHOLE SEARCH
        // ------------------------------------------------------

        debugPrint('⚠ Recent seed processing failed: $e');

        continue;
      }
    }

    // ----------------------------------------------------------
    // EVERYTHING FAILED
    // ----------------------------------------------------------

    debugPrint('⚠ No recent song produced related results.');

    debugPrint('⚠ No related songs found anywhere.');

    debugPrint('√ Keeping queue with clicked song only.');

    return [clickedSong];
  }

  // ============================================================
  // TRY ONE SEED FOUR TIMES
  // ============================================================

  Future<List<SongInfo>> _tryRelatedFourTimes({
    required SongInfo seedSong,
    required String videoId,
  }) async {
    for (int attempt = 1; attempt <= 4; attempt++) {
      try {
        debugPrint(
          '▶ Related attempt $attempt/4 '
          'for ${seedSong.name}',
        );

        final List<SongInfo> result = await _relatedSongService
            .createSongListWithRelated(seedSong, videoId);

        // ------------------------------------------------------
        // REMOVE INVALID / DUPLICATE RESULTS
        // ------------------------------------------------------

        final List<SongInfo> cleaned = _removeDuplicates(
          result,
          seedVideoId: videoId,
        );

        // ------------------------------------------------------
        // SUCCESS
        // ------------------------------------------------------

        if (cleaned.isNotEmpty) {
          debugPrint('√ Related attempt $attempt/4 succeeded');

          debugPrint('√ Found ${cleaned.length} related songs');

          return cleaned;
        }

        debugPrint(
          '⚠ Related attempt $attempt/4 '
          'returned no usable songs',
        );
      } catch (e) {
        debugPrint('⚠ Related attempt $attempt/4 failed: $e');

        // ------------------------------------------------------
        // IMPORTANT:
        // CONTINUE TO NEXT ATTEMPT.
        // ------------------------------------------------------

        continue;
      }
    }

    debugPrint('⚠ All 4 attempts failed for ${seedSong.name}');

    return [];
  }

  // ============================================================
  // BUILD FINAL QUEUE
  // ============================================================

  List<SongInfo> _buildQueue({
    required SongInfo clickedSong,
    required SongInfo? seedSong,
    required List<SongInfo> relatedSongs,
  }) {
    final List<SongInfo> queue = [];

    // ----------------------------------------------------------
    // CLICKED SONG ALWAYS FIRST
    // ----------------------------------------------------------

    queue.add(clickedSong);

    // ----------------------------------------------------------
    // IF A RECENT SONG WAS THE SUCCESSFUL SEED,
    // ADD IT AFTER THE CLICKED SONG.
    // ----------------------------------------------------------

    if (seedSong != null && seedSong.videoId != clickedSong.videoId) {
      queue.add(seedSong);
    }

    // ----------------------------------------------------------
    // ADD RELATED SONGS
    // ----------------------------------------------------------

    queue.addAll(relatedSongs);

    // ----------------------------------------------------------
    // REMOVE DUPLICATES
    // ----------------------------------------------------------

    final List<SongInfo> finalQueue = _removeDuplicatesFromQueue(queue);

    debugPrint('√ Queue built with ${finalQueue.length} songs');

    return finalQueue;
  }

  // ============================================================
  // REMOVE DUPLICATES
  // ============================================================

  List<SongInfo> _removeDuplicates(
    List<SongInfo> songs, {
    required String seedVideoId,
  }) {
    final Set<String> ids = {};
    final List<SongInfo> output = [];

    for (final song in songs) {
      final String id = song.videoId;

      if (id.isEmpty) {
        continue;
      }

      if (id == seedVideoId) {
        continue;
      }

      if (ids.contains(id)) {
        continue;
      }

      ids.add(id);
      output.add(song);
    }

    return output;
  }

  List<SongInfo> _removeDuplicatesFromQueue(List<SongInfo> songs) {
    final Set<String> ids = {};
    final List<SongInfo> output = [];

    for (final song in songs) {
      if (song.videoId.isEmpty) {
        continue;
      }

      if (ids.contains(song.videoId)) {
        continue;
      }

      ids.add(song.videoId);
      output.add(song);
    }

    return output;
  }

  // ============================================================
  // CONVERT RECENT PLAYED SONG → SongInfo
  // ============================================================

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
      debugPrint('⚠ Failed converting recent song: $e');

      return null;
    }
  }

  // ============================================================
  // GET ARTIST NAME FROM NESTED ARTISTS
  // ============================================================

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

  // ============================================================
  // GET ARTIST ID FROM NESTED ARTISTS
  // ============================================================

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

  // ============================================================
  // SAFE INTEGER
  //
  // FIXES:
  //
  // FormatException:
  // Invalid radix-10 number
  // Streamed
  // ============================================================

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

    final String text = value.toString().trim();

    final int? parsed = int.tryParse(text);

    return parsed ?? 0;
  }

  // ============================================================
  // PLAY ARTIST SONGS
  // ============================================================

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

      final String playlistName =
          convertedSongs.isNotEmpty && convertedSongs.first.artists.isNotEmpty
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

  // ============================================================
  // PLAY ALL
  // ============================================================

  Future<void> playAll(String playlistType, {int currentIndex = 0}) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    final queueProvider = Provider.of<QueueProvider>(context, listen: false);

    try {
      List<Map<String, dynamic>> songsData = [];

      String playlistId = '';

      // --------------------------------------------------------
      // RECENTLY PLAYED
      // --------------------------------------------------------

      if (playlistType == 'recently_played') {
        songsData = playerProvider.lastPlayedSongs;

        playlistId = 'recently_played';
      }
      // --------------------------------------------------------
      // LIKED SONGS
      // --------------------------------------------------------
      else if (playlistType == 'liked_songs') {
        final favoriteSongProvider = Provider.of<FavoriteSongProvider>(
          context,
          listen: false,
        );

        songsData = favoriteSongProvider.likedSongs;

        playlistId = 'liked_songs';
      }
      // --------------------------------------------------------
      // UNKNOWN TYPE
      // --------------------------------------------------------
      else {
        throw Exception('Unknown playlist type: $playlistType');
      }

      if (songsData.isEmpty) {
        throw Exception('No songs found in $playlistType.');
      }

      // --------------------------------------------------------
      // CONVERT
      // --------------------------------------------------------

      final List<SongInfo> convertedSongs = songsData
          .map<SongInfo?>((song) => _convertRecentSong(song))
          .whereType<SongInfo>()
          .toList();

      if (convertedSongs.isEmpty) {
        throw Exception('No valid songs found in $playlistType.');
      }

      // --------------------------------------------------------
      // INDEX SAFETY
      // --------------------------------------------------------

      if (currentIndex < 0 || currentIndex >= convertedSongs.length) {
        currentIndex = 0;
      }

      // --------------------------------------------------------
      // PLAYLIST NAME
      // --------------------------------------------------------

      final String playlistName = playlistType == 'recently_played'
          ? 'Recently'
          : playlistType == 'liked_songs'
          ? 'favorites'
          : playlistId;

      // --------------------------------------------------------
      // PLAY
      // --------------------------------------------------------

      await _contentDetailsService.playSong(
        convertedSongs[currentIndex],
        playerProvider,
        queueProvider,
        convertedSongs,
        playlistId: playlistId,
        playlistName: playlistName,
      );

      // --------------------------------------------------------
      // SET QUEUE
      // --------------------------------------------------------

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
}

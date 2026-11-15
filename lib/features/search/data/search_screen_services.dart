import 'package:flutter/foundation.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:get_it/get_it.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Thumbnail;

import '../../../core/models/song_model.dart';
import '../../../core/providers/queued_provider.dart';
import '../../../core/services/queue_builder_service.dart';
import '../../../core/services/settings_storage_service.dart';

enum SearchMode { youtubeMusic, youtube }

class SearchScreenServices {
  final YTMusic _ytMusic = GetIt.I<YTMusic>();
  final YoutubeExplode _yt = GetIt.I<YoutubeExplode>();

  final QueueBuilderService _queueBuilderService = QueueBuilderService();

  static const String searchHistoryKey = 'search_history';
  static const String searchHistoryEnabledKey = 'searchHistoryEnabled';

  // ---------------------------------------------------------------------------
  // SEARCH HISTORY
  // ---------------------------------------------------------------------------

  Future<List<String>> loadSearchHistory() async {
    final box = await SettingsStorageService.getBox();

    final isEnabled = (box.get(searchHistoryEnabledKey) as bool?) ?? true;

    if (!isEnabled) {
      return [];
    }

    return (box.get(searchHistoryKey) as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
  }

  Future<void> saveSearchHistory(List<String> history) async {
    final box = await SettingsStorageService.getBox();

    final isEnabled = (box.get(searchHistoryEnabledKey) as bool?) ?? true;

    if (!isEnabled) {
      return;
    }

    await box.put(searchHistoryKey, history);
  }

  Future<List<String>> addToSearchHistory(
    List<String> history,
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return history;
    }

    final updatedHistory = List<String>.from(history)
      ..remove(query)
      ..insert(0, query);

    if (updatedHistory.length > 10) {
      updatedHistory.removeRange(10, updatedHistory.length);
    }

    await saveSearchHistory(updatedHistory);

    return updatedHistory;
  }

  Future<List<String>> removeFromSearchHistory(
    List<String> history,
    String query,
  ) async {
    final updatedHistory = List<String>.from(history)..remove(query);

    await saveSearchHistory(updatedHistory);

    return updatedHistory;
  }

  Future<void> clearSearchHistory() async {
    await saveSearchHistory(const []);
  }

  // ---------------------------------------------------------------------------
  // SEARCH SUGGESTIONS
  // ---------------------------------------------------------------------------

  Future<List<dynamic>> fetchQuickSongs(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    try {
      final songs = await _ytMusic.searchSongs(query);

      return songs.take(5).toList();
    } catch (e) {
      debugPrint('fetchQuickSongs failed: $e');

      return [];
    }
  }

  Future<List<String>> fetchSearchSuggestions(
    String query,
    SearchMode mode,
  ) async {
    if (query.trim().isEmpty) {
      return [];
    }

    try {
      if (mode == SearchMode.youtube) {
        if (query.length < 3) {
          return [];
        }

        final suggestions = await _yt.search.getQuerySuggestions(query);

        return suggestions.take(5).toList();
      }

      final suggestions = await _ytMusic.getSearchSuggestions(query);

      return suggestions.take(5).toList();
    } catch (e) {
      debugPrint('fetchSearchSuggestions failed: $e');

      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  Future<List<dynamic>> fetchYouTubeVideos(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    try {
      final results = await _yt.search.search(query, filter: TypeFilters.video);

      return results.take(20).toList();
    } catch (e) {
      debugPrint('Error fetching YouTube videos: $e');

      return [];
    }
  }

  Future<Map<String, List<dynamic>>> performSearch(
    String query,
    SearchMode mode,
  ) async {
    if (query.trim().isEmpty) {
      if (mode == SearchMode.youtube) {
        return {'Videos': []};
      }

      return {'Songs': [], 'Albums': [], 'Artists': [], 'Playlists': []};
    }

    if (mode == SearchMode.youtube) {
      final videos = await fetchYouTubeVideos(query);

      return {'Videos': videos};
    }

    final results = await Future.wait([
      _ytMusic.searchSongs(query),
      _ytMusic.searchAlbums(query),
      _ytMusic.searchArtists(query),
      _ytMusic.searchPlaylists(query),
    ]);

    return {
      'Songs': results[0],
      'Albums': results[1],
      'Artists': results[2],
      'Playlists': results[3],
    };
  }

  // ---------------------------------------------------------------------------
  // PLAY SONG
  // ---------------------------------------------------------------------------

  Future<void> playSong(
    dynamic song,
    dynamic playerProvider,
    QueueProvider queueProvider,
  ) async {
    /*
     * IMPORTANT:
     *
     * This method intentionally does NOT wait for radio generation.
     *
     * The clicked song is placed into the queue immediately.
     * Playback starts immediately.
     *
     * Radio generation runs separately in the background.
     */

    final songInfo = _convertToSongInfo(song);

    if (songInfo.videoId.isEmpty) {
      throw Exception('Cannot play song: empty video ID');
    }

    debugPrint(
      'Starting playback immediately: '
      '${songInfo.name} - ${songInfo.videoId}',
    );

    // -------------------------------------------------------------------------
    // STEP 1:
    // Put the clicked song in the queue immediately.
    // -------------------------------------------------------------------------

    try {
      queueProvider.setQueue(
        [songInfo],
        currentIndex: 0,
        playlistId: 'search_results',
        playlistName: 'Search Results',
      );
    } catch (e) {
      debugPrint('Initial queue setup failed: $e');
    }

    // -------------------------------------------------------------------------
    // STEP 2:
    // START PLAYBACK IMMEDIATELY.
    //
    // We await ONLY the actual player start.
    // We do NOT wait for radio generation.
    // -------------------------------------------------------------------------

    try {
      await playerProvider.playerService.playSong(songInfo);

      debugPrint(
        'Playback started successfully: '
        '${songInfo.name} - ${songInfo.videoId}',
      );
    } catch (e) {
      debugPrint(
        'Actual playback failed for '
        '${songInfo.name}: $e',
      );

      rethrow;
    }

    // -------------------------------------------------------------------------
    // STEP 3:
    // Build the rest of the queue in the background.
    //
    // There is deliberately NO await here.
    // -------------------------------------------------------------------------

    _queueBuilderService.buildInBackground(
      currentSong: songInfo,
      queueProvider: queueProvider,
      playlistId: 'search_results',
      playlistName: 'Search Results',
      useYouTubeRelated: _isYouTubeSong(song),
    );
  }

  // ---------------------------------------------------------------------------
  // SONG CONVERSION
  // ---------------------------------------------------------------------------

  SongInfo _convertToSongInfo(dynamic song) {
    return SongInfo(
      videoId: song.videoId?.toString() ?? '',
      name: song.name?.toString() ?? 'Unknown Title',
      artists: [
        Artist(
          name: song.artist?.name?.toString() ?? 'Unknown Artist',
          id: song.artist?.artistId?.toString() ?? '',
        ),
      ],
      thumbnails: _convertThumbnails(song),
      duration: Duration(seconds: _getDurationSeconds(song)),
    );
  }

  List<Thumbnail> _convertThumbnails(dynamic song) {
    try {
      final thumbnails = song.thumbnails as List;

      return thumbnails
          .map(
            (t) => Thumbnail(
              url: t.url?.toString() ?? '',
              width: _toInt(t.width, 1280),
              height: _toInt(t.height, 720),
            ),
          )
          .where((t) => t.url.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Thumbnail conversion failed: $e');

      return [];
    }
  }

  int _getDurationSeconds(dynamic song) {
    try {
      final duration = song.duration;

      if (duration == null) {
        return 0;
      }

      if (duration is Duration) {
        return duration.inSeconds;
      }

      if (duration is int) {
        return duration;
      }

      return int.tryParse(duration.toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  int _toInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _isYouTubeSong(dynamic song) {
    try {
      return song.isYouTube == true;
    } catch (_) {
      return false;
    }
  }

}

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:get_it/get_it.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Thumbnail;

import '../../../core/models/song_model.dart';
import '../../../core/services/related_song_service.dart';
import '../../../core/services/settings_storage_service.dart';
import '../../../core/services/yt-music-api.dart' as ytApi;

enum SearchMode { youtubeMusic, youtube }

class SearchScreenServices {
  final YTMusic _ytMusic = GetIt.I<YTMusic>();
  final YoutubeExplode _yt = GetIt.I<YoutubeExplode>();

  final RelatedSongService _relatedSongService = RelatedSongService();

  static const String SEARCH_HISTORY_KEY = 'search_history';
  static const String SEARCH_HISTORY_ENABLED_KEY = 'searchHistoryEnabled';

  static const int _maxSearchQueueSize = 250;
  static const int _initialRadioBatchLimit = 50;
  static const int _extraRadioFetchCount = 6;

  // ---------------------------------------------------------------------------
  // SEARCH HISTORY
  // ---------------------------------------------------------------------------

  Future<List<String>> loadSearchHistory() async {
    final box = await SettingsStorageService.getBox();

    final isEnabled = (box.get(SEARCH_HISTORY_ENABLED_KEY) as bool?) ?? true;

    if (!isEnabled) {
      return [];
    }

    return (box.get(SEARCH_HISTORY_KEY) as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
  }

  Future<void> saveSearchHistory(List<String> history) async {
    final box = await SettingsStorageService.getBox();

    final isEnabled = (box.get(SEARCH_HISTORY_ENABLED_KEY) as bool?) ?? true;

    if (!isEnabled) {
      return;
    }

    await box.put(SEARCH_HISTORY_KEY, history);
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
    dynamic queueProvider,
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

    final isYouTube = _isYouTubeSong(song);

    if (isYouTube) {
      _buildYouTubeRelatedQueueInBackground(
        currentSong: songInfo,
        seedVideoId: songInfo.videoId,
        queueProvider: queueProvider,
      );
    } else {
      _buildRadioQueueInBackground(
        currentSong: songInfo,
        seedVideoId: songInfo.videoId,
        queueProvider: queueProvider,
      );
    }
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

  // ---------------------------------------------------------------------------
  // YOUTUBE RELATED QUEUE - BACKGROUND
  // ---------------------------------------------------------------------------

  void _buildYouTubeRelatedQueueInBackground({
    required SongInfo currentSong,
    required String seedVideoId,
    required dynamic queueProvider,
  }) {
    Future<void>(() async {
      try {
        debugPrint(
          'Background related queue generation started for '
          '$seedVideoId',
        );

        final songsList = await _relatedSongService.createSongListWithRelated(
          currentSong,
          seedVideoId,
        );

        if (songsList.isEmpty) {
          return;
        }

        final songIndex = songsList.indexWhere(
          (s) => s.videoId == currentSong.videoId,
        );

        try {
          queueProvider.setQueue(
            songsList,
            currentIndex: songIndex >= 0 ? songIndex : 0,
            playlistId: 'search_results',
            playlistName: 'Search Results',
          );

          debugPrint(
            'Background YouTube queue ready: '
            '${songsList.length} songs',
          );
        } catch (e) {
          debugPrint('Failed to update YouTube queue: $e');
        }
      } catch (e) {
        /*
         * VERY IMPORTANT:
         *
         * Related songs are optional.
         * Their failure must NEVER stop playback.
         */
        debugPrint('Background YouTube related queue failed: $e');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // YOUTUBE MUSIC RADIO - BACKGROUND
  // ---------------------------------------------------------------------------

  void _buildRadioQueueInBackground({
    required SongInfo currentSong,
    required String seedVideoId,
    required dynamic queueProvider,
  }) {
    Future<void>(() async {
      try {
        debugPrint(
          'Background radio queue generation started for '
          '$seedVideoId',
        );

        await _buildExpandedRadioQueueIncremental(
          currentSong: currentSong,
          seedVideoId: seedVideoId,
          queueProvider: queueProvider,
        );

        debugPrint(
          'Background radio queue generation completed for '
          '$seedVideoId',
        );
      } catch (e, stackTrace) {
        /*
         * Radio generation is completely optional.
         *
         * If YouTube changes its response or a radio request fails,
         * the currently playing song continues normally.
         */

        debugPrint('Background radio queue failed: $e');

        debugPrint('$stackTrace');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // EXPANDED RADIO QUEUE
  // ---------------------------------------------------------------------------

  Future<List<SongInfo>> _buildExpandedRadioQueueIncremental({
    required SongInfo currentSong,
    required String seedVideoId,
    required dynamic queueProvider,
  }) async {
    final random = Random();

    final seenVideoIds = <String>{currentSong.videoId};

    var songs = <SongInfo>[currentSong];

    /*
     * The clicked song has already been placed into the queue.
     *
     * We DO NOT call setQueue() again here.
     */

    List<SongInfo> getUniqueSongs(Iterable<SongInfo> incoming) {
      final unique = <SongInfo>[];

      for (final item in incoming) {
        if (item.videoId.isEmpty) {
          continue;
        }

        if (seenVideoIds.contains(item.videoId)) {
          continue;
        }

        seenVideoIds.add(item.videoId);

        unique.add(item);

        if (seenVideoIds.length >= _maxSearchQueueSize) {
          break;
        }
      }

      return unique;
    }

    // -------------------------------------------------------------------------
    // FIRST RADIO REQUEST
    // -------------------------------------------------------------------------

    try {
      final initialRadioData = await ytApi.getRadioSongs(
        seedVideoId,
        limit: _initialRadioBatchLimit,
      );

      final rawTracks = initialRadioData['tracks'];

      if (rawTracks is List) {
        final initialUniqueSongs = getUniqueSongs(
          _mapRadioTracksToSongInfo(rawTracks),
        );

        if (initialUniqueSongs.isNotEmpty) {
          try {
            queueProvider.addAllToQueue(initialUniqueSongs);

            songs = List<SongInfo>.from(queueProvider.queue);

            debugPrint(
              'Added ${initialUniqueSongs.length} radio songs. '
              'Queue size: ${songs.length}',
            );
          } catch (e) {
            debugPrint('Failed to add initial radio songs to queue: $e');
          }
        }
      }
    } catch (e) {
      /*
       * This is the exact area that was previously causing:
       *
       * NoSuchMethodError:
       * The method '[]' was called on null.
       *
       * It is now isolated from playback.
       */

      debugPrint('Initial radio request failed: $e');
    }

    // -------------------------------------------------------------------------
    // EXTRA RADIO REQUESTS
    // -------------------------------------------------------------------------

    for (
      var i = 0;
      i < _extraRadioFetchCount && songs.length < _maxSearchQueueSize;
      i++
    ) {
      if (songs.isEmpty) {
        break;
      }

      final randomSeedSong = songs[random.nextInt(songs.length)];

      try {
        final extraRadioData = await ytApi.getRadioSongs(
          randomSeedSong.videoId,
          limit: _initialRadioBatchLimit,
        );

        final rawTracks = extraRadioData['tracks'];

        if (rawTracks is! List) {
          debugPrint(
            'Radio response had no valid tracks for '
            '${randomSeedSong.videoId}',
          );

          continue;
        }

        final extraUniqueSongs = getUniqueSongs(
          _mapRadioTracksToSongInfo(rawTracks),
        );

        if (extraUniqueSongs.isNotEmpty) {
          try {
            queueProvider.addAllToQueue(extraUniqueSongs);

            songs = List<SongInfo>.from(queueProvider.queue);

            debugPrint(
              'Added ${extraUniqueSongs.length} extra radio songs. '
              'Queue size: ${songs.length}',
            );
          } catch (e) {
            debugPrint('Failed adding extra radio songs: $e');
          }
        }
      } catch (e) {
        /*
         * One bad radio seed should NOT stop the remaining radio requests.
         */

        debugPrint(
          'Extra radio fetch failed for '
          '${randomSeedSong.videoId}: $e',
        );
      }
    }

    return songs.take(_maxSearchQueueSize).toList();
  }

  // ---------------------------------------------------------------------------
  // RADIO TRACK MAPPING
  // ---------------------------------------------------------------------------

  List<SongInfo> _mapRadioTracksToSongInfo(List tracks) {
    final result = <SongInfo>[];

    for (final track in tracks) {
      if (track is! Map) {
        continue;
      }

      try {
        final videoId = track['videoId']?.toString() ?? '';

        if (videoId.isEmpty) {
          continue;
        }

        final title = track['title']?.toString() ?? 'Unknown Title';

        final trackArtists = track['artists'];

        final artists = <Artist>[];

        if (trackArtists is List) {
          for (final artist in trackArtists) {
            if (artist is Map) {
              artists.add(
                Artist(
                  name: artist['name']?.toString() ?? 'Unknown Artist',
                  id: artist['id']?.toString() ?? '',
                ),
              );
            }
          }
        }

        if (artists.isEmpty) {
          artists.add(Artist(name: 'Unknown Artist', id: ''));
        }

        final thumbnails = track['thumbnails'];

        String thumbnailUrl = '';

        if (thumbnails is List && thumbnails.isNotEmpty) {
          /*
           * Pick the last/highest resolution thumbnail,
           * but safely handle malformed data.
           */

          final last = thumbnails.last;

          if (last is Map) {
            thumbnailUrl = last['url']?.toString() ?? '';
          }
        }

        final durationSeconds = _toInt(track['duration_seconds'], 0);

        result.add(
          SongInfo(
            videoId: videoId,
            name: title,
            artists: artists,
            thumbnails: [
              Thumbnail(url: thumbnailUrl, width: 1280, height: 720),
            ],
            duration: Duration(seconds: durationSeconds),
          ),
        );
      } catch (e) {
        debugPrint('Failed to map radio track: $e');
      }
    }

    return result;
  }
}

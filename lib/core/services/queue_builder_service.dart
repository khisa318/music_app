import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/song_model.dart';
import '../providers/queued_provider.dart';
import 'related_song_service.dart';
import 'yt_music_api.dart' as yt_api;

class QueueBuilderService {
  final RelatedSongService _relatedSongService = RelatedSongService();

  static const int maxQueueSize = 250;
  static const int initialBatchLimit = 50;
  static const int extraFetchCount = 6;

  void buildInBackground({
    required SongInfo currentSong,
    required QueueProvider queueProvider,
    required String playlistId,
    required String playlistName,
    bool useYouTubeRelated = false,
  }) {
    Future<void>(() async {
      try {
        if (useYouTubeRelated) {
          await _buildYouTubeRelatedQueue(
            currentSong: currentSong,
            queueProvider: queueProvider,
            playlistId: playlistId,
            playlistName: playlistName,
          );
        } else {
          await _buildExpandedRadioQueueIncremental(
            currentSong: currentSong,
            queueProvider: queueProvider,
          );
        }
      } catch (e, stackTrace) {
        debugPrint('Background queue generation failed: $e');
        debugPrint('$stackTrace');
      }
    });
  }

  Future<void> _buildYouTubeRelatedQueue({
    required SongInfo currentSong,
    required QueueProvider queueProvider,
    required String playlistId,
    required String playlistName,
  }) async {
    final songsList = await _relatedSongService.createSongListWithRelated(
      currentSong,
      currentSong.videoId,
    );

    if (songsList.isEmpty) {
      return;
    }

    final songIndex = songsList.indexWhere(
      (song) => song.videoId == currentSong.videoId,
    );

    queueProvider.setQueue(
      songsList,
      currentIndex: songIndex >= 0 ? songIndex : 0,
      playlistId: playlistId,
      playlistName: playlistName,
    );
  }

  Future<List<SongInfo>> _buildExpandedRadioQueueIncremental({
    required SongInfo currentSong,
    required QueueProvider queueProvider,
  }) async {
    final random = Random();

    final seenVideoIds = <String>{currentSong.videoId};

    var songs = <SongInfo>[currentSong];

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

        if (seenVideoIds.length >= maxQueueSize) {
          break;
        }
      }

      return unique;
    }

    try {
      final initialRadioData = await yt_api.getRadioSongs(
        currentSong.videoId,
        limit: initialBatchLimit,
      );

      final rawTracks = initialRadioData['tracks'];

      if (rawTracks is List) {
        final initialUniqueSongs = getUniqueSongs(
          _mapRadioTracksToSongInfo(rawTracks),
        );

        if (initialUniqueSongs.isNotEmpty) {
          queueProvider.addAllToQueue(initialUniqueSongs);

          songs = List<SongInfo>.from(queueProvider.queue);
        }
      }
    } catch (e) {
      debugPrint('Initial radio request failed: $e');
    }

    for (
      var i = 0;
      i < extraFetchCount && songs.length < maxQueueSize;
      i++
    ) {
      if (songs.isEmpty) {
        break;
      }

      final randomSeedSong = songs[random.nextInt(songs.length)];

      try {
        final extraRadioData = await yt_api.getRadioSongs(
          randomSeedSong.videoId,
          limit: initialBatchLimit,
        );

        final rawTracks = extraRadioData['tracks'];

        if (rawTracks is! List) {
          continue;
        }

        final extraUniqueSongs = getUniqueSongs(
          _mapRadioTracksToSongInfo(rawTracks),
        );

        if (extraUniqueSongs.isNotEmpty) {
          queueProvider.addAllToQueue(extraUniqueSongs);

          songs = List<SongInfo>.from(queueProvider.queue);
        }
      } catch (e) {
        debugPrint(
          'Extra radio fetch failed for '
          '${randomSeedSong.videoId}: $e',
        );
      }
    }

    return songs.take(maxQueueSize).toList();
  }

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

  int _toInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

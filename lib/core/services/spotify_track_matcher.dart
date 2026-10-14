import 'dart:async';
import 'dart:math' as math;

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import 'spotify_playlist_service.dart';

/// Matches Spotify tracks to playable YouTube Music songs.
///
/// Spotify only provides metadata, so every imported track is searched on
/// YouTube Music and scored by title, artist and duration before being stored
/// in the same shape the app's local playlists use.
class SpotifyTrackMatcher {
  final YTMusic _ytMusic;

  SpotifyTrackMatcher({YTMusic? ytMusic})
    : _ytMusic = ytMusic ?? GetIt.I<YTMusic>();

  static const double _minimumScore = 0.6;
  static const int _candidateLimit = 8;

  /// Matches every track, returning only the ones that could be matched.
  ///
  /// [onMatched] fires for each track as soon as it is matched, allowing
  /// callers to persist results incrementally. [onProgress] is invoked with the
  /// number of tracks processed so far and the total.
  Future<List<Map<String, dynamic>>> matchAll(
    List<SpotifyTrack> tracks, {
    int concurrency = 3,
    FutureOr<void> Function(Map<String, dynamic> song)? onMatched,
    void Function(int completed, int total)? onProgress,
  }) async {
    final matched = <Map<String, dynamic>>[];
    if (tracks.isEmpty) return matched;

    for (var i = 0; i < tracks.length; i += concurrency) {
      final end = math.min(i + concurrency, tracks.length);
      final batch = tracks.sublist(i, end);

      final results = await Future.wait(batch.map(_matchTrack));

      for (final song in results) {
        if (song == null) continue;
        matched.add(song);
        if (onMatched != null) await onMatched(song);
      }

      onProgress?.call(end, tracks.length);
    }

    return matched;
  }

  Future<Map<String, dynamic>?> _matchTrack(SpotifyTrack track) async {
    try {
      final query = [
        track.title,
        track.primaryArtist,
      ].where((e) => e.isNotEmpty).join(' ');

      final results = await _ytMusic.searchSongs(query);
      if (results.isEmpty) return null;

      SongDetailed? best;
      double bestScore = 0.0;

      for (final song in results.take(_candidateLimit)) {
        final titleScore = _similarity(track.title, song.name);
        final artistScore = _similarity(track.primaryArtist, song.artist.name);
        final durationScore = _durationScore(track.durationMs, song.duration);

        final score =
            titleScore * 0.5 + artistScore * 0.3 + durationScore * 0.2;

        if (score > bestScore) {
          bestScore = score;
          best = song;
        }
      }

      if (best == null || bestScore < _minimumScore) return null;

      return _toSongMap(best);
    } catch (e) {
      debugPrint('Spotify match failed for "${track.title}": $e');
      return null;
    }
  }

  static Map<String, dynamic> _toSongMap(SongDetailed song) {
    final thumbnail = song.thumbnails.isNotEmpty
        ? song.thumbnails.last.url
        : '';

    return {
      'id': song.videoId,
      'title': song.name,
      'artist': song.artist.name,
      'artistId': song.artist.artistId ?? '',
      'thumbnail': thumbnail,
      'duration': song.duration ?? 0,
    };
  }

  /// Rewards candidates whose length is close to the Spotify track's.
  static double _durationScore(int spotifyMs, int? youtubeSeconds) {
    if (spotifyMs <= 0 || youtubeSeconds == null || youtubeSeconds <= 0) {
      return 0.5;
    }
    final spotifySeconds = spotifyMs / 1000.0;
    final difference = (spotifySeconds - youtubeSeconds).abs();
    final ratio = (difference / spotifySeconds).clamp(0.0, 1.0);
    return 1.0 - ratio;
  }

  static double _similarity(String a, String b) {
    final normalizedA = _normalize(a);
    final normalizedB = _normalize(b);

    if (normalizedA.isEmpty || normalizedB.isEmpty) return 0.0;

    final distance = _levenshtein(normalizedA, normalizedB);
    final maxLength = math.max(normalizedA.length, normalizedB.length);
    return 1.0 - (distance / maxLength);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(
          RegExp(
            r'\b(official|video|audio|music|song|track|remix|cover|live|feat|ft|with)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
      }
      for (var k = 0; k <= b.length; k++) {
        previous[k] = current[k];
      }
    }

    return previous[b.length];
  }
}

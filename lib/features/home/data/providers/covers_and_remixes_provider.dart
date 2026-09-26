import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../core/models/song_model.dart';
import '../../../../core/services/related_song_service.dart';

/// Alternate versions of music the listener has actually played.
///
/// YouTube Music builds its "Covers and remixes" shelf from recent listening,
/// but exposes no standalone endpoint for it. This walks the locally stored
/// play history and pulls each seed track's related videos, which is the same
/// signal YT Music uses, then keeps only the alternate-version candidates.
class CoversAndRemixesProvider extends ChangeNotifier {
  final RelatedSongService _relatedSongService = RelatedSongService();

  /// Seeds are the most recently played tracks, newest first.
  static const int _maxSeeds = 3;

  /// Candidates pulled per seed before ranking.
  static const int _maxPerSeed = 12;

  /// Final shelf size.
  static const int _maxResults = 8;

  /// Cheap pre-filter: related-video titles for alternate versions almost
  /// always contain one of these words. Keeps the network payload small and
  /// stops unrelated uploads crowding out real covers.
  static const List<String> _versionKeywords = [
    'cover',
    'remix',
    'acoustic',
    'unplugged',
    'live',
    'instrumental',
    'karaoke',
    'rework',
    'flip',
    'sped up',
    'slowed',
    'reverb',
    'mashup',
    'bootleg',
    'vip',
  ];

  List<SongInfo> _results = [];
  bool _isLoading = false;

  List<SongInfo> get results => _results;
  bool get isLoading => _isLoading;

  /// Seeds to look up alternate versions for.
  ///
  /// [seedSongs] is the listener's play history, newest first.
  Future<void> load(
    List<Map<String, dynamic>> seedSongs, {
    bool forceRefresh = false,
  }) async {
    if (_isLoading) return;
    if (_results.isNotEmpty && !forceRefresh) return;

    final seeds = seedSongs
        .map(_toSeed)
        .whereType<SongInfo>()
        .take(_maxSeeds)
        .toList();

    if (seeds.isEmpty) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final seedIds = seeds.map((s) => s.videoId).toSet();
      final collected = <SongInfo>[];

      for (final seed in seeds) {
        try {
          final related = await _relatedSongService.getRelatedSongs(
            seed.videoId,
          );
          for (final candidate in related) {
            if (seedIds.contains(candidate.videoId)) continue;
            if (!_looksLikeAlternateVersion(candidate.name)) continue;
            collected.add(candidate);
            if (collected.length >= _maxSeeds * _maxPerSeed) break;
          }
        } catch (e) {
          debugPrint('Covers/remixes lookup failed for ${seed.name}: $e');
        }
        if (collected.length >= _maxSeeds * _maxPerSeed) break;
      }

      _results = _rank(collected).take(_maxResults).toList();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Prioritise explicit covers and remixes over generic live/unplugged takes,
  /// then prefer the shorter, radio-friendly runtime.
  List<SongInfo> _rank(List<SongInfo> songs) {
    final scored = songs.map((song) {
      final title = song.name.toLowerCase();
      var score = 0;
      if (title.contains('cover')) score += 3;
      if (title.contains('remix') || title.contains('mashup')) score += 3;
      if (title.contains('rework') || title.contains('flip')) score += 2;
      if (title.contains('acoustic') || title.contains('unplugged')) score += 2;
      if (title.contains('live')) score += 1;
      if (title.contains('instrumental') || title.contains('karaoke')) score += 1;
      if (title.contains('official')) score += 1;

      final minutes = song.duration.inMinutes;
      if (minutes > 0 && minutes < 9) score += 1;

      return (song: song, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

    final seen = <String>{};
    final unique = <SongInfo>[];
    for (final entry in scored) {
      if (seen.add(entry.song.videoId)) unique.add(entry.song);
    }
    return unique;
  }

  bool _looksLikeAlternateVersion(String title) {
    final lower = title.toLowerCase();
    return _versionKeywords.any(lower.contains);
  }

  SongInfo? _toSeed(Map<String, dynamic> song) {
    final rawId = song['id'] ?? song['videoId'];
    final id = rawId?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final title = (song['title'] ?? song['name'])?.toString() ?? '';
    if (title.isEmpty) return null;

    final artistNames = <String>[];
    final rawArtists = song['artists'];
    if (rawArtists is List) {
      for (final a in rawArtists) {
        if (a is Map && a['name'] != null) {
          artistNames.add(a['name'].toString());
        } else if (a != null) {
          artistNames.add(a.toString());
        }
      }
    }
    if (artistNames.isEmpty && song['artist'] != null) {
      artistNames.add(song['artist'].toString());
    }

    return SongInfo(
      videoId: id,
      name: title,
      artists: [
        Artist(name: artistNames.isEmpty ? '' : artistNames.first, id: ''),
      ],
      thumbnails: [
        Thumbnail(url: (song['thumbnail'] ?? '').toString(), width: 480, height: 480),
      ],
      duration: Duration(seconds: _toSeconds(song['duration'])),
    );
  }

  /// History entries store duration in seconds, but a few legacy rows hold a
  /// string, so parse defensively instead of throwing mid-build.
  int _toSeconds(dynamic value) {
    if (value is int) return math.max(0, value);
    if (value is num) return math.max(0, value.toInt());
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

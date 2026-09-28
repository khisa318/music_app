import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/models/song_model.dart';
import '../../../../core/services/related_song_service.dart';

/// Alternate versions of music the listener has actually played: covers,
/// remixes, acoustic and live takes.
///
/// YT Music builds the same shelf from recent listening but exposes no
/// standalone endpoint for it, so this seeds from local play history and looks
/// the alternate versions up explicitly.
///
/// The lookup has two sources because neither is sufficient alone:
///
///  * YT Music search for `"<track> cover"` / `"<track> remix"`, which is what
///    actually surfaces alternate versions.
///  * The seed's related videos, which reliably surface live and unplugged
///    takes that search tends to miss.
///
/// Searching by related-video title alone left the shelf empty most of the
/// time, because mainstream uploads rarely carry "cover" in their title.
class CoversAndRemixesProvider extends ChangeNotifier {
  final YTMusic _ytMusic = GetIt.I<YTMusic>();
  final RelatedSongService _relatedSongService = RelatedSongService();

  /// Seeds are the most recently played tracks, newest first.
  static const int _maxSeeds = 2;

  /// Final shelf size.
  static const int _maxResults = 8;

  /// Words that describe a track's *form* rather than being part of its name.
  static const Set<String> _noiseWords = {
    'feat',
    'ft',
    'featuring',
    'with',
    'official',
    'video',
    'audio',
    'music',
    'lyric',
    'lyrics',
    'hd',
    'hq',
    'mv',
    'm/v',
    'version',
    'remaster',
    'remastered',
    'edition',
    'deluxe',
    'bonus',
    'track',
    'quality',
    'cover',
    'remix',
    'acoustic',
    'unplugged',
    'live',
    'instrumental',
    'karaoke',
    'rework',
    'flip',
    'mashup',
    'bootleg',
    'vip',
    'sped',
    'slowed',
    'reverb',
    'mix',
  };

  /// Qualifiers appended to the seed title when searching.
  static const List<String> _searchQualifiers = ['cover', 'remix'];

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
        .map(SongInfo.fromHistoryMap)
        .whereType<SongInfo>()
        .take(_maxSeeds)
        .toList();

    if (seeds.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final collected = <SongInfo>[];
      final seen = seeds.map((s) => s.videoId).toSet();

      for (final seed in seeds) {
        for (final candidate in await _searchAlternateVersions(seed)) {
          if (!seen.add(candidate.videoId)) continue;
          if (!_looksLikeAlternateVersion(candidate.name)) continue;
          if (!_matchesSeedTitle(candidate.name, seed.name)) continue;
          collected.add(candidate);
        }
      }

      if (collected.length < _maxResults) {
        for (final candidate in await _relatedAlternateVersions(seeds)) {
          if (!seen.add(candidate.videoId)) continue;
          if (!_looksLikeAlternateVersion(candidate.name)) continue;
          if (!seeds.any((s) => _matchesSeedTitle(candidate.name, s.name))) {
            continue;
          }
          collected.add(candidate);
        }
      }

      _results = _rank(collected).take(_maxResults).toList();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Explicit lookups for the seed's cover and remix versions.
  Future<List<SongInfo>> _searchAlternateVersions(SongInfo seed) async {
    final found = <SongInfo>[];

    for (final qualifier in _searchQualifiers) {
      try {
        final results = await _ytMusic.search('${seed.name} $qualifier');
        for (final result in results) {
          if (result is! SongDetailedSearchResult) continue;
          final song = result.songDetailed;
          found.add(
            SongInfo(
              videoId: song.videoId,
              name: song.name,
              artists: [
                Artist(name: song.artist.name, id: song.artist.artistId ?? ''),
              ],
              thumbnails: song.thumbnails
                  .map(
                    (t) =>
                        Thumbnail(url: t.url, width: t.width, height: t.height),
                  )
                  .toList(),
              duration: Duration(seconds: song.duration ?? 0),
            ),
          );
        }
      } catch (e) {
        debugPrint(
          'Covers/remixes search failed for "$seed.name $qualifier": $e',
        );
      }
    }

    return found;
  }

  /// Live/unplugged takes from each seed's related videos.
  Future<List<SongInfo>> _relatedAlternateVersions(List<SongInfo> seeds) async {
    final found = <SongInfo>[];

    for (final seed in seeds) {
      try {
        found.addAll(await _relatedSongService.getRelatedSongs(seed.videoId));
      } catch (e) {
        debugPrint('Covers/remixes related lookup failed for ${seed.name}: $e');
      }
    }

    return found;
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
      if (title.contains('instrumental') || title.contains('karaoke')) {
        score += 1;
      }
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
    for (final qualifier in _searchQualifiers) {
      if (lower.contains(qualifier)) return true;
    }
    return [
      'acoustic',
      'unplugged',
      'live',
      'instrumental',
      'karaoke',
      'rework',
      'flip',
      'mashup',
      'bootleg',
    ].any(lower.contains);
  }

  /// Guards against covers of a completely different track.
  ///
  /// The search query pulls in loosely related results, so a candidate has to
  /// share at least one meaningful word with the seed it was found for.
  bool _matchesSeedTitle(String candidate, String seed) {
    final seedWords = _significantWords(seed);
    if (seedWords.isEmpty) return false;

    final candidateWords = _significantWords(candidate);
    return seedWords.any(candidateWords.contains);
  }

  Set<String> _significantWords(String title) {
    return title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 3 && !_noiseWords.contains(w))
        .toSet();
  }
}

import 'dart:convert';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/models/song_model.dart';
import '../../../../core/providers/connectivity_provider.dart';
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

/// What one lookup pass found, and how much of it was actually able to ask.
///
/// A pass that found nothing because the network refused the question is not
/// the same as a pass that asked and was told there is nothing there. Only the
/// second one is an answer worth caching, and the two are told apart by
/// [succeeded] being zero.
typedef _Lookup = ({
  List<SongInfo> items,
  int attempted,
  int succeeded,
});

class CoversAndRemixesProvider extends ChangeNotifier {
  /// Resolved on first lookup rather than at construction, so a cached shelf
  /// can be served without the network client ever being touched.
  YTMusic? _ytMusicInstance;

  YTMusic get _ytMusic => _ytMusicInstance ??= GetIt.I<YTMusic>();

  /// Likewise lazy: [RelatedSongService] resolves its own dependencies in its
  /// constructor, which is only worth paying for on an actual lookup.
  RelatedSongService? _relatedSongServiceInstance;

  RelatedSongService get _relatedSongService =>
      _relatedSongServiceInstance ??= RelatedSongService();

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

  /// Where the resolved shelf is cached between launches.
  ///
  /// The lookup costs several YT Music round trips, so without this every cold
  /// start re-ran them and the shelf was empty for the whole time it took — and
  /// permanently empty offline.
  static const String _cacheBoxName = 'covers_and_remixes_cache';
  static const String _cacheKey = 'shelf';

  /// How long a cached shelf is served without going back to the network.
  static const Duration _cacheTtl = Duration(hours: 12);

  List<SongInfo> _results = [];
  bool _isLoading = false;

  /// Whether [_results] came off disk rather than from this session's lookup.
  bool _isFromCache = false;

  /// When the cached shelf was written.
  DateTime? _cachedAt;

  /// The seeds the cached shelf was built from, so a new play re-looks-up even
  /// inside the TTL.
  String _cachedSeedSignature = '';

  List<SongInfo> get results => _results;
  bool get isLoading => _isLoading;
  bool get isFromCache => _isFromCache;

  CoversAndRemixesProvider() {
    _restoreFromCache();
  }

  /// Whether the network is known to be usable.
  ///
  /// Treated as available until connectivity has actually reported in, so a
  /// first run is never blocked from looking up its shelf.
  bool get _isOnline {
    if (!GetIt.I.isRegistered<ConnectivityProvider>()) return true;

    final connectivity = GetIt.I<ConnectivityProvider>();
    if (!connectivity.isInitialized) return true;

    return connectivity.canPerformNetworkOperations();
  }

  bool get _cacheIsStale {
    final cachedAt = _cachedAt;
    if (cachedAt == null) return true;

    return DateTime.now().difference(cachedAt) > _cacheTtl;
  }

  /// Serves the cached shelf immediately, before any network work.
  ///
  /// Restored in the constructor so the section has something to render on the
  /// first frame instead of a shimmer. An entry with no songs still counts as
  /// cached, so a track that genuinely has no alternate versions is not
  /// re-searched on every launch.
  void _restoreFromCache() {
    try {
      final raw = Hive.box<String>(_cacheBoxName).get(_cacheKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final songs = <SongInfo>[];
      final cachedSongs = decoded['songs'];
      if (cachedSongs is List) {
        for (final entry in cachedSongs) {
          if (entry is! Map) continue;
          final song = SongInfo.fromHistoryMap(
            Map<String, dynamic>.from(entry),
          );
          if (song != null) songs.add(song);
        }
      }

      _results = songs.take(_maxResults).toList();
      _cachedSeedSignature = decoded['seedSignature']?.toString() ?? '';
      _cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
      _isFromCache = true;
    } catch (e) {
      debugPrint('Covers/remixes cache restore failed: $e');
    }
  }

  /// Writes the resolved shelf so the next launch can skip the lookups.
  ///
  /// Stored in the play-history row shape so [SongInfo.fromHistoryMap] reads it
  /// back, rather than adding a second serialization format for songs.
  Future<void> _persistToCache(String seedSignature) async {
    try {
      await Hive.box<String>(_cacheBoxName).put(
        _cacheKey,
        jsonEncode({
          'cachedAt': DateTime.now().toIso8601String(),
          'seedSignature': seedSignature,
          'songs': _results.map(_toCacheMap).toList(),
        }),
      );
    } catch (e) {
      debugPrint('Covers/remixes cache write failed: $e');
    }
  }

  /// Flattens a song for the cache, keeping the largest thumbnail on offer.
  Map<String, dynamic> _toCacheMap(SongInfo song) {
    var thumbnail = '';
    var widest = -1;

    for (final candidate in song.thumbnails) {
      if (candidate.url.isEmpty) continue;
      if (candidate.width > widest) {
        widest = candidate.width;
        thumbnail = candidate.url;
      }
    }

    return {
      'id': song.videoId,
      'title': song.name,
      'artists': song.artists.map((a) => {'name': a.name, 'id': a.id}).toList(),
      'thumbnail': thumbnail,
      'duration': song.duration.inSeconds,
    };
  }

  /// Re-runs the lookup even if a cached shelf is still inside its TTL.
  ///
  /// Takes the play history from the caller rather than reaching for it here,
  /// so the provider stays independent of [PlayerProvider].
  Future<void> refresh(List<Map<String, dynamic>> seedSongs) {
    return load(seedSongs, forceRefresh: true);
  }

  /// Seeds to look up alternate versions for.
  ///
  /// [seedSongs] is the listener's play history, newest first. A cached shelf is
  /// served as-is while it is fresh, shown immediately and refreshed behind the
  /// scenes once it is stale, and never re-looked-up with no network.
  Future<void> load(
    List<Map<String, dynamic>> seedSongs, {
    bool forceRefresh = false,
  }) async {
    if (_isLoading) return;

    final seeds = seedSongs
        .map(SongInfo.fromHistoryMap)
        .whereType<SongInfo>()
        .take(_maxSeeds)
        .toList();
    final seedSignature = seeds.map((s) => s.videoId).join(',');

    if (!forceRefresh) {
      if (_isFromCache) {
        // Served as-is only while the entry still matches the seeds and is
        // inside its TTL. A stale entry, or one built from different seeds, is
        // refreshed rather than trusted.
        if (seedSignature == _cachedSeedSignature && !_cacheIsStale) return;
      } else if (_results.isNotEmpty) {
        // Already resolved from the network during this session.
        return;
      }
    }

    if (seeds.isEmpty) return;
    if (!_isOnline) return;

    _isLoading = true;
    notifyListeners();

    try {
      final collected = <SongInfo>[];
      final seen = seeds.map((s) => s.videoId).toSet();
      var attempted = 0;
      var succeeded = 0;

      for (final seed in seeds) {
        final pass = await _searchAlternateVersions(seed);
        attempted += pass.attempted;
        succeeded += pass.succeeded;

        for (final candidate in pass.items) {
          if (!seen.add(candidate.videoId)) continue;
          if (!_looksLikeAlternateVersion(candidate.name)) continue;
          if (!_matchesSeedTitle(candidate.name, seed.name)) continue;
          collected.add(candidate);
        }
      }

      final related = await _relatedAlternateVersions(seeds);
      attempted += related.attempted;
      succeeded += related.succeeded;

      for (final candidate in related.items) {
        if (!seen.add(candidate.videoId)) continue;
        if (!_looksLikeAlternateVersion(candidate.name)) continue;
        if (!seeds.any((s) => _matchesSeedTitle(candidate.name, s.name))) {
          continue;
        }
        collected.add(candidate);
      }

      // Nothing got through, so this refresh learned nothing about the shelf
      // rather than learning it was empty. Connectivity already said the
      // network was usable, so this is a rate limit, a captive portal or YT
      // having a moment - the cases a cache exists for. Replacing the shelf
      // with what we have would blank it and then cache that blankness as
      // fresh for the next 12 hours, which is the one outcome the cache is
      // meant to prevent.
      if (succeeded == 0 && attempted > 0) {
        if (seedSignature != _cachedSeedSignature) {
          // The seeds moved, so what is cached describes a different track and
          // is not this shelf to show. Dropped, but not written: the stored
          // entry is left for a later attempt rather than overwritten.
          _results = [];
          _isFromCache = false;
        }
        return;
      }

      _results = _rank(collected).take(_maxResults).toList();
      _isFromCache = false;
      _cachedSeedSignature = seedSignature;
      _cachedAt = DateTime.now();

      await _persistToCache(seedSignature);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Explicit lookups for the seed's cover and remix versions.
  Future<_Lookup> _searchAlternateVersions(SongInfo seed) async {
    final found = <SongInfo>[];
    var attempted = 0;
    var succeeded = 0;

    for (final qualifier in _searchQualifiers) {
      attempted++;
      try {
        final results = await _ytMusic.search('${seed.name} $qualifier');
        succeeded++;
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
          'Covers/remixes search failed for "${seed.name} $qualifier": $e',
        );
      }
    }

    return (items: found, attempted: attempted, succeeded: succeeded);
  }

  /// Live/unplugged takes from each seed's related videos.
  Future<_Lookup> _relatedAlternateVersions(List<SongInfo> seeds) async {
    final found = <SongInfo>[];
    var attempted = 0;
    var succeeded = 0;

    for (final seed in seeds) {
      attempted++;
      try {
        found.addAll(await _relatedSongService.getRelatedSongs(seed.videoId));
        succeeded++;
      } catch (e) {
        debugPrint('Covers/remixes related lookup failed for ${seed.name}: $e');
      }
    }

    return (items: found, attempted: attempted, succeeded: succeeded);
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

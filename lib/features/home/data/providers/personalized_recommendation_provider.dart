// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/models/song_model.dart';
import '../../../../core/providers/stats_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/services/related_song_service.dart';
import '../../data/providers/home_screen_provider.dart';
import '../../../trending/data/provider/trending_provider.dart';

part 'personalized_recommendation_provider.g.dart';

/// Represents a user's music preference profile built from listening history.
@HiveType(typeId: 20)
class UserPreferenceProfile {
  @HiveField(0)
  final Map<String, double> artistAffinities; // artist name -> affinity score (0.0-1.0)

  @HiveField(1)
  final Map<String, double> songAffinities; // videoId -> affinity score

  @HiveField(2)
  final Map<String, int> skipCounts; // videoId -> number of skips

  @HiveField(3)
  final Map<String, int> completionCounts; // videoId -> number of completions

  @HiveField(4)
  final DateTime lastUpdated;

  @HiveField(5)
  final int totalSongsAnalyzed;

  @HiveField(6)
  final List<String> preferredArtistIds; // top artist IDs for quick lookup

  UserPreferenceProfile({
    required this.artistAffinities,
    required this.songAffinities,
    required this.skipCounts,
    required this.completionCounts,
    required this.lastUpdated,
    required this.totalSongsAnalyzed,
    required this.preferredArtistIds,
  });

  factory UserPreferenceProfile.empty() {
    return UserPreferenceProfile(
      artistAffinities: {},
      songAffinities: {},
      skipCounts: {},
      completionCounts: {},
      lastUpdated: DateTime.now(),
      totalSongsAnalyzed: 0,
      preferredArtistIds: [],
    );
  }

  Map<String, dynamic> toJson() => {
    'artistAffinities': artistAffinities,
    'songAffinities': songAffinities,
    'skipCounts': skipCounts,
    'completionCounts': completionCounts,
    'lastUpdated': lastUpdated.millisecondsSinceEpoch,
    'totalSongsAnalyzed': totalSongsAnalyzed,
    'preferredArtistIds': preferredArtistIds,
  };

  factory UserPreferenceProfile.fromJson(Map<String, dynamic> json) {
    return UserPreferenceProfile(
      artistAffinities: Map<String, double>.from(
        json['artistAffinities'] ?? {},
      ),
      songAffinities: Map<String, double>.from(json['songAffinities'] ?? {}),
      skipCounts: Map<String, int>.from(json['skipCounts'] ?? {}),
      completionCounts: Map<String, int>.from(json['completionCounts'] ?? {}),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        json['lastUpdated'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      totalSongsAnalyzed: json['totalSongsAnalyzed'] as int? ?? 0,
      preferredArtistIds: List<String>.from(json['preferredArtistIds'] ?? []),
    );
  }

  UserPreferenceProfile copyWith({
    Map<String, double>? artistAffinities,
    Map<String, double>? songAffinities,
    Map<String, int>? skipCounts,
    Map<String, int>? completionCounts,
    DateTime? lastUpdated,
    int? totalSongsAnalyzed,
    List<String>? preferredArtistIds,
  }) {
    return UserPreferenceProfile(
      artistAffinities: artistAffinities ?? this.artistAffinities,
      songAffinities: songAffinities ?? this.songAffinities,
      skipCounts: skipCounts ?? this.skipCounts,
      completionCounts: completionCounts ?? this.completionCounts,
      lastUpdated: lastUpdated ?? DateTime.now(),
      totalSongsAnalyzed: totalSongsAnalyzed ?? this.totalSongsAnalyzed,
      preferredArtistIds: preferredArtistIds ?? this.preferredArtistIds,
    );
  }
}

/// A personalized recommendation section with metadata.
class PersonalizedSection {
  final String title;
  final String subtitle;
  final List<SongInfo> songs;
  final SectionType type;
  final String? seedArtist; // For transparency - what artist seeded this

  PersonalizedSection({
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.type,
    this.seedArtist,
  });
}

enum SectionType {
  listenAgain, // Recently played, high affinity
  topArtists, // Songs from top artists
  artistMix, // Mix of songs from a specific top artist
  discovery, // New artists/genres related to preferences
  genreExploration, // Genre-based exploration
  trendingForYou, // Trending songs matching preferences
}

/// A small, time-limited cache entry for one artist's related tracks.
class _CachedRelatedSongs {
  final List<SongInfo> songs;
  final DateTime fetchedAt;

  const _CachedRelatedSongs(this.songs, this.fetchedAt);

  bool isFresh(DateTime now, Duration ttl) => now.difference(fetchedAt) < ttl;
}

class PersonalizedRecommendationProvider with ChangeNotifier {
  static const String _hiveBoxName = 'personalized_recommendations';
  static const String _profileKey = 'user_preference_profile';
  static const String _sectionsKey = 'personalized_sections';
  static const String _sectionsTimestampKey = 'personalized_sections_timestamp';
  static const String _sectionsSignatureKey = 'personalized_sections_signature';
  static const Duration _sectionsCacheDuration = Duration(hours: 6);
  static const int _maxRecommendationsPerSection = 6;
  static const int _maxTopArtists = 10;

  /// Number of artist mixes shown at once. Two keeps the feed varied without
  /// firing more network lookups than the old single-mix + discovery pair.
  static const int _maxArtistMixes = 2;
  static const int _minSongsForProfile =
      5; // Minimum songs before personalization kicks in

  /// How much relative weight recent (7-day) listening gets when ranking
  /// artists. High enough that a new flavour of music can unseat an all-time
  /// favourite, but not so high that lifetime taste is thrown away.
  static const double _recentArtistWeight = 0.65;

  // The persisted profile is bounded so it cannot grow forever for users with
  // very large libraries.
  static const int _maxTrackedSongs = 600;
  static const int _maxTrackedArtists = 80;
  static const int _maxTrackedEvents = 300;

  // Taste fingerprint: the first few distinct artists in recent playback.
  static const int _tasteArtistCount = 3;
  static const int _tasteHistoryWindow = 12;
  static const Duration _sourceChangeDebounceDuration = Duration(seconds: 4);

  // Small, bounded cache so re-ranking does not re-fetch the same artist's
  // related tracks every time another artist moves into the top slots.
  static const Duration _relatedCacheTtl = Duration(minutes: 30);
  static const int _relatedCacheSize = 8;
  static const int _relatedCacheSongs = 12;

  final StatsProvider _statsProvider;
  final PlayerProvider _playerProvider;
  final RelatedSongService _relatedSongService;
  final HomeScreenProvider _homeScreenProvider;
  final TrendingProvider _trendingProvider;

  Box<String>? _box;
  UserPreferenceProfile _profile = UserPreferenceProfile.empty();
  List<PersonalizedSection> _sections = [];
  bool _isLoading = false;
  bool _hasInitialized = false;
  String? _error;
  Timer? _sourceChangeDebounce;
  bool _sourceListenersAttached = false;
  bool _refreshQueued = false;
  String _sectionSourceSignature = '';
  final Map<String, _CachedRelatedSongs> _relatedCache = {};

  PersonalizedRecommendationProvider({
    required StatsProvider statsProvider,
    required PlayerProvider playerProvider,
    required RelatedSongService relatedSongService,
    required HomeScreenProvider homeScreenProvider,
    required TrendingProvider trendingProvider,
  }) : _statsProvider = statsProvider,
       _playerProvider = playerProvider,
       _relatedSongService = relatedSongService,
       _homeScreenProvider = homeScreenProvider,
       _trendingProvider = trendingProvider {
    _init();
  }

  // Getters
  UserPreferenceProfile get profile => _profile;
  List<PersonalizedSection> get sections => _sections;
  bool get isLoading => _isLoading;
  bool get hasInitialized => _hasInitialized;
  bool get isPersonalized => _profile.totalSongsAnalyzed >= _minSongsForProfile;
  String? get error => _error;

  Future<void> _init() async {
    _box = await Hive.openBox<String>(_hiveBoxName);
    await _loadProfile();
    await _loadCachedSections();
    _startSourceListeners();
    _hasInitialized = true;
    notifyListeners();

    // First run (or an expired cache): build the initial sections, otherwise
    // the home page would stay empty until new listening data arrived.
    if (_sections.isEmpty) {
      unawaited(updateRecommendations());
    } else {
      // The cached rows may have been built before the listener started
      // hearing a different kind of music. Regenerate only when the current
      // source fingerprint no longer matches the cached one.
      _scheduleRefreshIfSourcesChanged();
    }
  }

  /// Rebuilds recommendations when the data they depend on changes.
  ///
  /// On a cold start the home feed, playback history, stats and trending lists
  /// all load asynchronously. The first build can therefore see empty sources
  /// and cache an empty result, which made the home page say "start listening"
  /// even after songs had been played. These listeners retry once the sources
  /// arrive (or whenever the listener moves to a different artist).
  void _startSourceListeners() {
    if (_sourceListenersAttached) return;
    _sourceListenersAttached = true;

    _homeScreenProvider.addListener(_onSourceChanged);
    _trendingProvider.addListener(_onSourceChanged);
    _playerProvider.addListener(_onPlayerChanged);
    _statsProvider.addListener(_onSourceChanged);
  }

  /// Cheap fingerprint of the kind of music being played right now plus the
  /// home shelves used by the default/discovery rows.
  ///
  /// It deliberately uses artists rather than every song id: playing another
  /// track by the same artist does not warrant a full rebuild, while moving to
  /// a different artist/genre does.
  String _sourceSignature() {
    final artists = <String>[];
    for (final song in _playerProvider.lastPlayedSongs.take(
      _tasteHistoryWindow,
    )) {
      final artist = (song['artist'] ?? '').toString().trim();
      if (artist.isEmpty || artists.contains(artist)) continue;
      artists.add(artist);
      if (artists.length >= _tasteArtistCount) break;
    }

    if (artists.isEmpty) {
      artists.addAll(_profile.preferredArtistIds.take(_tasteArtistCount));
    }
    // Order-independent: rotating between the same artists should not rebuild.
    artists.sort();
    final taste = artists.join('|');

    // Once real personalization exists, the feed only depends on the listening
    // fingerprint. Avoiding the home-shelf part here keeps stats ticks cheap
    // and prevents a rebuild just because the home cache loaded.
    if (_profile.totalSongsAnalyzed >= _minSongsForProfile) {
      return taste;
    }

    final home = _homeScreenProvider.homeSections;
    final firstContents = home.isEmpty ? null : home.first.contents;
    final homeFingerprint =
        '$home.length:${firstContents is List ? firstContents.length : 0}';

    return '$taste#$homeFingerprint';
  }

  void _onPlayerChanged() {
    if (!_hasInitialized) return;

    // The Listen Again row can be updated without any network work, so keep it
    // responsive even when a full rebuild is not needed.
    _updateListenAgainFromPlayer();

    if (_isLoading) return;
    _scheduleRefreshIfSourcesChanged();
  }

  void _onSourceChanged() {
    if (!_hasInitialized || _isLoading) return;
    _scheduleRefreshIfSourcesChanged();
  }

  void _scheduleRefreshIfSourcesChanged() {
    final signature = _sourceSignature();
    final needsRefresh =
        _sections.isEmpty || signature != _sectionSourceSignature;

    _sourceChangeDebounce?.cancel();
    if (!needsRefresh) return;

    _sourceChangeDebounce = Timer(_sourceChangeDebounceDuration, () {
      if (!_hasInitialized || _isLoading) return;
      // Re-check after the debounce: a burst of notifications while a song
      // starts should not trigger more than one regeneration.
      if (_sections.isNotEmpty &&
          _sourceSignature() == _sectionSourceSignature) {
        return;
      }
      unawaited(updateRecommendations());
    });
  }

  Future<void> _loadProfile() async {
    try {
      final jsonString = _box?.get(_profileKey);
      if (jsonString != null) {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        _profile = UserPreferenceProfile.fromJson(jsonMap);
        debugPrint(
          'Loaded user preference profile: ${_profile.totalSongsAnalyzed} songs analyzed',
        );
      }
    } catch (e) {
      debugPrint('Error loading preference profile: $e');
      _profile = UserPreferenceProfile.empty();
    }
  }

  Future<void> _saveProfile() async {
    try {
      await _box?.put(_profileKey, json.encode(_profile.toJson()));
    } catch (e) {
      debugPrint('Error saving preference profile: $e');
    }
  }

  Future<void> _loadCachedSections() async {
    try {
      final rawTimestamp = _box?.get(_sectionsTimestampKey);
      final timestamp = rawTimestamp == null
          ? null
          : int.tryParse(rawTimestamp);
      if (timestamp != null) {
        final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (DateTime.now().difference(cachedTime) < _sectionsCacheDuration) {
          final jsonString = _box?.get(_sectionsKey);
          if (jsonString != null) {
            final List<dynamic> jsonList = json.decode(jsonString);
            _sections = jsonList
                .whereType<Map<String, dynamic>>()
                .map(_sectionFromJson)
                .where((s) => s.songs.isNotEmpty)
                .toList();
            _sectionSourceSignature = _box?.get(_sectionsSignatureKey) ?? '';
            debugPrint(
              'Loaded ${_sections.length} personalized sections from cache',
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading cached sections: $e');
    }
    // If cache is invalid or missing, we'll regenerate on first build
  }

  Future<void> _saveSections() async {
    try {
      final jsonList = _sections.map(_sectionToJson).toList();
      await _box?.put(_sectionsKey, json.encode(jsonList));
      await _box?.put(
        _sectionsTimestampKey,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      await _box?.put(_sectionsSignatureKey, _sectionSourceSignature);
    } catch (e) {
      debugPrint('Error saving sections: $e');
    }
  }

  PersonalizedSection _sectionFromJson(Map<String, dynamic> json) {
    final songsJson = json['songs'] as List<dynamic>? ?? [];
    final songs = songsJson
        .whereType<Map<String, dynamic>>()
        .map((s) => SongInfo.fromHistoryMap(s))
        .whereType<SongInfo>()
        .toList();

    return PersonalizedSection(
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      songs: songs,
      type: SectionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SectionType.discovery,
      ),
      seedArtist: json['seedArtist'] as String?,
    );
  }

  Map<String, dynamic> _sectionToJson(PersonalizedSection section) {
    return {
      'title': section.title,
      'subtitle': section.subtitle,
      'type': section.type.name,
      'seedArtist': section.seedArtist,
      'songs': section.songs
          .map(
            (s) => {
              'id': s.videoId,
              'title': s.name,
              'artist': s.artists.map((a) => a.name).join(', '),
              'thumbnail': s.thumbnails.isNotEmpty ? s.thumbnails.last.url : '',
              'artists': s.artists
                  .map((a) => {'name': a.name, 'id': a.id})
                  .toList(),
              'duration': s.duration.inSeconds,
              'isPodcast': s.isPodcast,
            },
          )
          .toList(),
    };
  }

  /// Keeps a persisted map from growing without bound. Dart maps preserve
  /// insertion order, so the oldest entries are dropped first.
  static Map<String, T> _capMap<T>(Map<String, T> map, int maxEntries) {
    if (map.length <= maxEntries) return map;
    return Map.fromEntries(map.entries.skip(map.length - maxEntries));
  }

  /// Call this when a song is skipped to track negative preference.
  void recordSkip(String videoId, String title, String artist) {
    final currentSkips = _profile.skipCounts[videoId] ?? 0;
    final newSkips = currentSkips + 1;

    // Update profile
    _profile = _profile.copyWith(
      skipCounts: _capMap({
        ..._profile.skipCounts,
        videoId: newSkips,
      }, _maxTrackedEvents),
    );

    // Reduce affinity for this song and artist
    final currentSongAffinity = _profile.songAffinities[videoId] ?? 0.5;
    final currentArtistAffinity = _profile.artistAffinities[artist] ?? 0.5;

    _profile = _profile.copyWith(
      songAffinities: {
        ..._profile.songAffinities,
        videoId: math.max(0.0, currentSongAffinity - 0.15),
      },
      artistAffinities: {
        ..._profile.artistAffinities,
        artist: math.max(0.0, currentArtistAffinity - 0.05),
      },
    );

    _saveProfile();

    // If this song was in recommendations, remove it
    _removeSongFromSections(videoId);
    notifyListeners();
  }

  /// Call this when a song is completed (played to end) to track positive preference.
  void recordCompletion(String videoId, String title, String artist) {
    final currentCompletions = _profile.completionCounts[videoId] ?? 0;
    final newCompletions = currentCompletions + 1;

    // Update profile
    _profile = _profile.copyWith(
      completionCounts: _capMap({
        ..._profile.completionCounts,
        videoId: newCompletions,
      }, _maxTrackedEvents),
    );

    // Increase affinity for this song and artist
    final currentSongAffinity = _profile.songAffinities[videoId] ?? 0.5;
    final currentArtistAffinity = _profile.artistAffinities[artist] ?? 0.5;

    _profile = _profile.copyWith(
      songAffinities: {
        ..._profile.songAffinities,
        videoId: math.min(1.0, currentSongAffinity + 0.1),
      },
      artistAffinities: {
        ..._profile.artistAffinities,
        artist: math.min(1.0, currentArtistAffinity + 0.03),
      },
    );

    _saveProfile();
    notifyListeners();
  }

  void _removeSongFromSections(String videoId) {
    _sections = _sections
        .map((section) {
          return PersonalizedSection(
            title: section.title,
            subtitle: section.subtitle,
            songs: section.songs.where((s) => s.videoId != videoId).toList(),
            type: section.type,
            seedArtist: section.seedArtist,
          );
        })
        .where((s) => s.songs.isNotEmpty)
        .toList();
  }

  /// Main method to update recommendations based on current listening data.
  Future<void> updateRecommendations() async {
    if (_isLoading) {
      // A pull-to-refresh can land while an automatic update is running.
      _refreshQueued = true;
      return;
    }

    // Any pending debounce is now redundant.
    _sourceChangeDebounce?.cancel();

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Analyze listening history and build/update profile
      await _analyzeAndUpdateProfile();

      // 2. Generate personalized sections
      await _generateSections();

      // 3. Fingerprint what this build was based on, then cache it. The
      // fingerprint lets source-change listeners skip rebuilding while the
      // same artists keep playing.
      _sectionSourceSignature = _sourceSignature();
      await _saveSections();
      await _saveProfile();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to update recommendations: $e';
      debugPrint(_error);
      notifyListeners();
    }

    if (_refreshQueued) {
      _refreshQueued = false;
      unawaited(updateRecommendations());
    }
  }

  /// Blends lifetime and recent (rolling 7-day) listening into an artist
  /// affinity map.
  ///
  /// Lifetime playtime alone is what used to "fingerprint" the most-played
  /// artist forever: a new artist could never outrank years of history. Recent
  /// listening gets [_recentArtistWeight] of the score, so a shift in taste
  /// surfaces quickly while long-term favourites remain in the top artists
  /// list for the secondary mix.
  @visibleForTesting
  static Map<String, double> calculateArtistAffinities({
    required Map<String, int> lifetimeSeconds,
    required Map<String, int> recentSeconds,
  }) {
    if (lifetimeSeconds.isEmpty && recentSeconds.isEmpty) {
      return const {};
    }

    final totalLifetime = lifetimeSeconds.values.fold<int>(0, (a, b) => a + b);
    final totalRecent = recentSeconds.values.fold<int>(0, (a, b) => a + b);
    final artists = <String>{...lifetimeSeconds.keys, ...recentSeconds.keys};

    final scores = <String, double>{};
    for (final artist in artists) {
      final lifetimeShare = totalLifetime > 0
          ? (lifetimeSeconds[artist] ?? 0) / totalLifetime
          : 0.0;
      final recentShare = totalRecent > 0
          ? (recentSeconds[artist] ?? 0) / totalRecent
          : 0.0;
      scores[artist] =
          (lifetimeShare * (1 - _recentArtistWeight) +
                  recentShare * _recentArtistWeight)
              .clamp(0.0, 1.0);
    }

    // Normalise so the top artist is 1.0. With no recent data (e.g. right
    // after upgrading) this preserves the previous absolute thresholds.
    final highest = scores.values.fold<double>(0, math.max);
    if (highest > 0) {
      for (final artist in scores.keys.toList()) {
        scores[artist] = scores[artist]! / highest;
      }
    }
    return scores;
  }

  Future<void> _analyzeAndUpdateProfile() async {
    // Wait for stats provider to be ready
    if (_statsProvider.isLoading) {
      // Wait a bit for stats to load
      await Future.delayed(const Duration(milliseconds: 500));
    }

    final songStats = _statsProvider.songStats;
    final artistPlaybackTime = _statsProvider.artistPlaybackTime;

    if (songStats.isEmpty) {
      // No listening history yet - keep empty profile for defaults
      return;
    }

    // Song affinities: single pass over the stats instead of repeatedly
    // scanning the whole map per artist.
    final newSongAffinities = <String, double>{};
    for (final stats in songStats.values) {
      final playCountFactor = (stats.playCount / 20).clamp(0.0, 0.5);
      final recencyFactor = _recencyFactor(stats.lastPlayedTimestamp);
      final skipPenalty = (_profile.skipCounts[stats.id] ?? 0) * 0.1;
      final completionBonus = (_profile.completionCounts[stats.id] ?? 0) * 0.05;

      final affinity =
          (playCountFactor +
                  recencyFactor * 0.3 +
                  completionBonus -
                  skipPenalty)
              .clamp(0.0, 1.0);
      newSongAffinities[stats.id] = affinity;
    }

    // Artist affinities: blend all-time playback time with the rolling 7-day
    // window. `dailyArtists` already aggregates recent listening, so no extra
    // history is kept in memory.
    final recentArtistSeconds = <String, int>{
      for (final entry in _statsProvider.dailyArtists.entries)
        entry.key: entry.value.inSeconds,
    };
    final newArtistAffinities = calculateArtistAffinities(
      lifetimeSeconds: artistPlaybackTime,
      recentSeconds: recentArtistSeconds,
    );

    // Get top artists by affinity
    final sortedArtists = newArtistAffinities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topArtistNames = sortedArtists
        .take(_maxTopArtists)
        .map((e) => e.key)
        .toList();

    // Bound the persisted maps. Affinities keep the strongest entries; the
    // event counters keep the most recently touched ones.
    final cappedSongs = newSongAffinities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Update profile
    _profile = _profile.copyWith(
      artistAffinities: Map.fromEntries(sortedArtists.take(_maxTrackedArtists)),
      songAffinities: Map.fromEntries(cappedSongs.take(_maxTrackedSongs)),
      skipCounts: _capMap(
        Map<String, int>.from(_profile.skipCounts),
        _maxTrackedEvents,
      ),
      completionCounts: _capMap(
        Map<String, int>.from(_profile.completionCounts),
        _maxTrackedEvents,
      ),
      lastUpdated: DateTime.now(),
      totalSongsAnalyzed: songStats.length,
      preferredArtistIds: topArtistNames,
    );
  }

  double _recencyFactor(int timestamp) {
    final daysSince = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestamp))
        .inDays;
    if (daysSince <= 1) return 0.5;
    if (daysSince <= 3) return 0.3;
    if (daysSince <= 7) return 0.2;
    if (daysSince <= 30) return 0.1;
    return 0.05;
  }

  Future<void> _generateSections() async {
    final newSections = <PersonalizedSection>[];

    // 1. Listen Again - recently played with high affinity
    final listenAgain = _buildListenAgainSection();
    if (listenAgain.songs.isNotEmpty) {
      newSections.add(listenAgain);
    }

    // 2. Artist mixes - the two strongest artists, which now reflect recent
    // listening instead of only the all-time favourite.
    final topArtistSections = await _buildTopArtistSections();
    newSections.addAll(topArtistSections);

    // 3. Discovery - a different flavour, sourced from the already-fetched
    // home shelves so this does not add another network request.
    final discovery = _buildDiscoverySection();
    if (discovery.songs.isNotEmpty) {
      newSections.add(discovery);
    }

    // 4. Trending For You - trending songs matching preferences
    final trendingForYou = await _buildTrendingForYouSection();
    if (trendingForYou.songs.isNotEmpty) {
      newSections.add(trendingForYou);
    }

    // 5. Genre Exploration (if we have enough data)
    if (_profile.totalSongsAnalyzed >= 30) {
      final genreExploration = _buildGenreExplorationSection();
      if (genreExploration.songs.isNotEmpty) {
        newSections.add(genreExploration);
      }
    }

    // If no personalized data yet, provide defaults
    if (newSections.isEmpty) {
      final defaults = await _buildDefaultSections();
      newSections.addAll(defaults);
    }

    // Never repeat the same track across rows. Duplicates make the feed feel
    // repetitive and keep unnecessary song objects alive.
    final deduped = <PersonalizedSection>[];
    final seen = <String>{};
    for (final section in newSections) {
      final songs = <SongInfo>[];
      for (final song in section.songs) {
        if (seen.add(song.videoId)) songs.add(song);
      }
      if (songs.isEmpty) continue;
      deduped.add(
        PersonalizedSection(
          title: section.title,
          subtitle: section.subtitle,
          songs: songs,
          type: section.type,
          seedArtist: section.seedArtist,
        ),
      );
    }

    _sections = deduped;
  }

  PersonalizedSection _buildListenAgainSection() {
    final recentSongs = _playerProvider.lastPlayedSongs.take(20).toList();
    final seen = <String>{};
    final songs = <SongInfo>[];

    for (final songMap in recentSongs) {
      final videoId =
          songMap['id']?.toString() ?? songMap['videoId']?.toString() ?? '';
      if (videoId.isEmpty || !seen.add(videoId)) continue;

      final affinity = _profile.songAffinities[videoId] ?? 0.3;
      // Only include songs with decent affinity or very recent plays
      if (affinity >= 0.2 || songs.length < 5) {
        final song = SongInfo.fromHistoryMap(songMap);
        if (song != null) {
          songs.add(song);
        }
      }
      if (songs.length >= _maxRecommendationsPerSection) break;
    }

    return PersonalizedSection(
      title: 'Listen Again',
      subtitle: 'Pick up where you left off',
      songs: songs,
      type: SectionType.listenAgain,
    );
  }

  Future<List<PersonalizedSection>> _buildTopArtistSections() async {
    final seeds = _artistSeeds();
    if (seeds.isEmpty) return const [];

    // `preferredArtistIds` is affinity-ranked (recent + lifetime), so this
    // picks two different kinds of music rather than the same artist twice.
    final artists = <String>[];
    for (final artist in _profile.preferredArtistIds) {
      if (!seeds.containsKey(artist)) continue;
      artists.add(artist);
      if (artists.length >= _maxArtistMixes) break;
    }
    if (artists.isEmpty) {
      artists.addAll(seeds.keys.take(_maxArtistMixes));
    }

    // Fetch in parallel so two mixes cost roughly the latency of one.
    final built = await Future.wait(
      artists.map((artist) async {
        final seedVideoId = seeds[artist];
        if (seedVideoId == null) return null;

        try {
          final relatedSongs = await _getRelatedForArtist(seedVideoId);

          // Filter out already over-recommended songs; the final dedupe pass
          // removes overlaps with other rows.
          final seen = <String>{};
          final filteredSongs = relatedSongs
              .where((s) => seen.add(s.videoId))
              .where(
                (s) =>
                    s.videoId != seedVideoId &&
                    (_profile.songAffinities[s.videoId] ?? 0.5) < 0.8,
              )
              .take(_maxRecommendationsPerSection)
              .toList();

          if (filteredSongs.isEmpty) return null;

          return PersonalizedSection(
            title: '$artist Mix',
            subtitle: 'Songs inspired by $artist',
            songs: filteredSongs,
            type: SectionType.artistMix,
            seedArtist: artist,
          );
        } catch (e) {
          debugPrint('Error getting related songs for $artist: $e');
          return null;
        }
      }),
    );

    return built.whereType<PersonalizedSection>().toList();
  }

  /// One seed track per artist, built in a single pass over history/stats.
  Map<String, String> _artistSeeds() {
    final seeds = <String, String>{};

    for (final songMap in _playerProvider.lastPlayedSongs) {
      final artist = (songMap['artist'] ?? '').toString();
      final id =
          songMap['id']?.toString() ?? songMap['videoId']?.toString() ?? '';
      if (artist.isEmpty || id.isEmpty) continue;
      seeds.putIfAbsent(artist, () => id);
    }

    for (final stats in _statsProvider.songStats.values) {
      if (stats.artist.isEmpty) continue;
      seeds.putIfAbsent(stats.artist, () => stats.id);
    }

    return seeds;
  }

  /// Bounded cache around related-track lookups. Returning the same list for
  /// a while avoids re-hitting the network when the top-two artists swap
  /// order after a single play.
  Future<List<SongInfo>> _getRelatedForArtist(String seedVideoId) async {
    final now = DateTime.now();
    final cached = _relatedCache[seedVideoId];
    if (cached != null && cached.isFresh(now, _relatedCacheTtl)) {
      return cached.songs;
    }

    final related = await _relatedSongService
        .getRelatedSongs(seedVideoId)
        .timeout(const Duration(seconds: 20));
    final songs = related.take(_relatedCacheSongs).toList(growable: false);

    if (_relatedCache.length >= _relatedCacheSize) {
      _relatedCache.remove(_relatedCache.keys.first);
    }
    _relatedCache[seedVideoId] = _CachedRelatedSongs(songs, now);
    return songs;
  }

  /// Converts a home-feed item into a playable [SongInfo].
  ///
  /// A shelf mixes songs, videos, albums, playlists and artists. Only
  /// [SongDetailed] and [VideoDetailed] expose a playable `videoId`; reading
  /// that getter off, say, a [PlaylistDetailed] throws `NoSuchMethodError` and
  /// used to abort the whole recommendation run. Album/playlist entries are
  /// containers rather than tracks, so they are skipped here.
  @visibleForTesting
  static SongInfo? songInfoFromHomeContent(dynamic content) {
    final String videoId;
    final String name;
    final ArtistBasic artist;
    final int? duration;
    final List<ThumbnailFull> thumbnails;

    if (content is SongDetailed) {
      videoId = content.videoId;
      name = content.name;
      artist = content.artist;
      duration = content.duration;
      thumbnails = content.thumbnails;
    } else if (content is VideoDetailed) {
      videoId = content.videoId;
      name = content.name;
      artist = content.artist;
      duration = content.duration;
      thumbnails = content.thumbnails;
    } else {
      return null;
    }

    return SongInfo(
      videoId: videoId,
      name: name,
      artists: [Artist(name: artist.name, id: artist.artistId ?? '')],
      thumbnails: thumbnails
          .map((t) => Thumbnail(url: t.url, width: t.width, height: t.height))
          .toList(),
      duration: Duration(seconds: duration ?? 0),
    );
  }

  PersonalizedSection _buildDiscoverySection() {
    // Home shelves are already fetched for the home screen. Using them here
    // means discovery is a genuinely different source from the artist mixes,
    // and it costs no extra network request.
    final knownArtists = _profile.artistAffinities.keys.toSet();
    final candidates = <SongInfo>[];
    final seen = <String>{};

    for (final section in _homeScreenProvider.carouselSections) {
      for (final content in section.contents) {
        final song = songInfoFromHomeContent(content);
        if (song == null) continue;
        if (!seen.add(song.videoId)) continue;
        if (_profile.songAffinities.containsKey(song.videoId)) continue;
        candidates.add(song);
      }
    }

    bool isNewArtist(SongInfo song) {
      final artist = song.artists.isNotEmpty ? song.artists.first.name : '';
      return artist.isNotEmpty && !knownArtists.contains(artist);
    }

    final songs = <SongInfo>[
      ...candidates.where(isNewArtist),
      ...candidates.where((song) => !isNewArtist(song)),
    ].take(_maxRecommendationsPerSection).toList();

    return PersonalizedSection(
      title: 'discover_new'.tr(),
      subtitle: 'artists_and_songs_you_might_like'.tr(),
      songs: songs,
      type: SectionType.discovery,
    );
  }

  /// Trending tracks for the default country, fetched on demand.
  ///
  /// The Home tab is usually opened before the Trending tab, so its lists are
  /// empty on a fresh install. Without this fetch the default recommendations
  /// had nothing to fall back to and the section stayed blank.
  Future<List<SongInfo>> _loadTrendingIfNeeded() async {
    final countries = _trendingProvider.countries;
    if (countries.isEmpty) return const [];

    final playlist = countries.firstWhere(
      (c) => c.name.toLowerCase().contains('kenya'),
      orElse: () => countries.first,
    );

    var songs = _trendingProvider.getTrendingSongs(playlist.playlistId);
    if (songs.isEmpty && !_trendingProvider.isLoading(playlist.playlistId)) {
      await _trendingProvider.loadTrendingSongs(playlist.playlistId);
      songs = _trendingProvider.getTrendingSongs(playlist.playlistId);
    }
    return songs;
  }

  Future<PersonalizedSection> _buildTrendingForYouSection() async {
    final songs = <SongInfo>[];
    final seen = <String>{};

    // Get trending songs from Kenya (default)
    final trendingSongs = await _loadTrendingIfNeeded();

    // Filter trending songs by artist affinity
    for (final song in trendingSongs) {
      final artistName = song.artists.isNotEmpty ? song.artists.first.name : '';
      final affinity = _profile.artistAffinities[artistName] ?? 0.0;

      if (seen.add(song.videoId) &&
          (affinity > 0.1 ||
              songs.length < 5) && // Include if affinity match or need filler
          songs.length < _maxRecommendationsPerSection) {
        songs.add(song);
      }
    }

    return PersonalizedSection(
      title: 'trending_for_you'.tr(),
      subtitle: 'popular_songs_matching_your_taste'.tr(),
      songs: songs,
      type: SectionType.trendingForYou,
    );
  }

  PersonalizedSection _buildGenreExplorationSection() {
    // Deeper home shelves: discovery already consumed the first shelves, so
    // this row adds genuinely new tracks (deduped again later).
    final songs = <SongInfo>[];
    final seen = <String>{};

    for (final section in _homeScreenProvider.carouselSections.skip(2)) {
      for (final content in section.contents) {
        final song = songInfoFromHomeContent(content);
        if (song == null) continue;
        if (seen.add(song.videoId) &&
            _profile.songAffinities[song.videoId] == null &&
            songs.length < _maxRecommendationsPerSection) {
          songs.add(song);
        }
      }
    }

    return PersonalizedSection(
      title: 'explore_more'.tr(),
      subtitle: 'more_music_you_might_enjoy'.tr(),
      songs: songs,
      type: SectionType.genreExploration,
    );
  }

  Future<List<PersonalizedSection>> _buildDefaultSections() async {
    final sections = <PersonalizedSection>[];

    // Default: Listen Again from YouTube Music home
    final listenAgainSongs = _homeScreenProvider.listenAgainSongs;
    if (listenAgainSongs.isNotEmpty) {
      sections.add(
        PersonalizedSection(
          title: 'listen_again'.tr(),
          subtitle: 'your_recent_plays'.tr(),
          songs: listenAgainSongs.take(_maxRecommendationsPerSection).toList(),
          type: SectionType.listenAgain,
        ),
      );
    }

    // Default: Trending in Kenya
    final trendingSongs = await _loadTrendingIfNeeded();
    if (trendingSongs.isNotEmpty) {
      sections.add(
        PersonalizedSection(
          title: 'trending_in_kenya'.tr(),
          subtitle: 'popular_right_now'.tr(),
          songs: trendingSongs.take(_maxRecommendationsPerSection).toList(),
          type: SectionType.trendingForYou,
        ),
      );
    }

    // Default: YouTube Music home sections (first few)
    for (final section in _homeScreenProvider.carouselSections.take(3)) {
      final songs = section.contents
          .map(songInfoFromHomeContent)
          .whereType<SongInfo>()
          .take(_maxRecommendationsPerSection)
          .toList();

      if (songs.isNotEmpty) {
        sections.add(
          PersonalizedSection(
            title: section.title,
            subtitle: 'recommended_for_you'.tr(),
            songs: songs,
            type: SectionType.discovery,
          ),
        );
      }
    }

    return sections;
  }

  /// Force refresh recommendations (pull-to-refresh)
  Future<void> refresh() async {
    await updateRecommendations();
  }

  void _updateListenAgainFromPlayer() {
    if (!_hasInitialized || _isLoading) return;

    final newSection = _buildListenAgainSection();
    if (newSection.songs.isEmpty) return;

    final index = _sections.indexWhere(
      (section) => section.type == SectionType.listenAgain,
    );

    // Player notifications also fire for play/pause and queue changes. Only
    // rebuild the widget tree when the actual track list changed.
    if (index >= 0 && _sameSongs(_sections[index].songs, newSection.songs)) {
      return;
    }

    if (index >= 0) {
      _sections[index] = newSection;
    } else {
      _sections = [newSection, ..._sections];
    }
    notifyListeners();
  }

  static bool _sameSongs(List<SongInfo> a, List<SongInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].videoId != b[i].videoId) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _sourceChangeDebounce?.cancel();
    if (_sourceListenersAttached) {
      _homeScreenProvider.removeListener(_onSourceChanged);
      _trendingProvider.removeListener(_onSourceChanged);
      _playerProvider.removeListener(_onPlayerChanged);
      _statsProvider.removeListener(_onSourceChanged);
    }
    _relatedCache.clear();
    _box?.close();
    super.dispose();
  }
}

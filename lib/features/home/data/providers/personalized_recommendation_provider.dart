// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
      artistAffinities: Map<String, double>.from(json['artistAffinities'] ?? {}),
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
  listenAgain,        // Recently played, high affinity
  topArtists,         // Songs from top artists
  artistMix,          // Mix of songs from a specific top artist
  discovery,          // New artists/genres related to preferences
  genreExploration,   // Genre-based exploration
  trendingForYou,     // Trending songs matching preferences
}

class PersonalizedRecommendationProvider with ChangeNotifier {
  static const String _hiveBoxName = 'personalized_recommendations';
  static const String _profileKey = 'user_preference_profile';
  static const String _sectionsKey = 'personalized_sections';
  static const String _sectionsTimestampKey = 'personalized_sections_timestamp';
  static const Duration _sectionsCacheDuration = Duration(hours: 6);
  static const int _maxRecommendationsPerSection = 15;
  static const int _maxTopArtists = 10;
  static const int _minSongsForProfile = 5; // Minimum songs before personalization kicks in

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
  Timer? _periodicUpdateTimer;
  static const Duration _updateInterval = Duration(minutes: 30);

  PersonalizedRecommendationProvider({
    required StatsProvider statsProvider,
    required PlayerProvider playerProvider,
    required RelatedSongService relatedSongService,
    required HomeScreenProvider homeScreenProvider,
    required TrendingProvider trendingProvider,
  })  : _statsProvider = statsProvider,
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
    _startPeriodicUpdate();
    _hasInitialized = true;
    notifyListeners();

    // First run (or an expired cache): build the initial sections, otherwise
    // the home page would stay empty until the periodic timer fired.
    if (_sections.isEmpty) {
      unawaited(updateRecommendations());
    }
  }

  Future<void> _loadProfile() async {
    try {
      final jsonString = _box?.get(_profileKey);
      if (jsonString != null) {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        _profile = UserPreferenceProfile.fromJson(jsonMap);
        debugPrint('Loaded user preference profile: ${_profile.totalSongsAnalyzed} songs analyzed');
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
            debugPrint('Loaded ${_sections.length} personalized sections from cache');
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
      await _box?.put(_sectionsTimestampKey, DateTime.now().millisecondsSinceEpoch.toString());
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
          .map((s) => {
                'id': s.videoId,
                'title': s.name,
                'artist': s.artists.map((a) => a.name).join(', '),
                'thumbnail': s.thumbnails.isNotEmpty ? s.thumbnails.last.url : '',
                'artists': s.artists.map((a) => {'name': a.name, 'id': a.id}).toList(),
                'duration': s.duration.inSeconds,
                'isPodcast': s.isPodcast,
              })
          .toList(),
    };
  }

  void _startPeriodicUpdate() {
    _periodicUpdateTimer?.cancel();
    _periodicUpdateTimer = Timer.periodic(_updateInterval, (_) {
      if (!_isLoading) {
        updateRecommendations();
      }
    });
  }

  /// Call this when a song is skipped to track negative preference.
  void recordSkip(String videoId, String title, String artist) {
    final currentSkips = _profile.skipCounts[videoId] ?? 0;
    final newSkips = currentSkips + 1;

    // Update profile
    _profile = _profile.copyWith(
      skipCounts: {..._profile.skipCounts, videoId: newSkips},
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
      completionCounts: {..._profile.completionCounts, videoId: newCompletions},
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
    _sections = _sections.map((section) {
      return PersonalizedSection(
        title: section.title,
        subtitle: section.subtitle,
        songs: section.songs.where((s) => s.videoId != videoId).toList(),
        type: section.type,
        seedArtist: section.seedArtist,
      );
    }).where((s) => s.songs.isNotEmpty).toList();
  }

  /// Main method to update recommendations based on current listening data.
  Future<void> updateRecommendations() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Analyze listening history and build/update profile
      await _analyzeAndUpdateProfile();

      // 2. Generate personalized sections
      await _generateSections();

      // 3. Save to cache
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

    final newArtistAffinities = <String, double>{};
    final newSongAffinities = <String, double>{};
    final newSkipCounts = Map<String, int>.from(_profile.skipCounts);
    final newCompletionCounts = Map<String, int>.from(_profile.completionCounts);

    // Calculate artist affinities based on playback time
    int totalPlaybackSeconds = artistPlaybackTime.values.fold(0, (a, b) => a + b);
    if (totalPlaybackSeconds > 0) {
      for (final entry in artistPlaybackTime.entries) {
        final affinity = (entry.value / totalPlaybackSeconds).clamp(0.0, 1.0);
        // Boost by play count factor
        final stats = songStats.values.where((s) => s.artist == entry.key).toList();
        final playCount = stats.fold(0, (a, b) => a + b.playCount);
        final boostedAffinity = (affinity * 0.7 + (playCount / 100).clamp(0.0, 0.3)).clamp(0.0, 1.0);
        newArtistAffinities[entry.key] = boostedAffinity;
      }
    }

    // Calculate song affinities based on play count and completion rate
    for (final stats in songStats.values) {
      final playCountFactor = (stats.playCount / 20).clamp(0.0, 0.5);
      final recencyFactor = _recencyFactor(stats.lastPlayedTimestamp);
      final skipPenalty = (newSkipCounts[stats.id] ?? 0) * 0.1;
      final completionBonus = (newCompletionCounts[stats.id] ?? 0) * 0.05;

      final affinity = (playCountFactor + recencyFactor * 0.3 + completionBonus - skipPenalty).clamp(0.0, 1.0);
      newSongAffinities[stats.id] = affinity;
    }

    // Get top artists by affinity
    final sortedArtists = newArtistAffinities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topArtistNames = sortedArtists.take(_maxTopArtists).map((e) => e.key).toList();

    // Update profile
    _profile = _profile.copyWith(
      artistAffinities: newArtistAffinities,
      songAffinities: newSongAffinities,
      skipCounts: newSkipCounts,
      completionCounts: newCompletionCounts,
      lastUpdated: DateTime.now(),
      totalSongsAnalyzed: songStats.length,
      preferredArtistIds: topArtistNames,
    );
  }

  double _recencyFactor(int timestamp) {
    final daysSince = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    ).inDays;
    if (daysSince <= 1) return 0.5;
    if (daysSince <= 3) return 0.3;
    if (daysSince <= 7) return 0.2;
    if (daysSince <= 30) return 0.1;
    return 0.05;
  }

  Future<void> _generateSections() async {
    final newSections = <PersonalizedSection>[];

    // 1. Listen Again - recently played with high affinity
    final listenAgain = await _buildListenAgainSection();
    if (listenAgain.songs.isNotEmpty) {
      newSections.add(listenAgain);
    }

    // 2. Top Artists Mix - personalized mixes for top 3-5 artists
    final topArtistSections = await _buildTopArtistSections();
    newSections.addAll(topArtistSections);

    // 3. Discovery - new artists related to preferences
    final discovery = await _buildDiscoverySection();
    if (discovery.songs.isNotEmpty) {
      newSections.add(discovery);
    }

    // 4. Trending For You - trending songs matching preferences
    final trendingForYou = await _buildTrendingForYouSection();
    if (trendingForYou.songs.isNotEmpty) {
      newSections.add(trendingForYou);
    }

    // 5. Genre Exploration (if we have enough data)
    if (_profile.totalSongsAnalyzed >= 20) {
      final genreExploration = await _buildGenreExplorationSection();
      if (genreExploration.songs.isNotEmpty) {
        newSections.add(genreExploration);
      }
    }

    // If no personalized data yet, provide defaults
    if (newSections.isEmpty) {
      final defaults = await _buildDefaultSections();
      newSections.addAll(defaults);
    }

    _sections = newSections;
  }

  Future<PersonalizedSection> _buildListenAgainSection() async {
    final recentSongs = _playerProvider.lastPlayedSongs.take(20).toList();
    final seen = <String>{};
    final songs = <SongInfo>[];

    for (final songMap in recentSongs) {
      final videoId = songMap['id']?.toString() ?? songMap['videoId']?.toString() ?? '';
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
    final sections = <PersonalizedSection>[];
    final topArtists = _profile.preferredArtistIds.take(5).toList();

    for (int i = 0; i < topArtists.length && i < 3; i++) {
      final artist = topArtists[i];

      // Find a seed song from this artist in history
      String? seedVideoId;
      for (final songMap in _playerProvider.lastPlayedSongs) {
        final songArtist = songMap['artist']?.toString() ?? '';
        if (songArtist == artist) {
          seedVideoId = songMap['id']?.toString() ?? songMap['videoId']?.toString();
          break;
        }
      }

      // Also check stats
      if (seedVideoId == null) {
        for (final stats in _statsProvider.songStats.values) {
          if (stats.artist == artist) {
            seedVideoId = stats.id;
            break;
          }
        }
      }

      if (seedVideoId != null) {
        try {
          final relatedSongs = await _relatedSongService.getRelatedSongs(seedVideoId);
          // Filter out already known songs and apply affinity
          final seen = <String>{};
          final filteredSongs = relatedSongs
              .where((s) => seen.add(s.videoId))
              .where((s) => (_profile.songAffinities[s.videoId] ?? 0.5) < 0.8) // Avoid over-recommending
              .take(_maxRecommendationsPerSection)
              .toList();

          if (filteredSongs.isNotEmpty) {
            sections.add(PersonalizedSection(
              title: '$artist Mix',
              subtitle: 'Songs inspired by $artist',
              songs: filteredSongs,
              type: SectionType.artistMix,
              seedArtist: artist,
            ));
          }
        } catch (e) {
          debugPrint('Error getting related songs for $artist: $e');
        }
      }
    }

    return sections;
  }

  Future<PersonalizedSection> _buildDiscoverySection() async {
    final songs = <SongInfo>[];
    final seen = <String>{};

    // Strategy 1: Related songs to top artists (but not the same artist mixes)
    final topArtists = _profile.preferredArtistIds.take(3).toList();
    for (final artist in topArtists) {
      // Find a seed song
      String? seedVideoId;
      for (final stats in _statsProvider.songStats.values) {
        if (stats.artist == artist) {
          seedVideoId = stats.id;
          break;
        }
      }

      if (seedVideoId != null) {
        try {
          final related = await _relatedSongService.getRelatedSongs(seedVideoId);
          for (final song in related) {
            if (seen.add(song.videoId) &&
                _profile.songAffinities[song.videoId] == null && // Not in history
                songs.length < _maxRecommendationsPerSection) {
              songs.add(song);
            }
          }
        } catch (e) {
          debugPrint('Discovery error for $artist: $e');
        }
      }
    }

    // Strategy 2: YouTube Music home sections (from HomeScreenProvider)
    if (songs.length < _maxRecommendationsPerSection) {
      for (final section in _homeScreenProvider.carouselSections) {
        for (final content in section.contents) {
          if (content.videoId != null) {
            final videoId = content.videoId.toString();
            if (seen.add(videoId) &&
                _profile.songAffinities[videoId] == null &&
                songs.length < _maxRecommendationsPerSection) {
              songs.add(SongInfo(
                videoId: videoId,
                name: content.name?.toString() ?? '',
                artists: [Artist(name: content.artist?.name?.toString() ?? '', id: '')],
                thumbnails: content.thumbnails != null
                    ? content.thumbnails.map((t) => Thumbnail(url: t.url, width: t.width ?? 480, height: t.height ?? 480)).toList()
                    : [],
                duration: Duration(seconds: content.duration ?? 0),
              ));
            }
          }
        }
      }
    }

    return PersonalizedSection(
      title: 'discover_new'.tr(),
      subtitle: 'artists_and_songs_you_might_like'.tr(),
      songs: songs.take(_maxRecommendationsPerSection).toList(),
      type: SectionType.discovery,
    );
  }

  Future<PersonalizedSection> _buildTrendingForYouSection() async {
    final songs = <SongInfo>[];
    final seen = <String>{};

    // Get trending songs from Kenya (default)
    final kenyaPlaylist = _trendingProvider.countries.firstWhere(
      (c) => c.name.toLowerCase().contains('kenya'),
      orElse: () => _trendingProvider.countries.first,
    );
    final trendingSongs = _trendingProvider.getTrendingSongs(kenyaPlaylist.playlistId);

    // Filter trending songs by artist affinity
    for (final song in trendingSongs) {
      final artistName = song.artists.isNotEmpty ? song.artists.first.name : '';
      final affinity = _profile.artistAffinities[artistName] ?? 0.0;

      if (seen.add(song.videoId) &&
          (affinity > 0.1 || songs.length < 5) && // Include if affinity match or need filler
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

  Future<PersonalizedSection> _buildGenreExplorationSection() async {
    // Infer genres from top artists and find related content
    // For now, use a broader discovery from home sections
    final songs = <SongInfo>[];
    final seen = <String>{};

    // Get songs from home sections that we haven't seen
    for (final section in _homeScreenProvider.carouselSections) {
      for (final content in section.contents) {
        if (content.videoId != null) {
          final videoId = content.videoId.toString();
          if (seen.add(videoId) &&
              _profile.songAffinities[videoId] == null &&
              songs.length < _maxRecommendationsPerSection) {
            songs.add(SongInfo(
              videoId: videoId,
              name: content.name?.toString() ?? '',
              artists: [Artist(name: content.artist?.name?.toString() ?? '', id: '')],
              thumbnails: content.thumbnails != null
                  ? content.thumbnails.map((t) => Thumbnail(url: t.url, width: t.width ?? 480, height: t.height ?? 480)).toList()
                  : [],
              duration: Duration(seconds: content.duration ?? 0),
            ));
          }
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
      sections.add(PersonalizedSection(
        title: 'listen_again'.tr(),
        subtitle: 'your_recent_plays'.tr(),
        songs: listenAgainSongs.take(_maxRecommendationsPerSection).toList(),
        type: SectionType.listenAgain,
      ));
    }

    // Default: Trending in Kenya
    final kenyaPlaylist = _trendingProvider.countries.firstWhere(
      (c) => c.name.toLowerCase().contains('kenya'),
      orElse: () => _trendingProvider.countries.first,
    );
    final trendingSongs = _trendingProvider.getTrendingSongs(kenyaPlaylist.playlistId);
    if (trendingSongs.isNotEmpty) {
      sections.add(PersonalizedSection(
        title: 'trending_in_kenya'.tr(),
        subtitle: 'popular_right_now'.tr(),
        songs: trendingSongs.take(_maxRecommendationsPerSection).toList(),
        type: SectionType.trendingForYou,
      ));
    }

    // Default: YouTube Music home sections (first few)
    for (final section in _homeScreenProvider.carouselSections.take(3)) {
      final songs = section.contents
          .whereType<dynamic>()
          .where((c) => c.videoId != null)
          .map((c) => SongInfo(
                videoId: c.videoId.toString(),
                name: c.name?.toString() ?? '',
                artists: [Artist(name: c.artist?.name?.toString() ?? '', id: '')],
                thumbnails: c.thumbnails != null
                    ? c.thumbnails.map((t) => Thumbnail(url: t.url, width: t.width ?? 480, height: t.height ?? 480)).toList()
                    : [],
                duration: Duration(seconds: c.duration ?? 0),
              ))
          .take(_maxRecommendationsPerSection)
          .toList();

      if (songs.isNotEmpty) {
        sections.add(PersonalizedSection(
          title: section.title,
          subtitle: 'recommended_for_you'.tr(),
          songs: songs,
          type: SectionType.discovery,
        ));
      }
    }

    return sections;
  }

  /// Force refresh recommendations (pull-to-refresh)
  Future<void> refresh() async {
    await _generateSections();
    await _saveSections();
    notifyListeners();
  }

  @override
  void dispose() {
    _periodicUpdateTimer?.cancel();
    _box?.close();
    super.dispose();
  }
}
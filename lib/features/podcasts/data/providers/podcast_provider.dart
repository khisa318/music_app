import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/providers/player_provider.dart';
import '../models/podcast_models.dart';
import '../services/podcast_api_service.dart';

class PodcastListeningItem {
  const PodcastListeningItem({required this.episode, required this.progress});

  final PodcastEpisode episode;
  final PodcastProgress progress;
}

class PodcastProvider extends ChangeNotifier {
  PodcastProvider({PodcastApiService? api})
    : _api = api ?? PodcastApiService() {
    _loadLibrary();
  }

  static const String libraryBoxName = 'podcast_library';
  static const int _maxHistory = 60;
  static const int _maxRecentSearches = 8;

  final PodcastApiService _api;

  PlayerProvider? _playerProvider;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  bool _isHomeLoading = false;
  bool _homeHasError = false;
  bool _isRefreshing = false;

  List<PodcastShow> _featured = const [];
  List<PodcastShow> _trending = const [];
  List<PodcastShow> _recommended = const [];

  final Map<String, List<PodcastShow>> _categoryShows = {};
  final Set<String> _loadingCategories = {};
  final Map<String, String> _categoryErrors = {};

  final Map<String, List<PodcastEpisode>> _episodesByShow = {};
  final Set<String> _loadingEpisodes = {};
  final Map<String, String> _episodeErrors = {};

  final Map<String, PodcastShow> _showsById = {};
  final Map<String, PodcastEpisode> _episodeCache = {};

  bool _isSearching = false;
  String _searchQuery = '';
  List<PodcastShow> _searchResults = const [];
  String? _searchError;
  List<String> _recentSearches = [];
  int _searchGeneration = 0;

  final Map<String, PodcastShow> _subscriptions = {};
  final Map<String, PodcastEpisode> _favorites = {};
  final List<PodcastEpisode> _history = [];
  final Map<String, PodcastProgress> _progress = {};

  String? _activeEpisodeId;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  DateTime _lastProgressWrite = DateTime.fromMillisecondsSinceEpoch(0);

  Box<String>? get _libraryBox =>
      Hive.isBoxOpen(libraryBoxName) ? Hive.box<String>(libraryBoxName) : null;

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  bool get isHomeLoading => _isHomeLoading;
  bool get homeHasError => _homeHasError;
  bool get isRefreshing => _isRefreshing;

  List<PodcastShow> get featuredShows => _featured;
  List<PodcastShow> get trendingShows => _trending;
  List<PodcastShow> get recommendedShows => _recommended;

  List<PodcastShow> get recentlyUpdatedShows {
    final merged = <String, PodcastShow>{};
    for (final show in [..._featured, ..._trending, ..._recommended]) {
      merged.putIfAbsent(show.id, () => show);
    }
    final shows = merged.values.toList()
      ..sort((a, b) {
        final aDate = a.latestEpisodeAt;
        final bDate = b.latestEpisodeAt;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
    return shows.take(15).toList();
  }

  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  List<PodcastShow> get searchResults => _searchResults;
  String? get searchError => _searchError;
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  bool get hasSubscriptions => _subscriptions.isNotEmpty;
  List<PodcastShow> get subscriptions =>
      _subscriptions.values.toList(growable: false);

  bool get hasFavorites => _favorites.isNotEmpty;
  List<PodcastEpisode> get favoriteEpisodes =>
      _favorites.values.toList(growable: false);

  List<PodcastEpisode> get history => List.unmodifiable(_history);

  List<PodcastListeningItem> get continueListening {
    final items = <PodcastListeningItem>[];
    for (final episode in _history) {
      final progress = _progress[episode.id];
      if (progress == null || !progress.isInProgress) continue;
      items.add(PodcastListeningItem(episode: episode, progress: progress));
    }
    items.sort((a, b) => b.progress.updatedAt.compareTo(a.progress.updatedAt));
    return items.take(12).toList();
  }

  bool isSubscribed(String showId) => _subscriptions.containsKey(showId);
  bool isFavorite(String episodeId) => _favorites.containsKey(episodeId);

  PodcastProgress? progressFor(String episodeId) {
    if (episodeId == _activeEpisodeId) {
      final episode = _episodeCache[episodeId];
      final duration = _currentDuration > Duration.zero
          ? _currentDuration
          : episode?.duration ?? Duration.zero;
      if (duration > Duration.zero) {
        return PodcastProgress(
          episodeId: episodeId,
          position: _currentPosition,
          duration: duration,
          updatedAt: DateTime.now(),
        );
      }
    }
    return _progress[episodeId];
  }

  List<PodcastEpisode> episodesFor(String showId) =>
      _episodesByShow[showId] ?? const [];

  bool isCategoryLoading(PodcastCategory category) =>
      _loadingCategories.contains(category.id);

  String? categoryError(PodcastCategory category) =>
      _categoryErrors[category.id];

  List<PodcastShow> showsForCategory(PodcastCategory category) =>
      _categoryShows[category.id] ?? const [];

  bool isLoadingEpisodes(String showId) => _loadingEpisodes.contains(showId);

  String? episodeError(String showId) => _episodeErrors[showId];

  PodcastShow? showById(String showId) =>
      _showsById[showId] ?? _subscriptions[showId];

  PodcastEpisode? episodeById(String episodeId) => _episodeCache[episodeId];

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_featured.isNotEmpty || _isHomeLoading) return;
    await refreshHome();
  }

  Future<void> refreshHome() async {
    if (_isHomeLoading) return;
    _isHomeLoading = true;
    _isRefreshing = _featured.isNotEmpty;
    notifyListeners();

    final results = await Future.wait([
      _safeShows(_api.loadFeatured),
      _safeShows(_api.loadTrending),
      _safeShows(_api.loadRecommended),
    ]);

    if (results[0].isNotEmpty) _featured = results[0];
    if (results[1].isNotEmpty) _trending = results[1];
    if (results[2].isNotEmpty) _recommended = results[2];

    _cacheShows([...results[0], ...results[1], ...results[2]]);

    _homeHasError =
        _featured.isEmpty && _trending.isEmpty && _recommended.isEmpty;

    _isHomeLoading = false;
    _isRefreshing = false;
    notifyListeners();
  }

  Future<List<PodcastShow>> _safeShows(
    Future<List<PodcastShow>> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (error) {
      debugPrint('Podcast discovery failed: $error');
      return const [];
    }
  }

  Future<void> loadCategory(PodcastCategory category, {bool force = false}) async {
    if (_loadingCategories.contains(category.id)) return;
    if (!force && (_categoryShows[category.id]?.isNotEmpty ?? false)) return;

    _loadingCategories.add(category.id);
    _categoryErrors.remove(category.id);
    notifyListeners();

    try {
      final shows = await _api.loadCategory(category);
      _categoryShows[category.id] = shows;
      _cacheShows(shows);
    } catch (error) {
      debugPrint('Podcast category ${category.id} failed: $error');
      _categoryErrors[category.id] = error.toString();
    } finally {
      _loadingCategories.remove(category.id);
      notifyListeners();
    }
  }

  Future<void> loadShowEpisodes(
    PodcastShow show, {
    bool force = false,
  }) async {
    _cacheShows([show]);
    if (_loadingEpisodes.contains(show.id)) return;
    if (!force && (_episodesByShow[show.id]?.isNotEmpty ?? false)) return;

    _loadingEpisodes.add(show.id);
    _episodeErrors.remove(show.id);
    notifyListeners();

    try {
      final episodes = await _api.loadEpisodes(show);
      _episodesByShow[show.id] = episodes;
      _cacheEpisodes(episodes);
      if (episodes.isNotEmpty && show.latestEpisodeAt == null) {
        _showsById[show.id] = show.copyWith(
          latestEpisodeAt: episodes.first.publishedAt,
        );
      }
    } catch (error) {
      debugPrint('Podcast episodes failed for ${show.title}: $error');
      _episodeErrors[show.id] = error.toString();
    } finally {
      _loadingEpisodes.remove(show.id);
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    final term = query.trim();
    _searchQuery = term;

    if (term.isEmpty) {
      _searchGeneration++;
      _isSearching = false;
      _searchResults = const [];
      _searchError = null;
      notifyListeners();
      return;
    }

    final generation = ++_searchGeneration;
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    if (term.length >= 2) {
      _rememberSearch(term);
    }

    try {
      final results = await _api.searchShows(term);
      if (generation != _searchGeneration) return;
      _searchResults = results;
      _cacheShows(results);
      _searchError = results.isEmpty ? 'empty' : null;
    } catch (error) {
      if (generation != _searchGeneration) return;
      debugPrint('Podcast search failed: $error');
      _searchResults = const [];
      _searchError = error.toString();
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchGeneration++;
    _searchQuery = '';
    _searchResults = const [];
    _searchError = null;
    _isSearching = false;
    notifyListeners();
  }

  void removeRecentSearch(String term) {
    _recentSearches.remove(term);
    _persistLibrary();
    notifyListeners();
  }

  void clearRecentSearches() {
    _recentSearches = [];
    _persistLibrary();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Library
  // ---------------------------------------------------------------------------

  void toggleSubscription(PodcastShow show) {
    if (_subscriptions.containsKey(show.id)) {
      _subscriptions.remove(show.id);
    } else {
      _subscriptions[show.id] = show;
      _showsById[show.id] = show;
    }
    _persistLibrary();
    notifyListeners();
  }

  void toggleFavorite(PodcastEpisode episode) {
    if (_favorites.containsKey(episode.id)) {
      _favorites.remove(episode.id);
    } else {
      _favorites[episode.id] = episode;
      _episodeCache[episode.id] = episode;
    }
    _persistLibrary();
    notifyListeners();
  }

  void removeHistory(String episodeId) {
    _history.removeWhere((episode) => episode.id == episodeId);
    _progress.remove(episodeId);
    _persistLibrary();
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _progress.clear();
    _persistLibrary();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  void attachPlayer(PlayerProvider player) {
    if (identical(_playerProvider, player)) return;

    _playerProvider?.removeListener(_onPlayerChanged);
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();

    _playerProvider = player;
    player.addListener(_onPlayerChanged);
    _positionSub = player.playerService.positionStream.listen(_onPosition);
    _durationSub = player.playerService.durationStream.listen(_onDuration);
    _playingSub = player.playerService.playingStream.listen(_onPlayingChanged);
    _onPlayerChanged();
  }

  bool get isPodcastPlaying =>
      _playerProvider?.currentSong?.isPodcast == true;

  bool get isPlaying => _playerProvider?.playerService.isPlaying ?? false;

  PodcastEpisode? get currentEpisode {
    final song = _playerProvider?.currentSong;
    if (song == null || !song.isPodcast) return null;
    return _episodeCache[song.videoId];
  }

  Duration get currentPosition => _currentPosition;
  Duration get currentDuration => _currentDuration;
  double get playbackSpeed =>
      _playerProvider?.playerService.getPlaybackSpeed() ?? 1.0;

  Future<void> playEpisode(
    PodcastEpisode episode, {
    List<PodcastEpisode>? queue,
  }) async {
    final player = _playerProvider;
    if (player == null) return;

    final showEpisodes = queue ?? _episodesByShow[episode.showId] ?? const [];
    final episodes = showEpisodes.isEmpty
        ? [episode]
        : (showEpisodes.any((e) => e.id == episode.id)
              ? List<PodcastEpisode>.from(showEpisodes)
              : [episode, ...showEpisodes]);

    _cacheEpisodes(episodes);
    _cacheEpisodes([episode]);

    final songs = episodes.map((e) => e.toSongInfo()).toList();
    var startIndex = episodes.indexWhere((e) => e.id == episode.id);
    if (startIndex < 0) startIndex = 0;

    final show = _showsById[episode.showId] ?? _subscriptions[episode.showId];
    final playlistName = show?.title ?? episode.showTitle;

    player.queueProvider.setQueue(
      songs,
      currentIndex: startIndex,
      playlistId: 'podcasts_${episode.showId}',
      playlistName: playlistName,
    );

    final saved = _progress[episode.id];
    final resumeAt = saved != null && saved.isInProgress ? saved.position : null;

    final started = await player.playerService.playSong(episode.toSongInfo());
    if (!started) return;

    if (resumeAt != null) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await player.playerService.seek(resumeAt);
    }
  }

  Future<void> playShow(PodcastShow show) async {
    await loadShowEpisodes(show);
    final episodes = _episodesByShow[show.id] ?? const [];
    if (episodes.isEmpty) return;
    await playEpisode(episodes.first, queue: episodes);
  }

  Future<void> togglePlayPause() async {
    final player = _playerProvider;
    if (player == null || !isPodcastPlaying) return;
    if (player.playerService.isPlaying) {
      await player.playerService.pause();
      _flushProgress();
    } else {
      await player.playerService.play();
    }
  }

  Future<void> seek(Duration position) async {
    final player = _playerProvider;
    if (player == null) return;
    await player.playerService.seek(position);
  }

  Future<void> seekBy(Duration delta) async {
    final target = _currentPosition + delta;
    final max = _currentDuration;
    var clamped = target < Duration.zero ? Duration.zero : target;
    if (max > Duration.zero && clamped > max) clamped = max;
    await seek(clamped);
  }

  Future<void> skipForward() => seekBy(const Duration(seconds: 15));

  Future<void> skipBackward() => seekBy(const Duration(seconds: -15));

  Future<void> playNext() async {
    await _playerProvider?.playerService.playNext();
  }

  Future<void> playPrevious() async {
    await _playerProvider?.playerService.playPrevious();
  }

  Future<void> setSpeed(double speed) async {
    await _playerProvider?.playerService.setPlaybackSpeed(speed);
    notifyListeners();
  }

  Future<void> cycleSpeed() async {
    const speeds = [1.0, 1.25, 1.5, 1.75, 2.0, 0.75];
    final current = playbackSpeed;
    final index = speeds.indexWhere((s) => (s - current).abs() < 0.01);
    final next = speeds[(index + 1) % speeds.length];
    await setSpeed(next);
  }

  // ---------------------------------------------------------------------------
  // Player tracking
  // ---------------------------------------------------------------------------

  void _onPlayerChanged() {
    final song = _playerProvider?.currentSong;

    if (song != null && song.isPodcast) {
      if (song.videoId != _activeEpisodeId) {
        _flushProgress();
        _activeEpisodeId = song.videoId;
        _currentPosition = Duration.zero;
        _currentDuration = song.duration;
        final episode = _episodeCache[song.videoId];
        if (episode != null) _addHistory(episode);
        notifyListeners();
      }
      return;
    }

    if (_activeEpisodeId != null) {
      _flushProgress();
      _activeEpisodeId = null;
      _currentPosition = Duration.zero;
      _currentDuration = Duration.zero;
      notifyListeners();
    }
  }

  void _onPosition(Duration position) {
    if (_activeEpisodeId == null) return;
    _currentPosition = position;

    final now = DateTime.now();
    if (now.difference(_lastProgressWrite).inSeconds >= 5) {
      _lastProgressWrite = now;
      _persistActiveProgress();
      notifyListeners();
    }
  }

  void _onDuration(Duration? duration) {
    if (duration != null && duration > Duration.zero) {
      _currentDuration = duration;
    }
  }

  void _onPlayingChanged(bool playing) {
    if (!playing && _activeEpisodeId != null) {
      _flushProgress();
    }
  }

  void _addHistory(PodcastEpisode episode) {
    _history.removeWhere((e) => e.id == episode.id);
    _history.insert(0, episode);
    if (_history.length > _maxHistory) {
      final removed = _history.sublist(_maxHistory);
      _history.removeRange(_maxHistory, _history.length);
      for (final episode in removed) {
        if (!_favorites.containsKey(episode.id)) {
          _progress.remove(episode.id);
        }
      }
    }
    _persistLibrary();
  }

  void _persistActiveProgress() {
    final episodeId = _activeEpisodeId;
    if (episodeId == null) return;
    final episode = _episodeCache[episodeId];
    if (episode == null) return;

    final duration = _currentDuration > Duration.zero
        ? _currentDuration
        : episode.duration;
    if (duration <= Duration.zero) return;

    _progress[episodeId] = PodcastProgress(
      episodeId: episodeId,
      position: _currentPosition,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    _persistLibrary();
  }

  void _flushProgress() {
    _persistActiveProgress();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  void _loadLibrary() {
    final box = _libraryBox;
    if (box == null) return;

    try {
      final raw = box.get('library');
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = decoded.cast<String, dynamic>();

      final subscriptions = data['subscriptions'];
      if (subscriptions is List) {
        for (final item in subscriptions.whereType<Map>()) {
          final show = PodcastShow.fromJson(item.cast<String, dynamic>());
          if (show.id.isEmpty) continue;
          _subscriptions[show.id] = show;
          _showsById[show.id] = show;
        }
      }

      final favorites = data['favorites'];
      if (favorites is List) {
        for (final item in favorites.whereType<Map>()) {
          final episode = PodcastEpisode.fromJson(item.cast<String, dynamic>());
          if (episode.id.isEmpty) continue;
          _favorites[episode.id] = episode;
          _episodeCache[episode.id] = episode;
        }
      }

      final history = data['history'];
      if (history is List) {
        for (final item in history.whereType<Map>()) {
          final episode = PodcastEpisode.fromJson(item.cast<String, dynamic>());
          if (episode.id.isEmpty) continue;
          _history.add(episode);
          _episodeCache[episode.id] = episode;
        }
      }

      final progress = data['progress'];
      if (progress is Map) {
        progress.forEach((key, value) {
          if (value is Map) {
            final entry = PodcastProgress.fromJson(
              value.cast<String, dynamic>(),
            );
            if (entry.episodeId.isNotEmpty) {
              _progress[entry.episodeId] = entry;
            }
          }
        });
      }

      final searches = data['recentSearches'];
      if (searches is List) {
        _recentSearches = searches
            .whereType<String>()
            .where((term) => term.trim().isNotEmpty)
            .toList();
      }
    } catch (error) {
      debugPrint('Podcast library load failed: $error');
    }
  }

  void _persistLibrary() {
    final box = _libraryBox;
    if (box == null) return;

    try {
      final data = {
        'subscriptions': _subscriptions.values
            .map((show) => show.toJson())
            .toList(),
        'favorites': _favorites.values.map((e) => e.toJson()).toList(),
        'history': _history.map((e) => e.toJson()).toList(),
        'progress': _progress.map((key, value) => MapEntry(key, value.toJson())),
        'recentSearches': _recentSearches,
      };
      unawaited(box.put('library', json.encode(data)));
    } catch (error) {
      debugPrint('Podcast library save failed: $error');
    }
  }

  void _rememberSearch(String term) {
    _recentSearches.removeWhere(
      (existing) => existing.toLowerCase() == term.toLowerCase(),
    );
    _recentSearches.insert(0, term);
    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
    }
    _persistLibrary();
  }

  void _cacheShows(Iterable<PodcastShow> shows) {
    for (final show in shows) {
      if (show.id.isNotEmpty) _showsById[show.id] = show;
    }
  }

  void _cacheEpisodes(Iterable<PodcastEpisode> episodes) {
    for (final episode in episodes) {
      if (episode.id.isNotEmpty) _episodeCache[episode.id] = episode;
    }
  }

  @override
  void dispose() {
    _flushProgress();
    _playerProvider?.removeListener(_onPlayerChanged);
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _api.dispose();
    super.dispose();
  }
}

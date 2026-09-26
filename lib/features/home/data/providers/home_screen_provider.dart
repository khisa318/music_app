import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import '../../../../core/models/song_model.dart';
import '../../../../core/providers/connectivity_provider.dart';
import '../../../trending/data/provider/trending_provider.dart';

part '../../../../generated/home_screen_provider.g.dart';

class HomeScreenProvider with ChangeNotifier {
  final YTMusic _ytMusic = GetIt.I<YTMusic>();
  final _collectionEquality = const DeepCollectionEquality();

  bool isHomeSectionsLoading = true;
  String _error = '';
  bool _isOfflineMode = false;
  bool _isLoadingHomeSections = false;
  bool _hasInitialized = false;

  List<dynamic> _homeSections = [];

  // Bumped whenever the cached DTO shape changes so stale entries are ignored.
  static const String _cacheKey = 'homeSectionsV2';
  static const String _cacheTimestampKey = 'lastFetchTimeV2';

  String get error => _error;
  List<dynamic> get homeSections => _homeSections;
  bool get isOfflineMode => _isOfflineMode;

  /// The genuine YouTube Music "Listen again" shelf, surfaced as the Speed Dial.
  ///
  /// YT Music returns this section as a list of `SongDetailed` rather than
  /// albums/playlists, so it is identified by content type instead of by title
  /// (the title is localised and has changed across app versions).
  List<SongInfo> get listenAgainSongs {
    final results = <SongInfo>[];

    for (final section in _homeSections) {
      final contents = section.contents;
      if (contents is! List || contents.isEmpty) continue;

      if (contents.every((c) => c is SongDetailed)) {
        for (final content in contents.whereType<SongDetailed>()) {
          results.add(_songDetailedToSongInfo(content));
        }
      } else if (contents.every((c) => c is SongInfo)) {
        for (final content in contents.whereType<SongInfo>()) {
          results.add(content);
        }
      }
    }

    return results;
  }

  static SongInfo _songDetailedToSongInfo(SongDetailed song) {
    return SongInfo(
      videoId: song.videoId,
      name: song.name,
      artists: [
        Artist(name: song.artist.name, id: song.artist.artistId ?? ''),
      ],
      thumbnails: song.thumbnails
          .map((t) => Thumbnail(url: t.url, width: t.width, height: t.height))
          .toList(),
      duration: Duration(seconds: song.duration ?? 0),
    );
  }

  /// True when a section is a pure track shelf, from either the live response
  /// ([SongDetailed]) or the Hive cache ([SongInfo]).
  static bool _isSongShelf(dynamic section) {
    final contents = section.contents;
    if (contents is! List || contents.isEmpty) return false;
    return contents.every((c) => c is SongDetailed || c is SongInfo);
  }

  /// Sections that are not song shelves, i.e. the album/playlist carousels.
  /// Song shelves belong to the Speed Dial and would otherwise be duplicated.
  List<dynamic> get carouselSections => _homeSections
      .where(
        (section) =>
            section.contents is List &&
            section.contents.isNotEmpty &&
            !_isSongShelf(section),
      )
      .toList();

  ConnectivityProvider? get _connectivityProvider {
    try {
      return GetIt.I<ConnectivityProvider>();
    } catch (e) {
      return null;
    }
  }

  Future<void> initialize() async {
    try {
      await loadHomeSections();
    } catch (e) {
      _error = 'Failed to initialize YT Music';
      debugPrint(_error);
      isHomeSectionsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadHomeSections({bool forceRefresh = false}) async {
    if (_isLoadingHomeSections || (!forceRefresh && _hasInitialized)) {
      return;
    }
    _isLoadingHomeSections = true;
    isHomeSectionsLoading = true;
    notifyListeners();

    try {
      if (forceRefresh) {
        await _fetchHomeSectionsFromAPI(notify: false);
      } else {
        await _loadHomeSectionsFromCache(notify: false);
      }
      _hasInitialized = true;
    } finally {
      _isLoadingHomeSections = false;
      isHomeSectionsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshData() async {
    await loadHomeSections(forceRefresh: true);
  }

  Future<void> saveHomeSections() async {
    try {
      final box = await Hive.openBox<dynamic>('home_sections_cache');
      await box.put(
        _cacheKey,
        _homeSections
            .map((section) => HomeSectionDTO.fromHomeSection(section))
            .toList(),
      );
      await box.put(
        _cacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Error saving home sections: $e');
    }
  }

  Future<void> loadSavedHomeSections() async {
    try {
      final box = await Hive.openBox<dynamic>('home_sections_cache');
      final cachedData = box.get(_cacheKey);
      if (cachedData != null) {
        final newSections = (cachedData as List)
            .cast<HomeSectionDTO>()
            .map((dto) => dto.toHomeSection())
            .toList();
        if (!_collectionEquality.equals(_homeSections, newSections)) {
          _homeSections = newSections;
        }
      }
      debugPrint('Loaded home sections from cache');
    } catch (e) {
      debugPrint('Error loading home sections: $e');
    }
  }

  Future<void> _loadHomeSectionsFromCache({bool notify = true}) async {
    if (notify) {
      isHomeSectionsLoading = true;
      notifyListeners();
    }
    try {
      await loadSavedHomeSections();

      final box = await Hive.openBox<dynamic>('home_sections_cache');
      final lastFetchTime = box.get(_cacheTimestampKey) as int?;
      bool needsRefresh = false;

      if (lastFetchTime != null) {
        final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchTime);
        if (DateTime.now().difference(lastFetch).inHours >= 4) {
          needsRefresh = true;
          debugPrint('Cache is older than 4 hours, fetching from API.');
        }
      } else if (_homeSections.isNotEmpty) {
        needsRefresh = true;
      }

      if ((_homeSections.isEmpty || needsRefresh) &&
          (_connectivityProvider?.canPerformNetworkOperations() ?? false)) {
        await _fetchHomeSectionsFromAPI(notify: false);
      } else if (_homeSections.isEmpty) {
        _isOfflineMode = true;
        _error = 'No cached data available. Please connect to internet.';
        debugPrint('No cached data and no internet connection');
      } else {
        _isOfflineMode =
            !(_connectivityProvider?.canPerformNetworkOperations() ?? false);
      }
    } catch (e) {
      debugPrint('Error loading home sections from cache: $e');
      _homeSections = [];
      _isOfflineMode = true;
    } finally {
      if (notify) {
        isHomeSectionsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchHomeSectionsFromAPI({bool notify = true}) async {
    if (!(_connectivityProvider?.canPerformNetworkOperations() ?? false)) {
      debugPrint('No internet connection - skipping API call');
      _isOfflineMode = true;
      return;
    }

    debugPrint('loading home sections from api');
    if (notify) {
      isHomeSectionsLoading = true;
      notifyListeners();
    }
    try {
      final sections = await _ytMusic.getHomeSections();
      final newSections = sections
          .where(
            (section) =>
                section.contents.isNotEmpty && section.title.isNotEmpty,
          )
          .toList();

      if (!_collectionEquality.equals(_homeSections, newSections)) {
        _homeSections = newSections;
        await saveHomeSections();
      }
      _isOfflineMode = false;
      _error = '';
      debugPrint('Loaded home sections from api');
    } catch (e) {
      debugPrint('Error fetching home sections from API: $e');
      _isOfflineMode = true;
      _error = 'Failed to load data from server';
    } finally {
      if (notify) {
        isHomeSectionsLoading = false;
        notifyListeners();
      }
    }
  }
}

class ContentItem {
  final String name;
  final String contentType;
  final String playlistId;
  final List<Thumbnail> thumbnails;

  ContentItem({
    required this.name,
    required this.contentType,
    required this.playlistId,
    required this.thumbnails,
  });
}

@HiveType(typeId: 3)
class HomeSectionDTO {
  @HiveField(0)
  final String title;
  @HiveField(1)
  final List<dynamic> contents;

  HomeSectionDTO({required this.title, required this.contents});

  factory HomeSectionDTO.fromHomeSection(HomeSection section) {
    return HomeSectionDTO(
      title: section.title,
      contents: section.contents.map<dynamic>((content) {
        if (content is AlbumDetailed) {
          return AlbumDetailedDTO.fromAlbumDetailed(content);
        } else if (content is PlaylistDetailed) {
          return PlaylistDetailedDTO.fromPlaylistDetailed(content);
        } else if (content is SongDetailed) {
          return SongInfoDTO.fromSongInfo(
            HomeScreenProvider._songDetailedToSongInfo(content),
          );
        }
        throw Exception('Unknown content type for DTO conversion');
      }).toList(),
    );
  }

  HomeSection toHomeSection() {
    return HomeSection(
      title: title,
      contents: contents.map<dynamic>((dto) {
        if (dto is AlbumDetailedDTO) {
          return dto.toAlbumDetailed();
        } else if (dto is PlaylistDetailedDTO) {
          return dto.toPlaylistDetailed();
        } else if (dto is SongInfoDTO) {
          final song = dto.toSongInfo();
          return SongDetailed(
            type: 'SONG',
            videoId: song.videoId,
            name: song.name,
            artist: ArtistBasic(
              name: song.artists.isEmpty ? '' : song.artists.first.name,
              artistId: song.artists.isEmpty ? null : song.artists.first.id,
            ),
            duration: song.duration.inSeconds,
            thumbnails: song.thumbnails
                .map((t) => ThumbnailFull(url: t.url, width: t.width, height: t.height))
                .toList(),
          );
        }
        throw Exception('Unknown content type for original conversion');
      }).toList(),
    );
  }
}

@HiveType(typeId: 8)
class ContentItemDTO {
  @HiveField(0)
  final String name;
  @HiveField(1)
  final String contentType;
  @HiveField(2)
  final String playlistId;
  @HiveField(3)
  final List<ThumbnailFullDTO> thumbnails;

  ContentItemDTO({
    required this.name,
    required this.contentType,
    required this.playlistId,
    required this.thumbnails,
  });
}

@HiveType(typeId: 6)
class AlbumDetailedDTO extends ContentItemDTO {
  @HiveField(4)
  final ArtistBasicDTO artist;
  @HiveField(5)
  final String albumId;

  AlbumDetailedDTO({
    required super.name,
    required super.contentType,
    required super.playlistId,
    required super.thumbnails,
    required this.artist,
    required this.albumId,
  });

  factory AlbumDetailedDTO.fromAlbumDetailed(AlbumDetailed album) {
    return AlbumDetailedDTO(
      name: album.name,
      contentType: album.type,
      playlistId: album.playlistId,
      thumbnails: album.thumbnails
          .map((t) => ThumbnailFullDTO.fromThumbnailFull(t))
          .toList(),
      artist: ArtistBasicDTO.fromArtistBasic(album.artist),
      albumId: album.albumId,
    );
  }

  AlbumDetailed toAlbumDetailed() {
    return AlbumDetailed(
      name: name,
      type: contentType,
      playlistId: playlistId,
      thumbnails: thumbnails.map((t) => t.toThumbnailFull()).toList(),
      artist: artist.toArtistBasic(),
      albumId: albumId,
    );
  }
}

@HiveType(typeId: 7)
class PlaylistDetailedDTO extends ContentItemDTO {
  PlaylistDetailedDTO({
    required super.name,
    required super.contentType,
    required super.playlistId,
    required super.thumbnails,
  });

  factory PlaylistDetailedDTO.fromPlaylistDetailed(PlaylistDetailed playlist) {
    return PlaylistDetailedDTO(
      name: playlist.name,
      contentType: playlist.type,
      playlistId: playlist.playlistId,
      thumbnails: playlist.thumbnails
          .map((t) => ThumbnailFullDTO.fromThumbnailFull(t))
          .toList(),
    );
  }

  PlaylistDetailed toPlaylistDetailed() {
    return PlaylistDetailed(
      name: name,
      type: contentType,
      playlistId: playlistId,
      thumbnails: thumbnails.map((t) => t.toThumbnailFull()).toList(),
      artist: ArtistBasic(name: ''),
    );
  }
}

@HiveType(typeId: 4)
class ArtistBasicDTO {
  @HiveField(0)
  final String name;

  ArtistBasicDTO({required this.name});

  factory ArtistBasicDTO.fromArtistBasic(ArtistBasic artist) {
    return ArtistBasicDTO(name: artist.name);
  }

  ArtistBasic toArtistBasic() {
    return ArtistBasic(name: name);
  }
}

@HiveType(typeId: 5)
class ThumbnailFullDTO {
  @HiveField(0)
  final String url;
  @HiveField(1)
  final int width;
  @HiveField(2)
  final int height;

  ThumbnailFullDTO({
    required this.url,
    required this.width,
    required this.height,
  });

  factory ThumbnailFullDTO.fromThumbnailFull(ThumbnailFull thumbnail) {
    return ThumbnailFullDTO(
      url: thumbnail.url,
      width: thumbnail.width,
      height: thumbnail.height,
    );
  }

  ThumbnailFull toThumbnailFull() {
    return ThumbnailFull(url: url, width: width, height: height);
  }
}

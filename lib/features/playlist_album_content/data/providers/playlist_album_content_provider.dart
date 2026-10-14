import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import '../../../../core/models/song_model.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../playlists/data/providers/playlist_album_library_provider.dart';
import '../models/local_playlist_content.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/download_provider.dart';

class PlaylistAlbumContentProvider extends ChangeNotifier {
  final ContentDetailsService _contentService = ContentDetailsService();

  /// Matches the remote initial page size so local playlists paginate the
  /// same way.
  static const int _initialSongLimit = 200;

  dynamic _content;
  bool _isLoading = true;
  String _contentDescription = '';
  List<dynamic> _songs = [];
  List<dynamic> _allSongs = [];
  int _currentSongPage = 0;
  Duration _totalDuration = Duration.zero;
  final bool _isPlaying = false;
  bool _isSaved = false;

  bool get isLoading => _isLoading;
  String get contentDescription => _contentDescription;
  List<dynamic> get songs => _songs;
  List<dynamic> get allSongs => _allSongs;
  int get currentSongPage => _currentSongPage;
  Duration get totalDuration => _totalDuration;
  bool get isPlaying => _isPlaying;
  bool get isSaved => _isSaved;

  /// Local playlists are stored by the user, so "add to / remove from library"
  /// has no meaning for them.
  bool get canToggleLibrary => _content is! LocalPlaylistContent;

  Future<void> loadContent(
    dynamic content, {
    PlaylistAlbumLibraryProvider? libraryProvider,
  }) async {
    _content = content;
    try {
      if (content is LocalPlaylistContent) {
        await _loadLocalContent(content, libraryProvider!);
        return;
      }

      final contentData = await _contentService.loadContentSongs(content);
      _applyLoadedContent(contentData);
    } catch (e) {
      debugPrint('Error loading content: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyLoadedContent(Map<String, dynamic> contentData) {
    final totalSeconds = contentData['allSongs'].fold(
      0,
      (sum, song) => sum + song.duration.inSeconds,
    );
    _songs = contentData['songs'];
    _allSongs = contentData['allSongs'];
    _contentDescription = contentData['description'];
    _totalDuration = Duration(seconds: totalSeconds);
    _isLoading = false;
    notifyListeners();
  }

  Future<List<SongInfo>> _readLocalSongs(
    LocalPlaylistContent content,
    PlaylistAlbumLibraryProvider library,
  ) async {
    final rows = await library.getPlaylistSongs(content.playlistName);
    return rows.map(SongInfo.fromHistoryMap).whereType<SongInfo>().toList();
  }

  void _applyLocalSongs(String description, List<SongInfo> songs) {
    _songs = songs.take(_initialSongLimit).toList();
    _allSongs = songs;
    _contentDescription = description;
    _totalDuration = Duration(
      seconds: songs.fold<int>(0, (sum, song) => sum + song.duration.inSeconds),
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadLocalContent(
    LocalPlaylistContent content,
    PlaylistAlbumLibraryProvider library,
  ) async {
    final songs = await _readLocalSongs(content, library);
    _applyLocalSongs('Playlist • ${songs.length} songs', songs);
  }

  /// Re-reads a local playlist's songs, keeping the current page.
  ///
  /// Called while a background Spotify import is still adding tracks so the
  /// open playlist fills in live.
  Future<void> refreshLocalSongs(PlaylistAlbumLibraryProvider library) async {
    final content = _content;
    if (content is! LocalPlaylistContent || _isLoading) return;

    final songs = await _readLocalSongs(content, library);
    if (songs.length == _allSongs.length) return;

    _songs = songs.take(_initialSongLimit).toList();
    _allSongs = songs;
    _contentDescription = 'Playlist • ${songs.length} songs';
    _totalDuration = Duration(
      seconds: songs.fold<int>(0, (sum, song) => sum + song.duration.inSeconds),
    );
    notifyListeners();
  }

  Future<void> checkIfSaved(
    dynamic content,
    PlaylistAlbumLibraryProvider libraryProvider,
  ) async {
    if (content is LocalPlaylistContent) return;

    final contentType = content is AlbumDetailed ? 'Album' : 'Playlist';
    await libraryProvider.loadAll();
    final savedItems = contentType == 'Album'
        ? libraryProvider.savedAlbums
        : libraryProvider.savedPlaylists;
    _isSaved = savedItems.any(
      (item) => item['playlistId'] == content.playlistId,
    );
    notifyListeners();
  }

  Future<String> addToLibrary(
    dynamic content,
    String contentDescription,
    Duration totalDuration,
    PlaylistAlbumLibraryProvider libraryProvider,
  ) async {
    final contentType = contentDescription.contains('Playlist')
        ? 'Playlist'
        : 'Album';
    final contentData = {
      'name': content.name,
      'thumbnail': content.thumbnails.last.url,
      'duration': totalDuration.inSeconds,
      'playlistId': content.playlistId,
      'contentType': contentType,
      'artist': contentType == 'Album' ? content.artist.name : '',
    };
    if (contentType == 'Playlist') {
      await libraryProvider.savePlaylist(contentData);
    } else if (contentType == 'Album') {
      await libraryProvider.saveAlbum(contentData);
    }
    _isSaved = true;
    notifyListeners();
    return 'Added to library';
  }

  Future<String> removeFromLibrary(
    dynamic content,
    String contentDescription,
    PlaylistAlbumLibraryProvider libraryProvider,
  ) async {
    final contentType = contentDescription.contains('Playlist')
        ? 'Playlist'
        : 'Album';
    final playlistId = content.playlistId;
    if (contentType == 'Playlist') {
      await libraryProvider.deletePlaylist(playlistId);
    } else if (contentType == 'Album') {
      await libraryProvider.deleteAlbum(playlistId);
    }
    _isSaved = false;
    notifyListeners();
    return 'Removed from library';
  }

  Future<void> playSong(
    dynamic song,
    PlayerProvider playerProvider,
    QueueProvider queueProvider,
    List<dynamic> allSongs,
    String playlistId,
  ) async {
    try {
      final playlistName = _content?.name ?? '';
      final playlistThumbnail = _content?.thumbnails?.last?.url ?? '';
      await _contentService.playSong(
        song,
        playerProvider,
        queueProvider,
        allSongs,
        playlistId: playlistId,
        playlistName: playlistName,
        playlistThumbnail: playlistThumbnail,
        isPlaylist:
            _content is PlaylistDetailed || _content is LocalPlaylistContent,
      );
      await queueProvider.saveQueue();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> loadMoreSongs() async {
    final newSongs = await _contentService.loadMoreContent(
      _songs,
      _allSongs,
      _currentSongPage + 1,
      100,
    );
    _currentSongPage++;
    _songs = newSongs;
    notifyListeners();
    return newSongs;
  }

  String formatTotalDuration() {
    final hours = _totalDuration.inHours;
    final minutes = _totalDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  void shareContent(dynamic content, String contentDescription) {
    final contentType = contentDescription.toLowerCase().contains('playlist')
        ? 'playlist'
        : 'album';
    // Local playlists have no YouTube URL to link to.
    final shareText = content is LocalPlaylistContent
        ? 'Check out this $contentType: ${content.name}'
        : 'Check out this $contentType: ${content.name} : https://www.music.youtube.com/playlist?list=${content.playlistId}';
    SharePlus.instance.share(ShareParams(text: shareText));
  }

  Future<void> downloadPlaylist(DownloadProvider downloadProvider) async {
    if (_allSongs.isEmpty) return;

    final playlistName = _content?.name ?? 'Unknown Playlist';
    await downloadProvider.downloadPlaylist(_allSongs, playlistName);
  }
}

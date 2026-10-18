import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/services/spotify_playlist_service.dart';
import '../../../../core/services/spotify_track_matcher.dart';

/// Live progress of a Spotify playlist being matched in the background.
class PlaylistImportProgress {
  final int total;
  int matched;
  bool done;

  PlaylistImportProgress({
    required this.total,
    this.matched = 0,
    this.done = false,
  });

  double get fraction => total <= 0 ? 0 : (matched / total).clamp(0.0, 1.0);
}

class PlaylistAlbumLibraryProvider with ChangeNotifier {
  static const String _playlistsBox = 'saved_playlists';
  static const String _albumsBox = 'saved_albums';
  static const String _createdBox = 'created_playlists';
  static const String _playlistSongsBox = 'playlist_songs';

  Box<String> get _playlists => Hive.box<String>(_playlistsBox);
  Box<String> get _albums => Hive.box<String>(_albumsBox);
  Box<String> get _createdPlaylistsBox => Hive.box<String>(_createdBox);
  Box<String> get _playlistSongs => Hive.box<String>(_playlistSongsBox);

  List<Map<String, dynamic>> _savedPlaylists = [];
  List<Map<String, dynamic>> _savedAlbums = [];
  List<Map<String, dynamic>> _createdPlaylists = [];
  bool _hasLoadedCreatedPlaylists = false;

  final Map<String, PlaylistImportProgress> _importProgress = {};

  bool isPlaylistsLoading = false;
  bool isAlbumsLoading = false;
  bool isCreatedPlaylistsLoading = false;

  List<Map<String, dynamic>> get savedPlaylists => _savedPlaylists;
  List<Map<String, dynamic>> get savedAlbums => _savedAlbums;
  List<Map<String, dynamic>> get createdPlaylists => _createdPlaylists;
  bool get hasLoadedCreatedPlaylists => _hasLoadedCreatedPlaylists;

  Future<void> loadSavedPlaylists({bool notify = true}) async {
    if (notify) {
      isPlaylistsLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }

    try {
      final values = _playlists.values.cast<String>().toList();
      final newList = values
          .map((e) => json.decode(e) as Map<String, dynamic>)
          .toList();

      newList.sort((a, b) {
        final aTs = (a['saved_at'] as int?) ?? 0;
        final bTs = (b['saved_at'] as int?) ?? 0;
        return bTs.compareTo(aTs);
      });

      _savedPlaylists = newList;
    } catch (e) {
      debugPrint('Error loading saved playlists: $e');
      _savedPlaylists = [];
    } finally {
      if (notify) {
        isPlaylistsLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
  }

  Future<void> loadSavedAlbums({bool notify = true}) async {
    if (notify) {
      isAlbumsLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }

    try {
      final values = _albums.values.cast<String>().toList();
      final newList = values
          .map((e) => json.decode(e) as Map<String, dynamic>)
          .toList();

      newList.sort((a, b) {
        final aTs = (a['saved_at'] as int?) ?? 0;
        final bTs = (b['saved_at'] as int?) ?? 0;
        return bTs.compareTo(aTs);
      });

      _savedAlbums = newList;
    } catch (e) {
      debugPrint('Error loading saved albums: $e');
      _savedAlbums = [];
    } finally {
      if (notify) {
        isAlbumsLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
  }

  Future<void> loadCreatedPlaylists({bool notify = true}) async {
    if (notify) {
      isCreatedPlaylistsLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }

    try {
      final values = _createdPlaylistsBox.values.cast<String>().toList();
      final newList = values
          .map((e) => json.decode(e) as Map<String, dynamic>)
          .toList();

      newList.sort((a, b) {
        final aTs =
            DateTime.tryParse(a['created'] ?? '')?.millisecondsSinceEpoch ?? 0;
        final bTs =
            DateTime.tryParse(b['created'] ?? '')?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });

      _createdPlaylists = newList;
    } catch (e) {
      debugPrint('Error loading created playlists: $e');
      _createdPlaylists = [];
    } finally {
      _hasLoadedCreatedPlaylists = true;
      if (notify) {
        isCreatedPlaylistsLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
  }

  Future<void> loadAll({bool notify = true}) async {
    if (notify) {
      isPlaylistsLoading = true;
      isAlbumsLoading = true;
      isCreatedPlaylistsLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }

    await Future.wait([
      loadSavedPlaylists(notify: false),
      loadSavedAlbums(notify: false),

      loadCreatedPlaylistsWithThumbnails(notify: false),
    ]);

    if (notify) {
      isPlaylistsLoading = false;
      isAlbumsLoading = false;
      isCreatedPlaylistsLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> savePlaylist(Map<String, dynamic> playlist) async {
    final playlistId =
        (playlist['playlistId'] ??
                DateTime.now().millisecondsSinceEpoch.toString())
            .toString();
    final item = Map<String, dynamic>.from(playlist);
    item['saved_at'] = DateTime.now().millisecondsSinceEpoch;
    await _playlists.put(playlistId, json.encode(item));
    await loadSavedPlaylists(notify: true);
  }

  Future<void> saveAlbum(Map<String, dynamic> album) async {
    final albumId =
        (album['albumId'] ?? DateTime.now().millisecondsSinceEpoch.toString())
            .toString();
    final item = Map<String, dynamic>.from(album);
    item['saved_at'] = DateTime.now().millisecondsSinceEpoch;
    await _albums.put(albumId, json.encode(item));
    await loadSavedAlbums(notify: true);
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _playlists.delete(playlistId);
    await loadSavedPlaylists(notify: true);
  }

  Future<void> deleteAlbum(String albumId) async {
    await _albums.delete(albumId);
    await loadSavedAlbums(notify: true);
  }

  Future<void> saveCreatedPlaylist(String name, {String? thumbnail}) async {
    final exists = _createdPlaylistsBox.values.cast<String>().any((e) {
      final item = json.decode(e) as Map<String, dynamic>;
      return item['name'] == name;
    });

    if (exists) {
      throw Exception('Playlist already exists');
    }

    final item = {
      'name': name,
      'created': DateTime.now().toIso8601String(),
      'thumbnail': thumbnail,
    };

    await _createdPlaylistsBox.put(name, json.encode(item));
    await loadCreatedPlaylists(notify: true);
  }

  /// Saves a playlist under [desiredName], appending " (2)", " (3)"… if a
  /// playlist with that name already exists, and returns the name used.
  Future<String> createPlaylistWithUniqueName(
    String desiredName, {
    String? thumbnail,
  }) async {
    var candidate = desiredName;
    var index = 2;
    while (true) {
      try {
        await saveCreatedPlaylist(candidate, thumbnail: thumbnail);
        return candidate;
      } catch (_) {
        candidate = '$desiredName ($index)';
        index++;
      }
    }
  }

  /// Live progress of a background import for [playlistName], or null.
  PlaylistImportProgress? getImportProgress(String playlistName) =>
      _importProgress[playlistName];

  bool isImportingPlaylist(String playlistName) {
    final progress = _importProgress[playlistName];
    return progress != null && !progress.done;
  }

  /// Matches [tracks] to YouTube Music and appends them to [playlistName] as
  /// they are found, so the playlist can be opened while this runs.
  Future<void> importSpotifyTracksIntoPlaylist(
    String playlistName,
    List<SpotifyTrack> tracks, {
    required int totalTracks,
    int alreadyMatched = 0,
  }) async {
    if (tracks.isEmpty) return;

    final progress = PlaylistImportProgress(
      total: totalTracks,
      matched: alreadyMatched,
    );
    _importProgress[playlistName] = progress;
    notifyListeners();

    try {
      await SpotifyTrackMatcher().matchAll(
        tracks,
        onMatched: (song) async {
          await saveSongToPlaylist(playlistName, song);
          progress.matched++;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Background Spotify import failed for $playlistName: $e');
    } finally {
      progress.done = true;
      notifyListeners();
    }
  }

  Future<void> deleteCreatedPlaylist(String name) async {
    await _createdPlaylistsBox.delete(name);

    await _playlistSongs.delete(name);
    await loadCreatedPlaylists(notify: true);
  }

  /// Renames a created playlist, moving both its metadata and its songs to
  /// the new key so nothing is orphaned. Throws when the target name is
  /// already taken.
  Future<void> renameCreatedPlaylist(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName) return;

    final collision =
        _createdPlaylistsBox.containsKey(trimmed) ||
        _playlistSongs.containsKey(trimmed);
    if (collision) {
      throw Exception('A playlist named "$trimmed" already exists');
    }

    final createdJson = _createdPlaylistsBox.get(oldName);
    final songsJson = _playlistSongs.get(oldName);

    if (createdJson != null) {
      final item = json.decode(createdJson) as Map<String, dynamic>;
      item['name'] = trimmed;
      await _createdPlaylistsBox.delete(oldName);
      await _createdPlaylistsBox.put(trimmed, json.encode(item));
    }
    if (songsJson != null) {
      await _playlistSongs.delete(oldName);
      await _playlistSongs.put(trimmed, songsJson);
    }

    await loadCreatedPlaylistsWithThumbnails(notify: true);
  }

  /// Sets the playlist cover to the picture of the song at the top of the
  /// playlist.
  Future<void> setCoverFromTopSong(String playlistName) async {
    final thumbnail = await getTopSongThumbnail(playlistName);
    await _applyThumbnail(playlistName, thumbnail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  Future<void> saveSongToPlaylist(
    String playlistName,
    Map<String, dynamic> song,
  ) async {
    final existingJson = _playlistSongs.get(playlistName);
    List<dynamic> songs = [];
    if (existingJson != null) {
      try {
        songs = json.decode(existingJson) as List<dynamic>;
      } catch (_) {
        songs = [];
      }
    }
    songs.add(song);
    await _playlistSongs.put(playlistName, json.encode(songs));

    try {
      // The cover follows the top song of the playlist.
      final newThumb = await getTopSongThumbnail(playlistName);
      await _applyThumbnail(playlistName, newThumb);
    } catch (e) {
      debugPrint(
        'Error updating created playlist thumbnail for $playlistName: $e',
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  Future<void> removeSongFromPlaylist(
    String playlistName,
    String songId,
  ) async {
    final existingJson = _playlistSongs.get(playlistName);
    if (existingJson == null) return;
    try {
      final songs = (json.decode(existingJson) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      songs.removeWhere((s) => s['id'].toString() == songId.toString());
      await _playlistSongs.put(playlistName, json.encode(songs));

      try {
        final latestThumb = await getTopSongThumbnail(playlistName);
        await _applyThumbnail(playlistName, latestThumb);
      } catch (e) {
        debugPrint(
          'Error updating thumbnail after removal for $playlistName: $e',
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error removing song from $playlistName: $e');
    }
  }

  /// Writes [thumbnail] (or removes the key when null) to the created
  /// playlist's stored metadata and its in-memory entry.
  Future<void> _applyThumbnail(String playlistName, String? thumbnail) async {
    final createdJson = _createdPlaylistsBox.get(playlistName);
    if (createdJson == null) return;

    final createdItem = json.decode(createdJson) as Map<String, dynamic>;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      createdItem['thumbnail'] = thumbnail;
    } else {
      createdItem.remove('thumbnail');
    }
    await _createdPlaylistsBox.put(playlistName, json.encode(createdItem));

    final idx = _createdPlaylists.indexWhere((p) => p['name'] == playlistName);
    if (idx != -1) {
      if (thumbnail != null && thumbnail.isNotEmpty) {
        _createdPlaylists[idx]['thumbnail'] = thumbnail;
      } else {
        _createdPlaylists[idx].remove('thumbnail');
      }
    }
  }

  Future<void> reorderPlaylistSongs(
    String playlistName,
    int oldIndex,
    int newIndex,
  ) async {
    final existingJson = _playlistSongs.get(playlistName);
    if (existingJson == null) return;
    try {
      final songs = (json.decode(existingJson) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
      if (oldIndex < 0 ||
          newIndex < 0 ||
          oldIndex >= songs.length ||
          newIndex > songs.length) {
        return;
      }
      if (oldIndex == newIndex) return;
      final item = songs.removeAt(oldIndex);
      final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
      songs.insert(insertIndex, item);
      await _playlistSongs.put(playlistName, json.encode(songs));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error reordering songs in $playlistName: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPlaylistSongs(
    String playlistName,
  ) async {
    final existingJson = _playlistSongs.get(playlistName);
    if (existingJson == null) return [];
    try {
      final list = (json.decode(existingJson) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return list;
    } catch (e) {
      debugPrint('Error decoding songs for $playlistName: $e');
      return [];
    }
  }

  Future<int> getSongCountForPlaylist(String playlistName) async {
    final songs = await getPlaylistSongs(playlistName);
    return songs.length;
  }

  /// The cover is the picture of the song at the top of the playlist.
  Future<String?> getTopSongThumbnail(String playlistName) async {
    final songs = await getPlaylistSongs(playlistName);
    if (songs.isEmpty) return null;

    final thumbnail = songs.first['thumbnail']?.toString();
    return (thumbnail == null || thumbnail.isEmpty) ? null : thumbnail;
  }

  /// Kept for callers written against the old name. The cover now tracks the
  /// top song rather than the most recently added one.
  Future<String?> getLatestSongThumbnail(String playlistName) =>
      getTopSongThumbnail(playlistName);

  Future<void> loadCreatedPlaylistsWithThumbnails({bool notify = true}) async {
    if (notify) {
      isCreatedPlaylistsLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }

    try {
      final values = _createdPlaylistsBox.values.cast<String>().toList();
      final newList = values
          .map((e) => json.decode(e) as Map<String, dynamic>)
          .toList();

      newList.sort((a, b) {
        final aTs =
            DateTime.tryParse(a['created'] ?? '')?.millisecondsSinceEpoch ?? 0;
        final bTs =
            DateTime.tryParse(b['created'] ?? '')?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });

      for (var playlist in newList) {
        final latestThumbnail = await getLatestSongThumbnail(playlist['name']);
        if (latestThumbnail != null) {
          playlist['thumbnail'] = latestThumbnail;
        }
      }

      _createdPlaylists = newList;
    } catch (e) {
      debugPrint('Error loading created playlists: $e');
      _createdPlaylists = [];
    } finally {
      _hasLoadedCreatedPlaylists = true;
      if (notify) {
        isCreatedPlaylistsLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
  }
}

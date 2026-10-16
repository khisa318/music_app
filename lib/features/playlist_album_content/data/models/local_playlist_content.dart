import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';

/// Content describing a locally stored (created) playlist.
///
/// It duck-types the remote `PlaylistDetailed` / `AlbumDetailed` objects that
/// [PlaylistAlbumContent] already renders, so playlists whose songs live in
/// Hive instead of on YouTube can reuse the exact same detail screen.
class LocalPlaylistContent {
  /// Hive key the playlist's songs are stored under.
  String playlistName;

  String name;
  final String thumbnailUrl;

  LocalPlaylistContent({
    required this.playlistName,
    required this.name,
    required this.thumbnailUrl,
  });

  /// Used as the playback context id; there is no remote playlist to link to.
  String get playlistId => playlistName;

  List<ThumbnailFull> get thumbnails => [
    ThumbnailFull(url: thumbnailUrl, width: 600, height: 600),
  ];
}

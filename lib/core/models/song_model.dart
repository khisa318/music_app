import 'dart:math' as math;

class SongInfo {
  final String videoId;
  final String name;
  final List<Artist> artists;
  final List<Thumbnail> thumbnails;
  final Duration duration;

  /// Direct, already-resolved audio stream. Podcast episodes carry their RSS
  /// enclosure URL here so [PlayerService] can open it without going through
  /// the YouTube/JioSaavn resolvers. Music leaves this null.
  final String? audioUrl;

  /// Whether this row belongs to the Podcasts feature. Podcast entries are kept
  /// out of music history/video-detail lookups but share the same player and
  /// background audio service as music.
  final bool isPodcast;

  SongInfo({
    required this.videoId,
    required this.name,
    required this.artists,
    required this.thumbnails,
    required this.duration,
    this.audioUrl,
    this.isPodcast = false,
  });

  /// Rebuilds a song from a play-history row.
  ///
  /// [PlayerProvider] persists history as loosely typed maps and older rows were
  /// written with slightly different keys, so every field is read
  /// defensively: a malformed row yields `null` instead of throwing while the
  /// Home screen builds.
  static SongInfo? fromHistoryMap(Map<String, dynamic> song) {
    final rawId = song['id'] ?? song['videoId'];
    final id = rawId?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final title = (song['title'] ?? song['name'])?.toString().trim() ?? '';
    if (title.isEmpty) return null;

    final artists = <Artist>[];
    final rawArtists = song['artists'];
    if (rawArtists is List) {
      for (final a in rawArtists) {
        if (a is Map) {
          final name = a['name']?.toString() ?? '';
          if (name.isNotEmpty) {
            artists.add(Artist(name: name, id: a['id']?.toString() ?? ''));
          }
        } else if (a != null) {
          artists.add(Artist(name: a.toString(), id: ''));
        }
      }
    }
    if (artists.isEmpty) {
      final fallback = song['artist']?.toString() ?? '';
      if (fallback.isNotEmpty) artists.add(Artist(name: fallback, id: ''));
    }

    return SongInfo(
      videoId: id,
      name: title,
      artists: artists.isEmpty ? [Artist(name: '', id: '')] : artists,
      thumbnails: [
        Thumbnail(
          url: (song['thumbnail'] ?? '').toString(),
          width: 480,
          height: 480,
        ),
      ],
      duration: Duration(seconds: _toSeconds(song['duration'])),
      audioUrl: (song['audioUrl'] as String?)?.trim().isEmpty == true
          ? null
          : song['audioUrl']?.toString(),
      isPodcast: song['isPodcast'] == true,
    );
  }

  /// History rows store duration in seconds, but some legacy rows hold a
  /// string, so parse defensively instead of throwing mid-build.
  static int _toSeconds(dynamic value) {
    if (value is int) return math.max(0, value);
    if (value is num) return math.max(0, value.toInt());
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class Artist {
  final String name;
  final String id;

  Artist({required this.name, required this.id});
}

class Thumbnail {
  final String url;
  final int width;
  final int height;

  Thumbnail({required this.url, required this.width, required this.height});
}

class ArtistInfo {
  final String id;
  final String name;
  final String thumbnailUrl;

  ArtistInfo({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
  });
}

import 'dart:convert';

import 'package:dio/dio.dart';

/// A single track read from a public Spotify playlist.
class SpotifyTrack {
  final String title;
  final String artists;
  final int durationMs;

  const SpotifyTrack({
    required this.title,
    required this.artists,
    required this.durationMs,
  });

  /// The first credited artist, used as the primary search term.
  String get primaryArtist {
    if (artists.isEmpty) return '';
    return artists.split(',').first.trim();
  }
}

/// Playlist metadata plus its full track list.
class SpotifyPlaylist {
  final String id;
  final String name;
  final String owner;
  final String? thumbnail;
  final List<SpotifyTrack> tracks;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.owner,
    required this.thumbnail,
    required this.tracks,
  });
}

/// The reason a Spotify playlist could not be loaded.
enum SpotifyImportError { notFound, network, parse }

class SpotifyImportException implements Exception {
  final SpotifyImportError type;
  final String? details;

  const SpotifyImportException(this.type, {this.details});

  @override
  String toString() => 'SpotifyImportException($type, $details)';
}

/// Reads public Spotify playlists without authentication by scraping the
/// JSON embedded in the playlist's embed page.
class SpotifyPlaylistService {
  SpotifyPlaylistService({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;

  static Dio _defaultDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      responseType: ResponseType.plain,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ),
  );

  /// Matches every supported Spotify playlist link and returns its id.
  ///
  /// Accepts `open.spotify.com/playlist/{id}` (including `intl-xx/` locale
  /// prefixes and query strings such as `?si=`) and `spotify:playlist:{id}`.
  /// Returns `null` when [url] is not a valid playlist link.
  static String? extractPlaylistId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    // Spotify URI: spotify:playlist:{id}
    final uriMatch = RegExp(
      r'^spotify:playlist:([a-zA-Z0-9]{22})',
    ).firstMatch(trimmed);
    if (uriMatch != null) return uriMatch.group(1);

    // Web link, tolerating a locale path segment and query parameters. The
    // match is intentionally lenient at the end so links pasted with trailing
    // share text still resolve.
    final webMatch = RegExp(
      r'^(?:https?://)?(?:open|play)\.spotify\.com/(?:intl-[a-zA-Z-]+/)?playlist/([a-zA-Z0-9]{22})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (webMatch != null) return webMatch.group(1);

    return null;
  }

  /// Fetches and parses the playlist. Throws [SpotifyImportException] with a
  /// typed reason so callers can show a specific message.
  Future<SpotifyPlaylist> getPlaylist(String playlistId) async {
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        'https://open.spotify.com/embed/playlist/$playlistId',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 410) {
        throw const SpotifyImportException(SpotifyImportError.notFound);
      }
      throw SpotifyImportException(
        SpotifyImportError.network,
        details: e.message,
      );
    }

    final html = response.data ?? '';
    final scriptMatch = RegExp(
      r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);

    if (scriptMatch == null) {
      throw const SpotifyImportException(SpotifyImportError.parse);
    }

    Map<String, dynamic> decoded;
    try {
      decoded = json.decode(scriptMatch.group(1)!) as Map<String, dynamic>;
    } catch (e) {
      throw SpotifyImportException(SpotifyImportError.parse, details: '$e');
    }

    // Missing or private playlists return an HTTP 200 page whose embedded
    // payload carries a 404 status.
    final pageProps = decoded['props']?['pageProps'];
    if (pageProps is Map) {
      final status = pageProps['status'];
      if (status is num && status >= 400) {
        throw const SpotifyImportException(SpotifyImportError.notFound);
      }
    }

    final entity = _findEntity(decoded);
    if (entity == null) {
      throw const SpotifyImportException(SpotifyImportError.parse);
    }

    final tracks = _parseTracks(entity['trackList']);

    if (tracks.isEmpty) {
      throw const SpotifyImportException(SpotifyImportError.notFound);
    }

    final name =
        _asString(entity['name']) ??
        _asString(entity['title']) ??
        'Spotify Playlist';

    return SpotifyPlaylist(
      id: playlistId,
      name: name,
      owner: _asString(entity['subtitle']) ?? 'Spotify',
      thumbnail: _parseCoverArt(entity['coverArt']),
      tracks: tracks,
    );
  }

  /// Walks the JSON for the object that holds the track list.
  static Map<String, dynamic>? _findEntity(Map<String, dynamic> root) {
    // Preferred, versioned path.
    final direct =
        root['props']?['pageProps']?['state']?['data']?['entity'];
    if (direct is Map && direct['trackList'] is List) {
      return Map<String, dynamic>.from(direct);
    }

    // Fallback: search anywhere in the tree.
    return _searchForTrackList(root);
  }

  static Map<String, dynamic>? _searchForTrackList(dynamic node) {
    if (node is Map) {
      final list = node['trackList'];
      if (list is List && list.isNotEmpty) {
        return Map<String, dynamic>.from(node.map((k, v) => MapEntry('$k', v)));
      }
      for (final value in node.values) {
        final found = _searchForTrackList(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _searchForTrackList(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  static List<SpotifyTrack> _parseTracks(dynamic trackList) {
    final tracks = <SpotifyTrack>[];
    if (trackList is! List) return tracks;

    for (final item in trackList) {
      if (item is! Map) continue;

      final entityType = _asString(item['entityType']);
      if (entityType != null && entityType != 'track') continue;

      final title = _asString(item['title']);
      if (title == null || title.isEmpty) continue;

      final durationRaw = item['duration'];
      final durationMs = durationRaw is num ? durationRaw.toInt() : 0;

      tracks.add(
        SpotifyTrack(
          title: title,
          artists: _asString(item['subtitle']) ?? '',
          durationMs: durationMs,
        ),
      );
    }
    return tracks;
  }

  static String? _parseCoverArt(dynamic coverArt) {
    if (coverArt is! Map) return null;
    final sources = coverArt['sources'];
    if (sources is! List || sources.isEmpty) return null;
    final first = sources.first;
    if (first is Map) return _asString(first['url']);
    return null;
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

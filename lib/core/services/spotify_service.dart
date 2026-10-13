import 'dart:convert';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

enum PlaylistSource { spotify, youtube, unknown }

class SpotifyTrack {
  final String title;
  final String artist;
  final int durationSeconds;

  const SpotifyTrack({
    required this.title,
    required this.artist,
    required this.durationSeconds,
  });
}

class SpotifyPlaylist {
  final String name;
  final String thumbnail;
  final List<SpotifyTrack> tracks;

  const SpotifyPlaylist({
    required this.name,
    required this.thumbnail,
    required this.tracks,
  });
}

class SpotifyService {
  final http.Client _client;
  final YTMusic _ytMusic;

  SpotifyService({http.Client? client, YTMusic? ytMusic})
    : _client = client ?? http.Client(),
      _ytMusic = ytMusic ?? GetIt.I<YTMusic>();

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  static final RegExp _youtubeUrlPattern = RegExp(
    r'youtube\.com|youtu\.be|music\.youtube\.com|youtube:',
    caseSensitive: false,
  );

  static final RegExp _rawSpotifyIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');

  PlaylistSource detectSource(String input) {
    final value = input.trim();
    if (value.isEmpty) return PlaylistSource.unknown;
    if (value.toLowerCase().contains('spotify')) return PlaylistSource.spotify;
    if (_rawSpotifyIdPattern.hasMatch(value)) return PlaylistSource.spotify;
    if (_youtubeUrlPattern.hasMatch(value)) return PlaylistSource.youtube;
    return PlaylistSource.unknown;
  }

  String? extractPlaylistId(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    if (_rawSpotifyIdPattern.hasMatch(value)) {
      return value;
    }

    final uriMatch = RegExp(
      r'/playlist/([A-Za-z0-9]+)',
    ).firstMatch(value);
    if (uriMatch != null) {
      return uriMatch.group(1);
    }

    final schemeMatch = RegExp(
      r'spotify:playlist:([A-Za-z0-9]+)',
    ).firstMatch(value);
    if (schemeMatch != null) {
      return schemeMatch.group(1);
    }

    return null;
  }

  Future<SpotifyPlaylist?> fetchPlaylist(String playlistId) async {
    if (playlistId.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://open.spotify.com/embed/playlist/$playlistId',
      );

      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': _userAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint(
          'Spotify embed request failed: ${response.statusCode}',
        );
        return null;
      }

      final nextDataMatch = RegExp(
        r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>',
        dotAll: true,
      ).firstMatch(response.body);

      if (nextDataMatch == null) {
        debugPrint('Spotify embed page missing __NEXT_DATA__');
        return null;
      }

      final decoded = jsonDecode(nextDataMatch.group(1)!);
      if (decoded is! Map<String, dynamic>) return null;

      final entity = _nav(decoded, [
        'props',
        'pageProps',
        'state',
        'data',
        'entity',
      ]);

      if (entity is! Map) {
        debugPrint('Spotify embed payload missing entity');
        return null;
      }

      final name =
          (entity['name'] ?? entity['title'] ?? 'Spotify Playlist').toString();
      final thumbnail = _extractThumbnail(entity);
      final tracks = _extractTracks(entity);

      return SpotifyPlaylist(
        name: name.trim().isEmpty ? 'Spotify Playlist' : name.trim(),
        thumbnail: thumbnail,
        tracks: tracks,
      );
    } catch (e) {
      debugPrint('Error fetching Spotify playlist: $e');
      return null;
    }
  }

  String _extractThumbnail(Map entity) {
    final coverArt = entity['coverArt'];
    if (coverArt is Map) {
      final sources = coverArt['sources'];
      if (sources is List && sources.isNotEmpty) {
        final first = sources.first;
        if (first is Map && first['url'] != null) {
          return first['url'].toString();
        }
      }
    }

    final images = entity['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map && first['url'] != null) {
        return first['url'].toString();
      }
    }

    return '';
  }

  List<SpotifyTrack> _extractTracks(Map entity) {
    final trackList = entity['trackList'];
    final tracks = <SpotifyTrack>[];

    if (trackList is! List) return tracks;

    for (final item in trackList) {
      if (item is! Map) continue;

      final title = item['title']?.toString();
      if (title == null || title.trim().isEmpty) continue;

      final artist =
          item['subtitle']?.toString() ?? item['artist']?.toString() ?? '';

      final durationRaw = item['duration'];
      final durationSeconds = durationRaw is num
          ? (durationRaw / 1000).round()
          : 0;

      tracks.add(
        SpotifyTrack(
          title: title.trim(),
          artist: artist.trim(),
          durationSeconds: durationSeconds,
        ),
      );
    }

    return tracks;
  }

  Future<List<Map<String, dynamic>>> matchTracksToYouTube(
    List<SpotifyTrack> tracks, {
    void Function(int completed, int total)? onProgress,
    String? fallbackThumbnail,
  }) async {
    final matched = <Map<String, dynamic>>[];

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];

      try {
        final query = '${track.title} ${track.artist}'.trim();
        final songs = await _ytMusic.searchSongs(query);

        if (songs.isNotEmpty) {
          final song = songs.first;
          matched.add({
            'id': song.videoId,
            'title': song.name,
            'artist': song.artist.name,
            'artistId': song.artist.artistId ?? '',
            'duration': song.duration ?? track.durationSeconds,
            'thumbnail': song.thumbnails.isNotEmpty
                ? song.thumbnails.last.url
                : (fallbackThumbnail ?? ''),
          });
        }
      } catch (e) {
        debugPrint('Failed to match Spotify track "${track.title}": $e');
      }

      onProgress?.call(i + 1, tracks.length);
    }

    return matched;
  }

  dynamic _nav(dynamic root, List items) {
    dynamic result = root;
    for (final item in items) {
      if (result is Map && result.containsKey(item)) {
        result = result[item];
      } else {
        return null;
      }
    }
    return result;
  }
}

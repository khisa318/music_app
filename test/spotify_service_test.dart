import 'dart:convert';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music_app/core/services/spotify_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.statusCode, this.body);

  final int statusCode;
  final String body;
  Uri? lastUri;
  Map<String, String>? lastHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    lastHeaders = request.headers;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }
}

String _embedHtml(Map<String, dynamic> entity) {
  final payload = {
    'props': {
      'pageProps': {
        'state': {
          'data': {'entity': entity},
        },
      },
    },
  };
  return '<!DOCTYPE html><html><body>'
      '<script id="__NEXT_DATA__" type="application/json">'
      '${jsonEncode(payload)}'
      '</script></body></html>';
}

Map<String, dynamic> _entity({
  String name = 'My Playlist',
  List<Map<String, dynamic>>? tracks,
}) {
  return {
    'type': 'playlist',
    'name': name,
    'coverArt': {
      'sources': [
        {'url': 'https://i.scdn.co/image/cover.jpg'},
      ],
    },
    'trackList':
        tracks ??
        [
          {
            'title': 'Stop The Wedding!',
            'subtitle': 'Ashe',
            'duration': 198840,
            'uri': 'spotify:track:3zOYmiNOuyDL0ClxJcEJ0T',
          },
          {
            'title': 'Nicole Kidman',
            'subtitle': 'ADÉLA',
            'duration': 181270,
          },
        ],
  };
}

SpotifyService _service(_FakeClient client) =>
    SpotifyService(client: client, ytMusic: YTMusic());

void main() {
  group('detectSource', () {
    final service = _service(_FakeClient(200, ''));

    test('recognises Spotify links', () {
      expect(
        service.detectSource('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        PlaylistSource.spotify,
      );
      expect(
        service.detectSource('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        PlaylistSource.spotify,
      );
      expect(
        service.detectSource('37i9dQZF1DXcBWIGoYBM5M'),
        PlaylistSource.spotify,
      );
    });

    test('recognises YouTube links', () {
      expect(
        service.detectSource('https://www.youtube.com/playlist?list=PLabc123'),
        PlaylistSource.youtube,
      );
      expect(
        service.detectSource('https://youtu.be/abc123'),
        PlaylistSource.youtube,
      );
      expect(
        service.detectSource('https://music.youtube.com/playlist?list=PLabc'),
        PlaylistSource.youtube,
      );
    });

    test('rejects unknown input', () {
      expect(service.detectSource(''), PlaylistSource.unknown);
      expect(service.detectSource('just some text'), PlaylistSource.unknown);
    });
  });

  group('extractPlaylistId', () {
    final service = _service(_FakeClient(200, ''));

    test('parses a plain playlist link and strips query params', () {
      expect(
        service.extractPlaylistId(
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc',
        ),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('parses an embed link', () {
      expect(
        service.extractPlaylistId(
          'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
        ),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('parses an intl localised link', () {
      expect(
        service.extractPlaylistId(
          'https://open.spotify.com/intl-de/playlist/37i9dQZF1DXcBWIGoYBM5M',
        ),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('parses a spotify URI and a raw id', () {
      expect(
        service.extractPlaylistId('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(
        service.extractPlaylistId('37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('returns null for invalid input', () {
      expect(service.extractPlaylistId('not a link'), isNull);
      expect(service.extractPlaylistId(''), isNull);
    });
  });

  group('fetchPlaylist', () {
    test('parses name, cover and tracks from the embed payload', () async {
      final client = _FakeClient(200, _embedHtml(_entity()));
      final playlist = await _service(client).fetchPlaylist('abc');

      expect(playlist, isNotNull);
      expect(playlist!.name, 'My Playlist');
      expect(playlist.thumbnail, 'https://i.scdn.co/image/cover.jpg');
      expect(playlist.tracks.length, 2);
      expect(playlist.tracks.first.title, 'Stop The Wedding!');
      expect(playlist.tracks.first.artist, 'Ashe');
      expect(playlist.tracks.first.durationSeconds, 199);
      expect(playlist.tracks[1].durationSeconds, 181);
    });

    test('requests the embed endpoint over https', () async {
      final client = _FakeClient(200, _embedHtml(_entity()));
      await _service(client).fetchPlaylist('37i9dQZF1DXcBWIGoYBM5M');

      expect(client.lastUri?.host, 'open.spotify.com');
      expect(
        client.lastUri?.path,
        '/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('returns null on a non-200 response', () async {
      final client = _FakeClient(404, '');
      expect(await _service(client).fetchPlaylist('abc'), isNull);
    });

    test('returns null when __NEXT_DATA__ is missing', () async {
      final client = _FakeClient(200, '<html><body>nope</body></html>');
      expect(await _service(client).fetchPlaylist('abc'), isNull);
    });

    test('returns null when the entity is missing', () async {
      final client = _FakeClient(200, '<script id="__NEXT_DATA__">{"props":{}}</script>');
      expect(await _service(client).fetchPlaylist('abc'), isNull);
    });

    test('skips malformed track entries', () async {
      final entity = _entity(
        tracks: [
          {'subtitle': 'no title', 'duration': 1000},
          {'title': 'Valid Song', 'subtitle': 'Artist', 'duration': 60000},
        ],
      );
      final client = _FakeClient(200, _embedHtml(entity));
      final playlist = await _service(client).fetchPlaylist('abc');

      expect(playlist!.tracks.length, 1);
      expect(playlist.tracks.single.title, 'Valid Song');
      expect(playlist.tracks.single.durationSeconds, 60);
    });

    test('falls back to a default name for a blank title', () async {
      final client = _FakeClient(200, _embedHtml(_entity(name: '   ')));
      final playlist = await _service(client).fetchPlaylist('abc');

      expect(playlist!.name, 'Spotify Playlist');
    });
  });
}

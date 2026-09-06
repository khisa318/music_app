import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'yt-stream.dart' as stream_provider;
import 'jiosaavn_isolate.dart';

Future<Map<String, dynamic>> _fetchYoutubeUrl(
  String videoId,
  String streamingQuality,
  bool forDownloading,
) async {
  try {
    debugPrint('Fetching from YouTube for videoId: $videoId');

    final streamProvider = await stream_provider.StreamProvider.fetch(videoId);

    if (!streamProvider.playable) {
      return {
        'success': false,
        'source': 'youtube',
        'errorType': 'unavailable',
        'error': streamProvider.statusMSG.isNotEmpty
            ? streamProvider.statusMSG
            : 'This YouTube video is unavailable.',
      };
    }

    if (streamProvider.audioFormats == null ||
        streamProvider.audioFormats!.isEmpty) {
      return {
        'success': false,
        'source': 'youtube',
        'errorType': 'no_audio',
        'error': 'No playable audio stream was found.',
      };
    }

    debugPrint(
      'Audio streams found: '
      '${streamProvider.audioFormats!.length}',
    );

    stream_provider.Audio? selectedAudio;

    switch (streamingQuality.toLowerCase()) {
      case 'low':
        selectedAudio = streamProvider.lowQualityAudio;
        break;

      case 'medium':
        selectedAudio = streamProvider.highestBitrateMp4aAudio;
        break;

      case 'high':
        selectedAudio = forDownloading
            ? streamProvider.highestBitrateMp4aAudio
            : streamProvider.highestQualityAudio;
        break;

      default:
        selectedAudio = forDownloading
            ? streamProvider.highestBitrateMp4aAudio
            : streamProvider.highestQualityAudio;
        break;
    }

    selectedAudio ??= streamProvider.audioFormats!.first;

    final extension = selectedAudio.audioCodec == stream_provider.Codec.mp4a
        ? 'm4a'
        : 'opus';

    int? expiry;

    try {
      final uri = Uri.parse(selectedAudio.url);
      final expireParam = uri.queryParameters['expire'];

      if (expireParam != null) {
        expiry = int.tryParse(expireParam);
      }
    } catch (_) {
      // Expiry is optional.
    }

    return {
      'success': true,
      'url': selectedAudio.url,
      'expiry': expiry,
      'bitrate': selectedAudio.bitrate,
      'size': selectedAudio.size,
      'source': 'youtube',
      'extension': extension,
      'duration': selectedAudio.duration,
    };
  } catch (e) {
    debugPrint('YouTube audio URL failed for $videoId: $e');

    return {
      'success': false,
      'source': 'youtube',
      'errorType': _getErrorType(e),
      'error': _getUserFriendlyError(e),
    };
  }
}

String _getErrorType(Object error) {
  final String message = error.toString().toLowerCase();

  if (message.contains('unavailable') ||
      message.contains('private') ||
      message.contains('taken down') ||
      message.contains('does not exist')) {
    return 'unavailable';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('timeout')) {
    return 'network';
  }

  if (message.contains('no audio')) {
    return 'no_audio';
  }

  return 'unknown';
}

String _getUserFriendlyError(Object error) {
  final String message = error.toString().toLowerCase();

  if (message.contains('unavailable') ||
      message.contains('private') ||
      message.contains('taken down') ||
      message.contains('does not exist')) {
    return 'This song is currently unavailable.';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('timeout')) {
    return 'Unable to connect. Check your internet connection.';
  }

  if (message.contains('no audio')) {
    return 'No playable audio was found for this song.';
  }

  return 'Unable to play this song right now.';
}

Future<Map<String, dynamic>> _fetchManifestDirect(
  Map<String, dynamic> params,
) async {
  final token = params['rootIsolateToken'] as RootIsolateToken?;

  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  try {
    final videoId = params['videoId'] as String;

    final streamingQuality = params['streamingQuality'] as String? ?? 'high';

    final forDownloading = params['forDownloading'] as bool? ?? false;

    final jioSaavnEnabled = params['jioSaavnEnabled'] as bool? ?? true;

    final title = params['title'] as String?;
    final artist = params['artist'] as String?;

    // ----------------------------------------------------------
    // TRY JIOSAAVN
    // ----------------------------------------------------------

    if (jioSaavnEnabled &&
        title != null &&
        artist != null &&
        title.isNotEmpty &&
        artist.isNotEmpty) {
      try {
        debugPrint(
          'Attempting JioSaavn search for: '
          '$title - $artist',
        );

        final saavnResult = await JioSaavnIsolate.searchSong(
          title: title,
          artist: artist,
          timeout: const Duration(seconds: 8),
        );

        if (saavnResult['success'] == true) {
          final saavnUrl = saavnResult['url'] as String;

          debugPrint('JioSaavn URL found');

          return {
            'success': true,
            'url': saavnUrl,
            'expiry': null,
            'bitrate': null,
            'size': null,
            'source': 'jiosaavn',
            'similarity_score': saavnResult['similarity_score'],
            'duration': saavnResult['duration'],
          };
        }

        debugPrint(
          'JioSaavn search failed: '
          '${saavnResult['error']}',
        );
      } catch (e) {
        debugPrint('JioSaavn search error: $e');
      }
    }

    // ----------------------------------------------------------
    // FALLBACK TO YOUTUBE
    // ----------------------------------------------------------

    final youtubeResult = await _fetchYoutubeUrl(
      videoId,
      streamingQuality,
      forDownloading,
    );

    if (youtubeResult['success'] == true) {
      return youtubeResult;
    }

    // Both sources failed.
    return {
      'success': false,
      'source': 'all',
      'errorType': youtubeResult['errorType'] ?? 'unknown',
      'error':
          youtubeResult['error'] ??
          'Unable to find a playable version of this song.',
    };
  } catch (e) {
    debugPrint('Error fetching manifest: $e');

    return {
      'success': false,
      'source': 'unknown',
      'errorType': 'unknown',
      'error': 'Unable to load this song.',
    };
  }
}

class AudioUrlIsolate {
  static final Map<String, Completer<Map<String, dynamic>>> _activeRequests =
      {};

  static Future<Map<String, dynamic>> fetchStreamUrl({
    required String videoId,
    required String streamingQuality,
    required Duration timeout,
    bool allowCancellation = true,
    String? title,
    String? artist,
    bool forDownloading = false,
    bool jioSaavnEnabled = true,
  }) async {
    // ----------------------------------------------------------
    // EXISTING REQUEST
    // ----------------------------------------------------------

    final existingRequest = _activeRequests[videoId];

    if (existingRequest != null) {
      if (!allowCancellation) {
        try {
          return await existingRequest.future;
        } catch (_) {
          // Existing request failed.
        }
      } else {
        if (!existingRequest.isCompleted) {
          existingRequest.complete({
            'success': false,
            'errorType': 'cancelled',
            'error': 'Previous request cancelled.',
          });
        }

        _activeRequests.remove(videoId);
      }
    }

    // ----------------------------------------------------------
    // NEW REQUEST
    // ----------------------------------------------------------

    final completer = Completer<Map<String, dynamic>>();

    _activeRequests[videoId] = completer;

    try {
      final result = await compute(_fetchManifestDirect, {
        'videoId': videoId,
        'streamingQuality': streamingQuality,
        'title': title,
        'artist': artist,
        'forDownloading': forDownloading,
        'jioSaavnEnabled': jioSaavnEnabled,
        'rootIsolateToken': RootIsolateToken.instance,
      }).timeout(timeout);

      if (!completer.isCompleted) {
        completer.complete(result);
      }

      return result;
    } catch (e) {
      debugPrint('Audio URL request failed for $videoId: $e');

      final result = {
        'success': false,
        'errorType': _getErrorType(e),
        'error': _getUserFriendlyError(e),
      };

      if (!completer.isCompleted) {
        completer.complete(result);
      }

      return result;
    } finally {
      if (identical(_activeRequests[videoId], completer)) {
        _activeRequests.remove(videoId);
      }
    }
  }

  static Future<void> cancelRequest(String videoId) async {
    final completer = _activeRequests[videoId];

    if (completer != null && !completer.isCompleted) {
      completer.complete({
        'success': false,
        'errorType': 'cancelled',
        'error': 'Request cancelled.',
      });
    }

    _activeRequests.remove(videoId);
  }

  static Future<void> cancelAllRequests() async {
    for (final videoId in _activeRequests.keys.toList()) {
      final completer = _activeRequests[videoId];

      if (completer != null && !completer.isCompleted) {
        completer.complete({
          'success': false,
          'errorType': 'cancelled',
          'error': 'Request cancelled.',
        });
      }
    }

    _activeRequests.clear();
  }

  static int get activeRequestCount => _activeRequests.length;

  static bool isRequestActive(String videoId) =>
      _activeRequests.containsKey(videoId);
}

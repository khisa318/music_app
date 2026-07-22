import 'dart:async';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song_model.dart';
import '../providers/settings_provider.dart';

class TempAudioCacheService {
  static const String _cacheDirName = 'noize_stream_cache';
  static const Duration _defaultMaxAge = Duration(days: 2);

  Future<Directory> _getCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/$_cacheDirName');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _buildSafeFileName(SongInfo song, String quality, String provider) {
    final sanitizedId = Uri.encodeComponent(song.videoId);
    final sanitizedQuality = Uri.encodeComponent(quality);
    final sanitizedProvider = Uri.encodeComponent(provider);
    return '$sanitizedId-$sanitizedQuality-$sanitizedProvider.mp4';
  }

  Future<String> _getProviderName() async {
    try {
      final settingsProvider = GetIt.I<SettingsProvider>();
      return settingsProvider.jioSaavnEnabled ? 'jiosaavn' : 'youtube';
    } catch (_) {
      return 'youtube';
    }
  }

  Future<File?> getCachedFile(SongInfo song) async {
    try {
      final settingsProvider = GetIt.I<SettingsProvider>();
      final provider = await _getProviderName();
      final fileName = _buildSafeFileName(
        song,
        settingsProvider.streamingQuality,
        provider,
      );
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$fileName');
      if (!await file.exists()) {
        return null;
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<File> downloadAndCacheFile(String url, SongInfo song) async {
    final settingsProvider = GetIt.I<SettingsProvider>();
    final provider = await _getProviderName();
    final fileName = _buildSafeFileName(
      song,
      settingsProvider.streamingQuality,
      provider,
    );
    final cacheDir = await _getCacheDirectory();
    final file = File('${cacheDir.path}/$fileName');
    final tempFile = File('${file.path}.tmp');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download audio cache: ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final output = tempFile.openWrite(mode: FileMode.write);
      await response.pipe(output);
      await output.close();
      if (await file.exists()) {
        await file.delete();
      }
      return tempFile.renameSync(file.path);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> cleanupExpiredCache({Duration maxAge = _defaultMaxAge}) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final now = DateTime.now();
      await for (final entry in cacheDir.list()) {
        if (entry is File) {
          try {
            final stat = await entry.stat();
            if (now.difference(stat.modified) > maxAge) {
              await entry.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      await for (final entry in cacheDir.list()) {
        if (entry is File) {
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

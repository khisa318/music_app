import 'package:flutter/services.dart';

class LocalSongsService {
  static const _channel = MethodChannel('com.anand.noize/local_songs');

  static final LocalSongsService _instance = LocalSongsService._();
  factory LocalSongsService() => _instance;
  LocalSongsService._();

  Future<List<Map<String, dynamic>>> querySongs() async {
    final result = await _channel.invokeMethod<List>('querySongs');
    if (result == null) return [];
    return result.cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<Uint8List?> queryArtwork(int id, {int size = 500}) async {
    final result = await _channel.invokeMethod<Uint8List>('queryArtwork', {
      'id': id,
      'size': size,
    });
    return result;
  }

  Future<void> scanMedia(String path) async {
    await _channel.invokeMethod('scanMedia', {'path': path});
  }
}

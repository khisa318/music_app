import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_app/features/home/data/providers/covers_and_remixes_provider.dart';

const String _boxName = 'covers_and_remixes_cache';
const String _key = 'shelf';

Map<String, dynamic> _song({
  required String id,
  required String title,
  String artist = 'Original Artist',
  int seconds = 210,
}) {
  return {
    'id': id,
    'title': title,
    'artists': [
      {'name': artist, 'id': 'artist-$artist'},
    ],
    'thumbnail': 'https://example.test/$id.jpg',
    'duration': seconds,
  };
}

String _entry({
  required String seedSignature,
  required List<Map<String, dynamic>> songs,
  Duration age = const Duration(minutes: 5),
}) {
  return jsonEncode({
    'cachedAt': DateTime.now().subtract(age).toIso8601String(),
    'seedSignature': seedSignature,
    'songs': songs,
  });
}

List<Map<String, dynamic>> _history(List<String> ids) {
  return [
    for (var index = 0; index < ids.length; index++)
      {'id': ids[index], 'title': 'Seed Track $index', 'duration': 200},
  ];
}

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('covers_remixes_cache');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>(_boxName);
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test('serves the cached shelf on the first frame, before any lookup', () {
    Hive.box<String>(_boxName).put(
      _key,
      _entry(
        seedSignature: 'seedA,seedB',
        songs: [
          _song(id: 'alt1', title: 'Seed Track 0 (Acoustic)'),
          _song(id: 'alt2', title: 'Seed Track 1 (Live)'),
        ],
      ),
    );

    final provider = CoversAndRemixesProvider();

    expect(provider.isFromCache, isTrue);
    expect(provider.isLoading, isFalse);
    expect(provider.results, hasLength(2));
    expect(provider.results.first.videoId, 'alt1');
    expect(provider.results.first.name, 'Seed Track 0 (Acoustic)');
    expect(provider.results.first.artists.first.name, 'Original Artist');
    expect(provider.results.first.thumbnails.first.url, contains('alt1.jpg'));
  });

  test('an empty cached shelf still counts as cached', () {
    Hive.box<String>(_boxName).put(
      _key,
      _entry(seedSignature: 'seedA', songs: []),
    );

    final provider = CoversAndRemixesProvider();

    expect(provider.isFromCache, isTrue);
    expect(provider.results, isEmpty);
  });

  test('a fresh cache for the same seeds skips the lookup entirely', () async {
    Hive.box<String>(_boxName).put(
      _key,
      _entry(
        seedSignature: 'seedA,seedB',
        songs: [_song(id: 'alt1', title: 'Seed Track 0 (Acoustic)')],
      ),
    );

    final provider = CoversAndRemixesProvider();

    // No YTMusic is registered, so a lookup would fail and wipe the shelf. The
    // cache surviving proves the lookup was never attempted.
    await provider.load(_history(['seedA', 'seedB']));

    expect(provider.results, hasLength(1));
    expect(provider.results.first.videoId, 'alt1');
    expect(provider.isFromCache, isTrue);
  });

  test('a fresh cache is discarded once its seeds change', () async {
    Hive.box<String>(_boxName).put(
      _key,
      _entry(
        seedSignature: 'seedA,seedB',
        songs: [_song(id: 'alt1', title: 'Seed Track 0 (Acoustic)')],
      ),
    );

    final provider = CoversAndRemixesProvider();
    await provider.load(_history(['seedC', 'seedD']));

    expect(provider.results, isEmpty);
    expect(provider.isFromCache, isFalse);
  });

  test('a cache older than the TTL is looked up again', () async {
    Hive.box<String>(_boxName).put(
      _key,
      _entry(
        seedSignature: 'seedA,seedB',
        songs: [_song(id: 'alt1', title: 'Seed Track 0 (Acoustic)')],
        age: const Duration(hours: 13),
      ),
    );

    final provider = CoversAndRemixesProvider();

    await provider.load(_history(['seedA', 'seedB']));

    expect(provider.results, isEmpty);
    expect(provider.isFromCache, isFalse);
  });

  test('malformed cache entries are ignored instead of throwing', () {
    Hive.box<String>(_boxName).put(_key, 'not json at all');

    final provider = CoversAndRemixesProvider();

    expect(provider.results, isEmpty);
    expect(provider.isFromCache, isFalse);
  });

  test('a missing cache is a no-op, not a failure', () {
    final provider = CoversAndRemixesProvider();

    expect(provider.results, isEmpty);
    expect(provider.isFromCache, isFalse);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/podcast_models.dart';

/// Metadata source for the Podcasts feature.
///
/// Uses Apple's public iTunes Search/Lookup API for discovery and each show's
/// own RSS feed for full episode lists. No API key or account is required.
/// Responses are cached in Hive so the section still works offline and when
/// iTunes is unreachable.
class PodcastApiService {
  PodcastApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String cacheBoxName = 'podcasts_cache';

  static const Duration _showTtl = Duration(hours: 12);
  static const Duration _episodeTtl = Duration(hours: 2);

  final http.Client _client;
  final Map<String, Future<List<PodcastShow>>> _showRequests = {};
  final Map<String, Future<List<PodcastEpisode>>> _episodeRequests = {};

  Box<String>? get _box =>
      Hive.isBoxOpen(cacheBoxName) ? Hive.box<String>(cacheBoxName) : null;

  Future<List<PodcastShow>> loadFeatured() async {
    // Primary: Kenyan podcasts from Kenya store
    final kenyaShows = await _searchShowsCached(
      'Kenya podcast',
      country: 'ke',
      limit: 25,
    );
    if (kenyaShows.length >= 8) return kenyaShows;

    // Secondary: Nairobi-specific podcasts
    final nairobiShows = await _searchShowsCached(
      'Nairobi podcast',
      country: 'ke',
      limit: 25,
    );
    if (kenyaShows.length + nairobiShows.length >= 8) {
      return _mergeShows([kenyaShows, nairobiShows]);
    }

    // Tertiary: Kenyan-hosted shows (often have "Kenyan" in title)
    final kenyanShows = await _searchShowsCached(
      'Kenyan podcast',
      country: 'ke',
      limit: 25,
    );

    // Quaternary: East Africa region as fallback
    final eastAfricaShows = await _searchShowsCached(
      'East Africa podcast',
      country: 'ke',
      limit: 25,
    );

    return _mergeShows([kenyaShows, nairobiShows, kenyanShows, eastAfricaShows]);
  }

  Future<List<PodcastShow>> loadTrending() async {
    // Primary: Nairobi podcasts (most likely to be trending in Kenya)
    final nairobiShows = await _searchShowsCached(
      'Nairobi podcast',
      country: 'ke',
      limit: 25,
    );

    // Secondary: Kenya-wide trending
    final kenyaShows = await _searchShowsCached(
      'Kenya trending podcast',
      country: 'ke',
      limit: 25,
    );

    // Tertiary: East Africa regional
    final eastAfricaShows = await _searchShowsCached(
      'East Africa podcast',
      country: 'ke',
      limit: 25,
    );

    return _mergeShows([nairobiShows, kenyaShows, eastAfricaShows]);
  }

  Future<List<PodcastShow>> loadRecommended() async {
    // Primary: Kenya-specific podcasts
    final kenyaShows = await _searchShowsCached(
      'Kenya podcast',
      country: 'ke',
      limit: 25,
    );
    if (kenyaShows.length >= 6) return kenyaShows;

    // Secondary: Africa-wide from South Africa store
    final africaShows = await _searchShowsCached(
      'Africa podcast',
      country: 'za',
      limit: 25,
    );

    // Tertiary: Global fallback
    final globalShows = await _searchShowsCached(
      'podcast',
      country: 'us',
      limit: 25,
    );

    return _mergeShows([kenyaShows, africaShows, globalShows]);
  }

  Future<List<PodcastShow>> loadCategory(PodcastCategory category) async {
    final local = await _searchShowsCached(
      '${category.searchQuery} Africa',
      country: 'ke',
      limit: 25,
    );
    if (local.length >= 4) return local;
    final global = await _searchShowsCached(
      category.searchQuery,
      country: 'us',
      limit: 25,
    );
    return _mergeShows([local, global]);
  }

  Future<List<PodcastShow>> searchShows(String term) async {
    final query = term.trim();
    if (query.isEmpty) return const [];

    final local = await _searchShowsCached(query, country: 'ke', limit: 25);
    if (local.length >= 6) return local;
    final global = await _searchShowsCached(query, country: 'us', limit: 25);
    return _mergeShows([local, global]);
  }

  Future<List<PodcastEpisode>> loadEpisodes(PodcastShow show) {
    final existing = _episodeRequests[show.id];
    if (existing != null) return existing;
    final future = _loadEpisodesInner(show);
    _episodeRequests[show.id] = future;
    return future.whenComplete(() => _episodeRequests.remove(show.id));
  }

  Future<List<PodcastEpisode>> _loadEpisodesInner(PodcastShow show) async {
    return _cachedJson<List<PodcastEpisode>>(
      key: 'episodes_${show.id}',
      ttl: _episodeTtl,
      load: () async {
        final feedUrl = show.feedUrl;
        if (feedUrl != null) {
          try {
            final fromFeed = await _loadFeedEpisodes(show, feedUrl);
            if (fromFeed.isNotEmpty) return fromFeed;
          } catch (error) {
            debugPrint('Podcast RSS failed for ${show.title}: $error');
          }
        }
        return _loadItunesEpisodes(show);
      },
      encode: (episodes) => episodes.map((e) => e.toJson()).toList(),
      decode: (payload) => _decodeEpisodeList(payload),
    );
  }

  Future<List<PodcastEpisode>> _loadFeedEpisodes(
    PodcastShow show,
    String feedUrl,
  ) async {
    final uri = Uri.tryParse(feedUrl);
    if (uri == null) throw const FormatException('Invalid feed URL');

    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent': 'MusiX/1.1 (+podcast-discovery)',
            'Accept': 'application/rss+xml, application/xml, text/xml, */*',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('RSS ${response.statusCode}', uri: uri);
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final document = XmlDocument.parse(body);
    final items = document.findAllElements('item');
    final episodes = <PodcastEpisode>[];

    for (final item in items) {
      final episode = _episodeFromRssItem(item, show);
      if (episode != null) episodes.add(episode);
    }

    episodes.sort((a, b) {
      final aDate = a.publishedAt;
      final bDate = b.publishedAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return episodes;
  }

  PodcastEpisode? _episodeFromRssItem(XmlElement item, PodcastShow show) {
    final children = item.children.whereType<XmlElement>().toList();

    String textOf(String localName) {
      for (final child in children) {
        if (child.name.local == localName) {
          return child.innerText.trim();
        }
      }
      return '';
    }

    XmlElement? elementOf(String localName) {
      for (final child in children) {
        if (child.name.local == localName) return child;
      }
      return null;
    }

    final enclosure = elementOf('enclosure');
    final audioUrl = enclosure?.getAttribute('url')?.trim() ?? '';
    final title = textOf('title');
    if (audioUrl.isEmpty || title.isEmpty) return null;

    final guid = textOf('guid');
    final summary =
        _firstNonEmpty([
          textOf('summary'),
          textOf('description'),
          textOf('encoded'),
          textOf('subtitle'),
        ]) ??
        '';

    var imageUrl = show.artworkUrl;
    final imageElement = elementOf('image');
    if (imageElement != null) {
      final href = imageElement.getAttribute('href')?.trim() ?? '';
      if (href.isNotEmpty) {
        imageUrl = href;
      } else {
        for (final child in imageElement.children.whereType<XmlElement>()) {
          if (child.name.local == 'url' && child.innerText.trim().isNotEmpty) {
            imageUrl = child.innerText.trim();
            break;
          }
        }
      }
    }

    final rawDuration = textOf('duration');
    final publishedAt = _parsePubDate(textOf('pubDate'));

    return PodcastEpisode(
      id: podcastEpisodeId(
        showId: show.id,
        title: title,
        guid: guid,
        audioUrl: audioUrl,
      ),
      showId: show.id,
      showTitle: show.title,
      title: cleanPodcastText(title),
      description: cleanPodcastText(summary),
      audioUrl: audioUrl,
      imageUrl: imageUrl,
      duration: _parseDuration(rawDuration),
      publishedAt: publishedAt,
      guid: guid.isEmpty ? null : guid,
      episodeNumber: int.tryParse(textOf('episode')),
      seasonNumber: int.tryParse(textOf('season')),
    );
  }

  Future<List<PodcastEpisode>> _loadItunesEpisodes(PodcastShow show) async {
    final data = await _getJson(
      Uri.https('itunes.apple.com', '/lookup', {
        'id': show.id,
        'entity': 'podcastEpisode',
        'limit': '200',
        if (show.country != null && show.country!.isNotEmpty)
          'country': show.country!,
      }),
    );

    final results = (data['results'] as List?) ?? const [];
    final episodes = <PodcastEpisode>[];

    for (final raw in results) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      if (map['collectionId']?.toString() != show.id) continue;

      final audioUrl =
          (map['episodeUrl'] ?? map['previewUrl'])?.toString().trim() ?? '';
      final title = (map['trackName'] ?? map['collectionName'])?.toString() ?? '';
      if (audioUrl.isEmpty || title.isEmpty) continue;

      final artwork =
          (map['artworkUrl600'] ?? map['artworkUrl160'] ?? show.artworkUrl)
              ?.toString() ??
          show.artworkUrl;
      final durationMs = _asInt(map['trackTimeMillis']);

      episodes.add(
        PodcastEpisode(
          id: podcastEpisodeId(
            showId: show.id,
            title: title,
            guid: map['episodeGuid']?.toString(),
            audioUrl: audioUrl,
          ),
          showId: show.id,
          showTitle: show.title,
          title: cleanPodcastText(title),
          description: cleanPodcastText(
            (map['description'] ?? map['shortDescription'])?.toString(),
          ),
          audioUrl: audioUrl,
          imageUrl: artwork,
          duration: Duration(milliseconds: durationMs),
          publishedAt: DateTime.tryParse(
            map['releaseDate']?.toString() ?? '',
          ),
          guid: map['episodeGuid']?.toString(),
          episodeNumber: _asNullableInt(map['trackNumber']),
          itunesUrl: map['trackViewUrl']?.toString(),
        ),
      );
    }

    episodes.sort((a, b) {
      final aDate = a.publishedAt;
      final bDate = b.publishedAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return episodes;
  }

  Future<List<PodcastShow>> _searchShowsCached(
    String term, {
    required String country,
    required int limit,
  }) {
    final key = 'search_${country}_${term.toLowerCase()}_$limit';
    final existing = _showRequests[key];
    if (existing != null) return existing;

    final future = _cachedJson<List<PodcastShow>>(
      key: key,
      ttl: _showTtl,
      load: () => _searchShows(term, country: country, limit: limit),
      encode: (shows) => shows.map((s) => s.toJson()).toList(),
      decode: (payload) => _decodeShowList(payload),
    );

    _showRequests[key] = future;
    return future.whenComplete(() => _showRequests.remove(key));
  }

  Future<List<PodcastShow>> _searchShows(
    String term, {
    required String country,
    required int limit,
  }) async {
    final data = await _getJson(
      Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'media': 'podcast',
        'entity': 'podcast',
        'limit': '$limit',
        'country': country,
      }),
    );

    final results = (data['results'] as List?) ?? const [];
    final shows = <PodcastShow>[];

    for (final raw in results) {
      if (raw is! Map) continue;
      final show = _showFromItunes(raw.cast<String, dynamic>());
      if (show != null) shows.add(show);
    }

    return shows;
  }

  PodcastShow? _showFromItunes(Map<String, dynamic> map) {
    final id = map['collectionId']?.toString() ?? '';
    final title = (map['collectionName'] ?? map['trackName'])?.toString() ?? '';
    if (id.isEmpty || title.trim().isEmpty) return null;

    final feedUrl = map['feedUrl']?.toString().trim();
    final artwork =
        (map['artworkUrl600'] ??
                map['artworkUrl100'] ??
                map['artworkUrl60'] ??
                '')
            .toString();

    return PodcastShow(
      id: id,
      title: cleanPodcastText(title),
      publisher: cleanPodcastText(map['artistName']?.toString()),
      description: cleanPodcastText(map['description']?.toString()),
      artworkUrl: artwork,
      feedUrl: feedUrl == null || feedUrl.isEmpty ? null : feedUrl,
      genre: map['primaryGenreName']?.toString(),
      country: map['country']?.toString(),
      episodeCount: _asInt(map['trackCount']),
      itunesUrl: map['collectionViewUrl']?.toString(),
      latestEpisodeAt: DateTime.tryParse(
        map['releaseDate']?.toString() ?? '',
      ),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(
              uri,
              headers: const {
                'User-Agent': 'MusiX/1.1 (+podcast-discovery)',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'iTunes request failed (${response.statusCode})',
            uri: uri,
          );
        }

        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
        throw const FormatException('Unexpected iTunes response');
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    }

    throw lastError ?? Exception('iTunes request failed');
  }

  Future<T> _cachedJson<T>({
    required String key,
    required Duration ttl,
    required Future<T> Function() load,
    required Object Function(T value) encode,
    required T Function(dynamic payload) decode,
  }) async {
    final box = _box;
    dynamic cachedPayload;

    if (box != null) {
      try {
        final raw = box.get(key);
        if (raw != null) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            cachedPayload = decoded['payload'];
            final expires = _asInt(decoded['expires']);
            if (expires > DateTime.now().millisecondsSinceEpoch &&
                cachedPayload != null) {
              return decode(cachedPayload);
            }
          }
        }
      } catch (error) {
        debugPrint('Podcast cache read failed for $key: $error');
      }
    }

    try {
      final fresh = await load();
      if (box != null) {
        try {
          await box.put(
            key,
            json.encode({
              'expires': DateTime.now()
                  .add(ttl)
                  .millisecondsSinceEpoch,
              'payload': encode(fresh),
            }),
          );
        } catch (error) {
          debugPrint('Podcast cache write failed for $key: $error');
        }
      }
      return fresh;
    } catch (error) {
      if (cachedPayload != null) {
        try {
          return decode(cachedPayload);
        } catch (_) {
          // Fall through and rethrow the original error.
        }
      }
      rethrow;
    }
  }

  List<PodcastShow> _decodeShowList(dynamic payload) {
    if (payload is! List) return const [];
    return payload
        .whereType<Map>()
        .map((e) => PodcastShow.fromJson(e.cast<String, dynamic>()))
        .where((show) => show.id.isNotEmpty || show.title.isNotEmpty)
        .toList();
  }

  List<PodcastEpisode> _decodeEpisodeList(dynamic payload) {
    if (payload is! List) return const [];
    return payload
        .whereType<Map>()
        .map((e) => PodcastEpisode.fromJson(e.cast<String, dynamic>()))
        .where(
          (episode) =>
              episode.id.isNotEmpty &&
              episode.audioUrl.isNotEmpty &&
              episode.title.isNotEmpty,
        )
        .toList();
  }

  List<PodcastShow> _mergeShows(List<List<PodcastShow>> groups) {
    final seen = <String>{};
    final merged = <PodcastShow>[];
    for (final group in groups) {
      for (final show in group) {
        final key = show.id.isNotEmpty ? show.id : show.title;
        if (seen.add(key)) merged.add(show);
      }
    }
    return merged;
  }

  DateTime? _parsePubDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    try {
      return HttpDate.parse(trimmed);
    } catch (_) {
      return DateTime.tryParse(trimmed);
    }
  }

  Duration _parseDuration(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return Duration.zero;

    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      var hours = 0;
      var minutes = 0;
      var seconds = 0;
      if (parts.length == 3) {
        hours = int.tryParse(parts[0]) ?? 0;
        minutes = int.tryParse(parts[1]) ?? 0;
        seconds = int.tryParse(parts[2]) ?? 0;
      } else if (parts.length == 2) {
        minutes = int.tryParse(parts[0]) ?? 0;
        seconds = int.tryParse(parts[1]) ?? 0;
      }
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }

    final seconds = int.tryParse(trimmed) ?? 0;
    return Duration(seconds: seconds);
  }

  String? _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value;
    }
    return null;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  void dispose() {
    _client.close();
  }
}

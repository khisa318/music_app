import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../../../../core/models/song_model.dart';

enum PodcastCategory {
  comedy('comedy', 'podcast_category_comedy', 'comedy podcast'),
  news('news', 'podcast_category_news', 'news podcast'),
  business('business', 'podcast_category_business', 'business podcast'),
  technology('technology', 'podcast_category_technology', 'technology podcast'),
  sports('sports', 'podcast_category_sports', 'sports podcast'),
  lifestyle('lifestyle', 'podcast_category_lifestyle', 'lifestyle podcast'),
  relationships(
    'relationships',
    'podcast_category_relationships',
    'relationships podcast',
  ),
  trueCrime('true_crime', 'podcast_category_true_crime', 'true crime podcast');

  const PodcastCategory(this.id, this.titleKey, this.searchQuery);

  final String id;
  final String titleKey;
  final String searchQuery;

  static PodcastCategory? fromId(String? id) {
    for (final category in values) {
      if (category.id == id) return category;
    }
    return null;
  }
}

class PodcastShow {
  const PodcastShow({
    required this.id,
    required this.title,
    required this.publisher,
    required this.description,
    required this.artworkUrl,
    this.feedUrl,
    this.genre,
    this.country,
    this.episodeCount = 0,
    this.itunesUrl,
    this.isFeatured = false,
    this.latestEpisodeAt,
  });

  final String id;
  final String title;
  final String publisher;
  final String description;
  final String artworkUrl;
  final String? feedUrl;
  final String? genre;
  final String? country;
  final int episodeCount;
  final String? itunesUrl;
  final bool isFeatured;
  final DateTime? latestEpisodeAt;

  String get displayPublisher =>
      publisher.trim().isEmpty ? 'Podcast' : publisher.trim();

  PodcastShow copyWith({
    String? id,
    String? title,
    String? publisher,
    String? description,
    String? artworkUrl,
    String? feedUrl,
    String? genre,
    String? country,
    int? episodeCount,
    String? itunesUrl,
    bool? isFeatured,
    DateTime? latestEpisodeAt,
  }) {
    return PodcastShow(
      id: id ?? this.id,
      title: title ?? this.title,
      publisher: publisher ?? this.publisher,
      description: description ?? this.description,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      feedUrl: feedUrl ?? this.feedUrl,
      genre: genre ?? this.genre,
      country: country ?? this.country,
      episodeCount: episodeCount ?? this.episodeCount,
      itunesUrl: itunesUrl ?? this.itunesUrl,
      isFeatured: isFeatured ?? this.isFeatured,
      latestEpisodeAt: latestEpisodeAt ?? this.latestEpisodeAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'publisher': publisher,
    'description': description,
    'artworkUrl': artworkUrl,
    'feedUrl': feedUrl,
    'genre': genre,
    'country': country,
    'episodeCount': episodeCount,
    'itunesUrl': itunesUrl,
    'isFeatured': isFeatured,
    'latestEpisodeAt': latestEpisodeAt?.toIso8601String(),
  };

  factory PodcastShow.fromJson(Map<String, dynamic> json) {
    return PodcastShow(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      publisher: json['publisher']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      artworkUrl: json['artworkUrl']?.toString() ?? '',
      feedUrl: _nullIfEmpty(json['feedUrl']?.toString()),
      genre: _nullIfEmpty(json['genre']?.toString()),
      country: _nullIfEmpty(json['country']?.toString()),
      episodeCount: _asInt(json['episodeCount']),
      itunesUrl: _nullIfEmpty(json['itunesUrl']?.toString()),
      isFeatured: json['isFeatured'] == true,
      latestEpisodeAt: DateTime.tryParse(
        json['latestEpisodeAt']?.toString() ?? '',
      ),
    );
  }
}

class PodcastEpisode {
  const PodcastEpisode({
    required this.id,
    required this.showId,
    required this.showTitle,
    required this.title,
    required this.description,
    required this.audioUrl,
    required this.imageUrl,
    required this.duration,
    this.publishedAt,
    this.guid,
    this.episodeNumber,
    this.seasonNumber,
    this.itunesUrl,
  });

  final String id;
  final String showId;
  final String showTitle;
  final String title;
  final String description;
  final String audioUrl;
  final String imageUrl;
  final Duration duration;
  final DateTime? publishedAt;
  final String? guid;
  final int? episodeNumber;
  final int? seasonNumber;
  final String? itunesUrl;

  SongInfo toSongInfo() {
    return SongInfo(
      videoId: id,
      name: title,
      artists: [Artist(name: showTitle, id: showId)],
      thumbnails: [
        Thumbnail(
          url: imageUrl.isEmpty ? '' : imageUrl,
          width: 600,
          height: 600,
        ),
      ],
      duration: duration,
      audioUrl: audioUrl,
      isPodcast: true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'showId': showId,
    'showTitle': showTitle,
    'title': title,
    'description': description,
    'audioUrl': audioUrl,
    'imageUrl': imageUrl,
    'duration': duration.inMilliseconds,
    'publishedAt': publishedAt?.toIso8601String(),
    'guid': guid,
    'episodeNumber': episodeNumber,
    'seasonNumber': seasonNumber,
    'itunesUrl': itunesUrl,
  };

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) {
    final durationMs = _asInt(json['duration']);
    return PodcastEpisode(
      id: json['id']?.toString() ?? '',
      showId: json['showId']?.toString() ?? '',
      showTitle: json['showTitle']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      audioUrl: json['audioUrl']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      duration: Duration(milliseconds: durationMs),
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      guid: _nullIfEmpty(json['guid']?.toString()),
      episodeNumber: _asNullableInt(json['episodeNumber']),
      seasonNumber: _asNullableInt(json['seasonNumber']),
      itunesUrl: _nullIfEmpty(json['itunesUrl']?.toString()),
    );
  }
}

class PodcastProgress {
  const PodcastProgress({
    required this.episodeId,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String episodeId;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get fraction {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get isFinished =>
      duration > Duration.zero &&
      position >= duration - const Duration(seconds: 20);

  bool get isInProgress =>
      position > const Duration(seconds: 10) && !isFinished;

  Map<String, dynamic> toJson() => {
    'episodeId': episodeId,
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PodcastProgress.fromJson(Map<String, dynamic> json) {
    return PodcastProgress(
      episodeId: json['episodeId']?.toString() ?? '',
      position: Duration(milliseconds: _asInt(json['position'])),
      duration: Duration(milliseconds: _asInt(json['duration'])),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String podcastEpisodeId({
  required String showId,
  required String title,
  String? guid,
  String? audioUrl,
}) {
  final source = [
    showId,
    guid?.trim().isNotEmpty == true ? guid!.trim() : title.trim(),
    audioUrl?.trim() ?? '',
  ].join('|');
  final digest = sha1.convert(utf8.encode(source)).toString();
  return 'pod_${digest.substring(0, 24)}';
}

String _cleanText(String? value) {
  if (value == null) return '';
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String cleanPodcastText(String? value) => _cleanText(value);
String? _nullIfEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
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

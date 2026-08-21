import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/duration_utils.dart';

// ============================================================
// CONFIG
// ============================================================

const String domain = 'https://music.youtube.com/';
const String baseUrl = '${domain}youtubei/v1/';

const String fixedParams =
    '?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

const String userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/114.0.0.0 Safari/537.36';

// ============================================================
// HEADERS
// ============================================================

final Map<String, String> headers = {
  'user-agent': userAgent,
  'accept': '*/*',
  'accept-encoding': 'gzip, deflate',
  'content-type': 'application/json',
  'origin': domain,
  'cookie': 'CONSENT=YES+1',
};

// ============================================================
// YOUTUBE MUSIC CONTEXT
// ============================================================

final Map<String, dynamic> apiContext = {
  'context': {
    'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20230213.01.00'},
    'user': {},
  },
};

// ============================================================
// DIO
// ============================================================

final Dio _dio = Dio(
  BaseOptions(
    headers: headers,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 15),
  ),
);

// ============================================================
// REQUEST
// ============================================================

Future<Response> sendRequest(
  String action,
  Map<dynamic, dynamic> data, {
  String additionalParams = '',
}) async {
  try {
    final response = await _dio.post(
      '$baseUrl$action$fixedParams$additionalParams',
      data: data,
    );

    if (response.statusCode == 200) {
      return response;
    }

    throw Exception('YouTube Music request failed: ${response.statusCode}');
  } on DioException catch (e) {
    debugPrint('YouTube Music Dio error [$action]: ${e.message}');

    throw Exception('Network error: ${e.message}');
  }
}

// ============================================================
// GET SONG
// ============================================================

Future<Map<String, dynamic>> getSongWithId(String songId) async {
  final data = Map<String, dynamic>.from(apiContext);

  data['videoId'] = songId;

  final response = (await sendRequest('player', data)).data;

  if (response is! Map<String, dynamic>) {
    throw Exception('Invalid player response');
  }

  final category = nav(response, [
    'microformat',
    'microformatDataRenderer',
    'category',
  ]);

  final videoDetails = response['videoDetails'];

  if (videoDetails is Map &&
      (category == 'Music' || videoDetails.containsKey('musicVideoType'))) {
    final metadata = parseSongMetadata(response);

    final streamingUrls = parseStreamingUrls(response);

    return {'metadata': metadata, 'streamingUrls': streamingUrls};
  }

  throw Exception('Not a music video');
}

// ============================================================
// RADIO / RELATED SONGS
// ============================================================

Future<Map<String, dynamic>> getRadioSongs(
  String videoId, {
  int limit = 25,
}) async {
  if (videoId.isEmpty) {
    throw Exception('Video ID is empty');
  }

  if (videoId.startsWith('MPED')) {
    videoId = videoId.substring(4);
  }

  debugPrint('================================================');

  debugPrint('getRadioSongs START: $videoId');

  final data = Map<String, dynamic>.from(apiContext);

  data['enablePersistentPlaylistPanel'] = true;
  data['isAudioOnly'] = true;
  data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
  data['videoId'] = videoId;
  data['playlistId'] = 'RDAMVM$videoId';
  data['params'] = 'wAEB';

  final List<dynamic> tracks = [];

  String? lyricsBrowseId;
  String? relatedBrowseId;
  String? playlist;
  String? additionalParamsForNext;

  try {
    final response = (await sendRequest('next', data)).data;

    debugPrint('YTMusic next -> 200');

    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid next response');
    }

    debugPrint('getRadioSongs: received next response');

    final watchNextRenderer = nav(response, [
      'contents',
      'singleColumnMusicWatchNextResultsRenderer',
      'tabbedRenderer',
      'watchNextTabbedResultsRenderer',
    ]);

    if (watchNextRenderer is! Map<String, dynamic>) {
      throw Exception('watchNextRenderer not found');
    }

    debugPrint('getRadioSongs: watchNextRenderer found');

    lyricsBrowseId = getTabBrowseId(watchNextRenderer, 1);

    relatedBrowseId = getTabBrowseId(watchNextRenderer, 2);

    debugPrint('lyrics browseId: $lyricsBrowseId');

    debugPrint('related browseId: $relatedBrowseId');

    final dynamic panel = nav(watchNextRenderer, [
      ...tabContent,
      'musicQueueRenderer',
      'content',
      'playlistPanelRenderer',
    ]);

    if (panel is Map<String, dynamic>) {
      debugPrint('getRadioSongs: playlistPanelRenderer found');

      final contents = panel['contents'];

      if (contents is List) {
        debugPrint(
          'playlist panel contains '
          '${contents.length} items',
        );

        final playlistIds = contents
            .map(
              (content) => nav(content, [
                'playlistPanelVideoRenderer',
                ...navigationPlaylistId,
              ]),
            )
            .where((value) => value != null)
            .toList();

        if (playlistIds.isNotEmpty) {
          playlist = playlistIds.first.toString();
        }

        debugPrint('playlist ID: $playlist');

        tracks.addAll(parseWatchPlaylist(contents));

        debugPrint('parsed ${tracks.length} radio tracks');
      }
    } else {
      debugPrint('getRadioSongs: playlistPanelRenderer NOT found');
    }

    // ----------------------------------------------------------
    // Continuations
    // ----------------------------------------------------------

    if (tracks.length < limit) {
      final panel = nav(watchNextRenderer, [
        ...tabContent,
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer',
      ]);

      if (panel is Map<String, dynamic> && panel['continuations'] != null) {
        Future<dynamic> requestFunc(String additionalParams) async {
          return (await sendRequest(
            'next',
            data,
            additionalParams: additionalParams,
          )).data;
        }

        List<dynamic> parseFunc(dynamic contents) {
          if (contents is! List) {
            return [];
          }

          return parseWatchPlaylist(contents);
        }

        final continuationResults = await getContinuations(
          panel,
          'playlistPanelContinuation',
          limit - tracks.length,
          requestFunc,
          parseFunc,
          ctokenPath: 'Radio',
          isAdditionparamReturnReq: true,
        );

        final continuationItems = continuationResults[0];

        additionalParamsForNext = continuationResults[1];

        if (continuationItems is List) {
          tracks.addAll(continuationItems);
        }
      }
    }

    // ----------------------------------------------------------
    // Limit
    // ----------------------------------------------------------

    final limitedTracks = tracks.take(limit).toList();

    debugPrint(
      'getRadioSongs END: '
      '${limitedTracks.length} tracks found '
      'for $videoId',
    );

    for (int i = 0; i < limitedTracks.length && i < 5; i++) {
      final track = limitedTracks[i];

      debugPrint(
        'Radio[$i]: '
        '${track['title']} '
        '(${track['videoId']})',
      );
    }

    return {
      'tracks': limitedTracks,
      'playlistId': playlist,
      'lyrics': lyricsBrowseId,
      'related': relatedBrowseId,
      'additionalParamsForNext': additionalParamsForNext,
      'totalTracks': limitedTracks.length,
      'radioId': 'RDAMVM$videoId',
    };
  } catch (e, stack) {
    debugPrint('getRadioSongs FAILED for $videoId: $e');

    debugPrintStack(stackTrace: stack);

    throw Exception('Failed to get radio songs: $e');
  }
}

// ============================================================
// SAFE TAB BROWSE ID
// ============================================================

String? getTabBrowseId(Map<String, dynamic> watchNextRenderer, int tabId) {
  try {
    final tabs = watchNextRenderer['tabs'];

    if (tabs is! List) {
      return null;
    }

    if (tabId < 0 || tabId >= tabs.length) {
      return null;
    }

    final tab = tabs[tabId];

    if (tab is! Map) {
      return null;
    }

    final tabRenderer = tab['tabRenderer'];

    if (tabRenderer is! Map) {
      return null;
    }

    if (tabRenderer['unselectable'] == true) {
      return null;
    }

    final endpoint = tabRenderer['endpoint'];

    if (endpoint is! Map) {
      debugPrint(
        'getTabBrowseId: tab '
        '$tabId has no endpoint',
      );

      return null;
    }

    final browseEndpoint = endpoint['browseEndpoint'];

    if (browseEndpoint is! Map) {
      debugPrint(
        'getTabBrowseId: tab '
        '$tabId has no browseEndpoint',
      );

      return null;
    }

    final browseId = browseEndpoint['browseId'];

    if (browseId is String && browseId.isNotEmpty) {
      return browseId;
    }

    return null;
  } catch (e) {
    debugPrint('getTabBrowseId($tabId) failed: $e');

    return null;
  }
}

// ============================================================
// PARSE WATCH PLAYLIST
// ============================================================

List<dynamic> parseWatchPlaylist(List<dynamic> results) {
  final tracks = <dynamic>[];

  const ppvwr = 'playlistPanelVideoWrapperRenderer';

  const ppvr = 'playlistPanelVideoRenderer';

  for (final rawResult in results) {
    try {
      dynamic result = rawResult;

      Map<String, dynamic>? counterpart;

      if (result is! Map) {
        continue;
      }

      if (result.containsKey(ppvwr)) {
        final wrapper = result[ppvwr];

        if (wrapper is Map) {
          final counterpartList = wrapper['counterpart'];

          if (counterpartList is List && counterpartList.isNotEmpty) {
            final counterpartData = counterpartList[0];

            if (counterpartData is Map) {
              final renderer = counterpartData['counterpartRenderer'];

              if (renderer is Map) {
                final parsed = renderer[ppvr];

                if (parsed is Map<String, dynamic>) {
                  counterpart = parsed;
                }
              }
            }
          }

          result = wrapper['primaryRenderer'];
        }
      }

      if (result is! Map) {
        continue;
      }

      if (!result.containsKey(ppvr)) {
        continue;
      }

      final data = result[ppvr];

      if (data is! Map<String, dynamic>) {
        continue;
      }

      if (data.containsKey('unplayableText')) {
        continue;
      }

      final videoId = data['videoId'];

      if (videoId is! String || videoId.isEmpty) {
        continue;
      }

      final track = parseWatchTrack(data);

      if (counterpart != null) {
        track['counterpart'] = parseWatchTrack(counterpart);
      }

      tracks.add(track);
    } catch (e) {
      debugPrint('parseWatchPlaylist item failed: $e');
    }
  }

  return tracks;
}

// ============================================================
// PARSE WATCH TRACK
// ============================================================

Map<String, dynamic> parseWatchTrack(Map<String, dynamic> data) {
  final runs = nav(data, ['longBylineText', 'runs']);

  final songInfo = runs is List
      ? parseSongRuns(runs)
      : <String, dynamic>{'artists': []};

  final track = <String, dynamic>{
    'videoId': data['videoId'],

    'title': nav(data, titleText),

    'length': nav(data, ['lengthText', 'runs', 0, 'text']),

    'thumbnails': nav(data, thumbnail),

    'videoType': nav(data, ['navigationEndpoint', ...navigationVideoType]),
  };

  track.addAll(songInfo);

  if (track['length'] != null) {
    try {
      track['duration_seconds'] = DurationUtils.parseDuration(
        track['length'],
      ).inSeconds;
    } catch (_) {}
  }

  return track;
}

// ============================================================
// CONTINUATIONS
// ============================================================

Future<List> getContinuations(
  Map<String, dynamic> results,
  String continuationType,
  int? limit,
  Function requestFunc,
  Function parseFunc, {
  String ctokenPath = '',
  bool isAdditionparamReturnReq = false,
  String? additionalParams_,
}) async {
  final items = <dynamic>[];

  String? continuationToken;

  if (additionalParams_ != null) {
    final params = <String, String>{};

    for (final param in additionalParams_.split('&')) {
      final parts = param.split('=');

      if (parts.length == 2) {
        params[parts[0]] = parts[1];
      }
    }

    continuationToken = params['continuation'];
  } else {
    continuationToken = nav(results, [
      'continuations',
      0,
      'nextContinuationData',
      'continuation',
    ]);
  }

  String? additionalParamsForNext;

  while (continuationToken != null && (limit == null || items.length < limit)) {
    try {
      final additionalParams =
          '&ctoken=$continuationToken'
          '&continuation=$continuationToken';

      final response = await requestFunc(additionalParams);

      final continuationItems = nav(response, [
        'onResponseReceivedActions',
        0,
        'appendContinuationItemsAction',
        'continuationItems',
      ]);

      if (continuationItems is! List || continuationItems.isEmpty) {
        break;
      }

      final contents = parseFunc(continuationItems);

      if (contents is! List || contents.isEmpty) {
        break;
      }

      items.addAll(contents);

      continuationToken = nav(continuationItems.last, [
        'continuationItemRenderer',
        'continuationEndpoint',
        'continuationCommand',
        'token',
      ]);

      if (isAdditionparamReturnReq && continuationToken != null) {
        additionalParamsForNext =
            '&ctoken=$continuationToken'
            '&continuation=$continuationToken';
      }
    } catch (e) {
      debugPrint('Continuation failed: $e');

      break;
    }
  }

  if (isAdditionparamReturnReq) {
    return [items, additionalParamsForNext];
  }

  return items;
}

// ============================================================
// SONG METADATA
// ============================================================

Map<String, dynamic> parseSongMetadata(Map<String, dynamic> response) {
  final videoDetails = response['videoDetails'];

  return {
    'title': videoDetails['title'],
    'artist': videoDetails['author'],
    'duration': videoDetails['lengthSeconds'],
    'videoId': videoDetails['videoId'],
  };
}

// ============================================================
// STREAMING URLS
// ============================================================

List<Map<String, dynamic>> parseStreamingUrls(Map<String, dynamic> response) {
  final streamingData = response['streamingData'];

  if (streamingData is! Map) {
    return [];
  }

  final formats = streamingData['formats'];

  if (formats is! List) {
    return [];
  }

  return formats.whereType<Map>().map((format) {
    final mime = format['mimeType']?.toString();

    return {
      'url': format['url'],
      'quality': format['qualityLabel'] ?? format['quality'],
      'format': mime?.split(';')[0] ?? 'unknown',
      'bitrate': format['bitrate'],
    };
  }).toList();
}

// ============================================================
// PLAYLIST / ALBUM
// ============================================================

Future<Map<String, dynamic>> getPlaylistAlbumSongs({
  String? playlistId,
  String? albumId,
  int limit = 3000,
  bool related = false,
  int suggestionsLimit = 0,
}) async {
  String browseId;

  if (playlistId != null) {
    browseId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
  } else if (albumId != null) {
    browseId = albumId;

    if (albumId.startsWith('OLAK5uy')) {
      browseId = await getAlbumBrowseId(albumId);
    }
  } else {
    throw Exception('Must provide either playlistId or albumId');
  }

  final data = Map<String, dynamic>.from(apiContext);

  data['browseId'] = browseId;

  final response = (await sendRequest('browse', data)).data;

  Map<String, dynamic> item;

  if (playlistId != null) {
    final header =
        nav(response, ['header', 'musicDetailHeaderRenderer']) ??
        nav(response, [
          'contents',
          'twoColumnBrowseResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
          0,
          'musicResponsiveHeaderRenderer',
        ]);

    final results =
        nav(response, musicPlaylistShelfRenderer) ??
        nav(response, [
          'contents',
          'singleColumnBrowseResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
          0,
          'musicPlaylistShelfRenderer',
        ]);

    if (header is! Map<String, dynamic> || results is! Map<String, dynamic>) {
      throw Exception('Playlist response format changed');
    }

    item = {
      'id': results['playlistId'],
      'title': nav(header, titleText),
      'thumbnails':
          nav(header, thumnailCropped) ??
          nav(header, [
            'thumbnail',
            'musicThumbnailRenderer',
            'thumbnail',
            'thumbnails',
          ]),
      'description': nav(header, descriptionPath),
    };

    final subtitle = header['subtitle'];

    if (subtitle is Map) {
      final runs = subtitle['runs'];

      if (runs is List && runs.length > 1) {
        item['author'] = {
          'name': nav(header, subtitle2),
          'id': nav(header, ['subtitle', 'runs', 2, ...navigationBrowseId]),
        };

        if (runs.length == 5) {
          item['year'] = nav(header, subtitle3);
        }
      }
    }

    final secondSubtitle = header['secondSubtitle'];

    int songCount = 0;

    if (secondSubtitle is Map) {
      final runs = secondSubtitle['runs'];

      if (runs is List && runs.isNotEmpty) {
        for (final run in runs) {
          final text = run['text']?.toString();

          if (text == null) {
            continue;
          }

          final match = RegExp(r'^\d[\d,]*$').firstMatch(text);

          if (match != null) {
            songCount = int.tryParse(text.replaceAll(',', '')) ?? 0;

            break;
          }
        }
      }
    }

    item['trackCount'] = songCount;

    final contents = results['contents'];

    item['tracks'] = contents is List ? parsePlaylistItems(contents) : [];

    if (contents is List && songCount > 0) {
      Future<dynamic> requestFunc(dynamic additionalParams) async {
        return (await sendRequest('browse', {
          ...data,
          ...additionalParams,
        })).data;
      }

      List<dynamic> parseFunc(dynamic contents) {
        if (contents is! List) {
          return [];
        }

        return parsePlaylistItems(contents);
      }

      final currentTracks = item['tracks'] as List;

      final extra = await getContinuationsPlaylist(
        results,
        limit - currentTracks.length,
        requestFunc,
        parseFunc,
      );

      item['tracks'] = [...currentTracks, ...extra];
    }
  } else {
    item = parseAlbumHeader(response);

    final results =
        nav(response, [
          'contents',
          'twoColumnBrowseResultsRenderer',
          'secondaryContents',
          'sectionListRenderer',
          'contents',
          0,
          'musicShelfRenderer',
        ]) ??
        nav(response, [
          'contents',
          'singleColumnBrowseResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
          0,
          'musicShelfRenderer',
        ]);

    if (results is Map<String, dynamic>) {
      final contents = results['contents'];

      item['tracks'] = contents is List
          ? parsePlaylistItems(
              contents,
              artistsM: item['artists'],
              thumbnailsM: item['thumbnails'],
              albumIdName: {'id': albumId, 'name': item['title']},
              albumYear: item['year'],
              isAlbum: true,
            )
          : [];
    } else {
      item['tracks'] = [];
    }
  }

  return {'playlist': item, 'songs': item['tracks'] ?? []};
}

// ============================================================
// PLAYLIST ITEMS
// ============================================================

List<dynamic> parsePlaylistItems(
  List<dynamic> results, {
  List<List<dynamic>>? menuEntries,
  dynamic thumbnailsM,
  dynamic artistsM,
  String? albumYear,
  dynamic albumIdName,
  bool isAlbum = false,
}) {
  final songs = <dynamic>[];

  for (final result in results) {
    try {
      if (result is! Map) {
        continue;
      }

      if (!result.containsKey('musicResponsiveListItemRenderer')) {
        continue;
      }

      final data = result['musicResponsiveListItemRenderer'];

      if (data is! Map<String, dynamic>) {
        continue;
      }

      String? videoId = nav(data, ['playlistItemData', 'videoId']);

      if (videoId == null && isAlbum) {
        final creditId = nav(data, [
          'menu',
          'menuRenderer',
          'items',
          5,
          'menuNavigationItemRenderer',
          'navigationEndpoint',
          'browseEndpoint',
          'browseId',
        ]);

        if (creditId is String && creditId.contains('MPTC')) {
          videoId = creditId.split('MPTC')[1];
        }
      }

      if (videoId == null && data.containsKey('menu')) {
        final menu = nav(data, menuItems);

        if (menu is List) {
          for (final menuItem in menu) {
            if (menuItem is! Map) {
              continue;
            }

            if (menuItem.containsKey('menuServiceItemRenderer')) {
              final service = nav(menuItem, menuService);

              if (service is Map &&
                  service.containsKey('playlistEditEndpoint')) {
                videoId =
                    service['playlistEditEndpoint']?['actions']?[0]?['removedVideoId'];
              }
            }
          }
        }
      }

      if (videoId == null && nav(data, playButton) != null) {
        final play = nav(data, playButton);

        if (play is Map && play.containsKey('playNavigationEndpoint')) {
          videoId = nav(play, [
            'playNavigationEndpoint',
            'watchEndpoint',
            'videoId',
          ]);
        }
      }

      final title = getItemText(data, 0);

      if (title == 'Song deleted') {
        continue;
      }

      final artists = parseSongArtists(data, 1);

      final album = isAlbum ? albumIdName : parseSongAlbum(data, 2);

      dynamic duration;

      final fixedColumns = data['fixedColumns'];

      if (fixedColumns is List && fixedColumns.isNotEmpty) {
        final fixed = getFixedColumnItem(data, 0);

        if (fixed != null) {
          final text = fixed['text'];

          if (text is Map) {
            if (text.containsKey('simpleText')) {
              duration = text['simpleText'];
            } else if (text.containsKey('runs')) {
              duration = nav(text, ['runs', 0, 'text']);
            }
          }
        }
      }

      dynamic thumbnails_;

      if (data.containsKey('thumbnail')) {
        thumbnails_ = nav(data, thumbnailsPath);
      }

      bool isAvailable = true;

      if (data.containsKey('musicItemRendererDisplayPolicy')) {
        isAvailable =
            data['musicItemRendererDisplayPolicy'] !=
            'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT';
      }

      String? trackDetails;

      if (isAlbum) {
        final indexText = nav(data, ['index', 'runs', 0, 'text']);

        if (indexText != null) {
          trackDetails = '$indexText/${results.length}';
        }
      }

      final song = <String, dynamic>{
        'videoId': videoId,
        'title': title,
        'album': album,
        'artists': artists ?? artistsM,
        'thumbnails': isAlbum ? thumbnailsM : thumbnails_ ?? thumbnailsM,
        'isAvailable': isAvailable,
        'trackDetails': trackDetails,
      };

      if (duration != null) {
        song['length'] = duration;

        try {
          song['duration_seconds'] = DurationUtils.parseDuration(
            duration,
          ).inSeconds;
        } catch (_) {}
      }

      if (menuEntries != null) {
        for (final menuEntry in menuEntries) {
          song[menuEntry.last] = nav(
            data,
            menuItems + menuEntry.whereType<String>().toList(),
          );
        }
      }

      if (videoId != null && videoId.isNotEmpty && isAvailable) {
        songs.add(song);
      }
    } catch (e) {
      debugPrint('parsePlaylistItems item failed: $e');
    }
  }

  return songs;
}

// ============================================================
// ARTISTS
// ============================================================

List<dynamic>? parseSongArtists(Map<String, dynamic> data, int index) {
  final flexItem = getFlexColumnItem(data, index);

  if (flexItem.isEmpty) {
    return null;
  }

  final runs = nav(flexItem, ['text', 'runs']);

  if (runs is! List) {
    return null;
  }

  return parseSongArtistsRuns(runs);
}

List<Map<String, dynamic>> parseSongArtistsRuns(List<dynamic> runs) {
  final artists = <Map<String, dynamic>>[];

  for (int i = 0; i < runs.length; i += 2) {
    final run = runs[i];

    if (run is! Map) {
      continue;
    }

    final name = run['text']?.toString();

    if (name == null || name.isEmpty) {
      continue;
    }

    artists.add({
      'name': name,
      'id': nav(run, navigationBrowseId, noneIfAbsent: false),
    });
  }

  return artists;
}

// ============================================================
// ALBUM
// ============================================================

Map<String, dynamic>? parseSongAlbum(Map<String, dynamic> data, int index) {
  final flexItem = getFlexColumnItem(data, index);

  if (flexItem.isEmpty) {
    return null;
  }

  return {'name': getItemText(data, index), 'id': getBrowseId(flexItem, 0)};
}

String? getBrowseId(Map<String, dynamic> item, int index) {
  try {
    final run = item['text']['runs'][index];

    if (run is Map && run.containsKey('navigationEndpoint')) {
      return nav(run, navigationBrowseId);
    }
  } catch (_) {}

  return null;
}

// ============================================================
// FIXED COLUMN
// ============================================================

Map<String, dynamic>? getFixedColumnItem(Map<String, dynamic> item, int index) {
  try {
    final fixed = item['fixedColumns'];

    if (fixed is! List || index >= fixed.length) {
      return null;
    }

    final renderer = fixed[index]['musicResponsiveListItemFixedColumnRenderer'];

    if (renderer is! Map<String, dynamic>) {
      return null;
    }

    return renderer;
  } catch (_) {
    return null;
  }
}

// ============================================================
// TEXT
// ============================================================

String? getItemText(
  Map<String, dynamic> item,
  int index, {
  int runIndex = 0,
  bool noneIfAbsent = false,
}) {
  try {
    final column = getFlexColumnItem(item, index);

    if (column.isEmpty) {
      return noneIfAbsent ? null : '';
    }

    final runs = nav(column, ['text', 'runs']);

    if (runs is! List || runIndex >= runs.length) {
      return noneIfAbsent ? null : '';
    }

    return runs[runIndex]['text']?.toString();
  } catch (_) {
    return noneIfAbsent ? null : '';
  }
}

// ============================================================
// FLEX COLUMN
// ============================================================

Map<String, dynamic> getFlexColumnItem(Map<String, dynamic> item, int index) {
  try {
    final columns = item['flexColumns'];

    if (columns is! List || index >= columns.length) {
      return {};
    }

    final renderer =
        columns[index]['musicResponsiveListItemFlexColumnRenderer'];

    if (renderer is! Map<String, dynamic>) {
      return {};
    }

    final text = renderer['text'];

    if (text is! Map || text['runs'] is! List) {
      return {};
    }

    return renderer;
  } catch (_) {
    return {};
  }
}

// ============================================================
// SONG RUNS
// ============================================================

Map<String, dynamic> parseSongRuns(List<dynamic> runs) {
  final parsed = <String, dynamic>{'artists': <dynamic>[]};

  for (int i = 0; i < runs.length; i++) {
    final run = runs[i];

    if (run is! Map) {
      continue;
    }

    // Separators
    if (i % 2 != 0) {
      continue;
    }

    final text = run['text']?.toString();

    if (text == null) {
      continue;
    }

    if (run.containsKey('navigationEndpoint')) {
      final id = nav(run, navigationBrowseId, noneIfAbsent: true);

      final item = <String, dynamic>{'name': text, 'id': id};

      if (id is String &&
          (id.startsWith('MPRE') || id.contains('release_detail'))) {
        parsed['album'] = item;
      } else {
        parsed['artists'].add(item);
      }

      continue;
    }

    if (RegExp(r'^\d([^ ])* [^ ]*$').hasMatch(text) && i > 0) {
      parsed['views'] = text.split(' ')[0];
    } else if (RegExp(r'^(\d+:)*\d+:\d+$').hasMatch(text)) {
      parsed['length'] = text;

      try {
        parsed['duration_seconds'] = DurationUtils.parseDuration(
          text,
        ).inSeconds;
      } catch (_) {}
    } else if (RegExp(r'^\d{4}$').hasMatch(text)) {
      parsed['year'] = text;
    } else {
      parsed['artists'].add({'name': text, 'id': null});
    }
  }

  return parsed;
}

// ============================================================
// ALBUM HEADER
// ============================================================

Map<String, dynamic> parseAlbumHeader(Map<String, dynamic> response) {
  final header =
      nav(response, [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
        0,
        'musicResponsiveHeaderRenderer',
      ]) ??
      nav(response, ['header', 'musicDetailHeaderRenderer']);

  if (header is! Map<String, dynamic>) {
    throw Exception('Album header not found');
  }

  final album = <String, dynamic>{
    'title': nav(header, titleText),
    'type': nav(header, subtitle),
    'thumbnails':
        nav(header, thumnailCropped) ??
        nav(header, [
          'thumbnail',
          'musicThumbnailRenderer',
          'thumbnail',
          'thumbnails',
        ]),
  };

  album['description'] =
      nav(header, [
        'description',
        'musicDescriptionShelfRenderer',
        'description',
        'runs',
        0,
        'text',
      ]) ??
      '';

  final subtitleRuns = nav(header, ['subtitle', 'runs']);

  if (subtitleRuns is List) {
    final albumInfo = parseSongRuns(
      subtitleRuns.length > 2 ? subtitleRuns.sublist(2) : subtitleRuns,
    );

    album.addAll(albumInfo);
  }

  final secondSubtitleRuns = nav(header, ['secondSubtitle', 'runs']);

  if (secondSubtitleRuns is List && secondSubtitleRuns.isNotEmpty) {
    album['duration'] = secondSubtitleRuns.last['text'];
  }

  final canonicalUrl = nav(response, [
    'microformat',
    'microformatDataRenderer',
    'urlCanonical',
  ]);

  if (canonicalUrl is String && canonicalUrl.contains('list=')) {
    album['audioPlaylistId'] = canonicalUrl.split('list=').last;
  }

  return album;
}

// ============================================================
// PLAYLIST CONTINUATION
// ============================================================

Future<List> getContinuationsPlaylist(
  Map<String, dynamic> results,
  int? limit,
  Function requestFunc,
  Function parseFunc,
) async {
  final items = <dynamic>[];

  final contents = results['contents'];

  if (contents is! List || contents.isEmpty) {
    return items;
  }

  String? continuationToken;

  for (int i = contents.length - 1; i >= 0; i--) {
    final token = nav(contents[i], [
      'continuationItemRenderer',
      'continuationEndpoint',
      'continuationCommand',
      'token',
    ]);

    if (token != null) {
      continuationToken = token;
      break;
    }
  }

  while (continuationToken != null && (limit == null || items.length < limit)) {
    try {
      final response = await requestFunc({'continuation': continuationToken});

      final continuationItems = nav(response, [
        'onResponseReceivedActions',
        0,
        'appendContinuationItemsAction',
        'continuationItems',
      ]);

      if (continuationItems is! List || continuationItems.isEmpty) {
        break;
      }

      final parsed = parseFunc(continuationItems);

      if (parsed is List && parsed.isNotEmpty) {
        items.addAll(parsed);
      }

      continuationToken = nav(continuationItems.last, [
        'continuationItemRenderer',
        'continuationEndpoint',
        'continuationCommand',
        'token',
      ]);
    } catch (e) {
      debugPrint('Playlist continuation failed: $e');
      break;
    }
  }

  return items;
}

// ============================================================
// ALBUM BROWSE ID
// ============================================================

Future<String> getAlbumBrowseId(String audioPlaylistId) async {
  try {
    final response = await _dio.get(
      '${domain}playlist',
      queryParameters: {'list': audioPlaylistId},
    );

    final reg = RegExp(r'\"MPRE.+?\"');

    final match = reg.firstMatch(response.data.toString());

    if (match != null) {
      final value = match[0]!;

      return value.substring(1).split('\\')[0];
    }
  } catch (e) {
    debugPrint('getAlbumBrowseId failed: $e');
  }

  return audioPlaylistId;
}

// ============================================================
// NAVIGATION HELPER
// ============================================================

dynamic nav(
  dynamic root,
  List items, {
  bool noneIfAbsent = false,
  String funName = 'd',
}) {
  try {
    dynamic result = root;

    for (final item in items) {
      if (result == null) {
        return null;
      }

      if (result is Map) {
        result = result[item];
      } else if (result is List) {
        if (item is! int || item < 0 || item >= result.length) {
          return null;
        }

        result = result[item];
      } else {
        return null;
      }
    }

    return result;
  } catch (e) {
    if (!noneIfAbsent) {
      debugPrint('nav failed [$funName]: $e');
    }

    return null;
  }
}

// ============================================================
// CONSTANTS
// ============================================================

const titleText = ['title', 'runs', 0, 'text'];

const subtitle2 = ['subtitle', 'runs', 2, 'text'];

const subtitle3 = ['subtitle', 'runs', 4, 'text'];

const descriptionPath = ['description', 'runs', 0, 'text'];

const thumnailCropped = [
  'thumbnail',
  'croppedSquareThumbnailRenderer',
  'thumbnail',
  'thumbnails',
];

const navigationBrowseId = ['navigationEndpoint', 'browseEndpoint', 'browseId'];

const navigationPlaylistId = [
  'navigationEndpoint',
  'watchEndpoint',
  'playlistId',
];

const navigationVideoType = [
  'watchEndpoint',
  'watchEndpointMusicSupportedConfigs',
  'watchEndpointMusicConfig',
  'musicVideoType',
];

const musicPlaylistShelfRenderer = [
  'contents',
  'twoColumnBrowseResultsRenderer',
  'secondaryContents',
  'sectionListRenderer',
  'contents',
  0,
  'musicPlaylistShelfRenderer',
];

const menuItems = ['menu', 'menuRenderer', 'items'];

const menuService = ['menuServiceItemRenderer', 'serviceEndpoint'];

const playButton = [
  'overlay',
  'musicItemThumbnailOverlayRenderer',
  'content',
  'musicPlayButtonRenderer',
];

const tabContent = ['tabs', 0, 'tabRenderer', 'content'];

const thumbnailsPath = [
  'thumbnail',
  'musicThumbnailRenderer',
  'thumbnail',
  'thumbnails',
];

const thumbnail = ['thumbnail', 'thumbnails'];

const subtitle = ['subtitle', 'runs', 0, 'text'];

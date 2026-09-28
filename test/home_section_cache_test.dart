import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/models/song_model.dart';
import 'package:music_app/features/home/data/providers/home_screen_provider.dart';

SongDetailed _song(String videoId, String name, {String artist = 'Artist'}) {
  return SongDetailed(
    type: 'SONG',
    videoId: videoId,
    name: name,
    artist: ArtistBasic(name: artist, artistId: 'ar_$videoId'),
    duration: 210,
    thumbnails: [ThumbnailFull(url: 'https://img/$videoId', width: 60, height: 60)],
  );
}

AlbumDetailed _album(String albumId, String name) {
  return AlbumDetailed(
    name: name,
    type: 'MUSIC_PAGE_TYPE_ALBUM',
    playlistId: 'PL_$albumId',
    thumbnails: [ThumbnailFull(url: 'https://img/$albumId', width: 60, height: 60)],
    artist: ArtistBasic(name: 'Artist'),
    albumId: albumId,
  );
}

void main() {
  group('HomeSectionDTO caching', () {
    test('a song shelf survives the round trip the Speed Dial depends on', () {
      final section = HomeSection(title: 'Listen again', contents: [
        _song('v1', 'First'),
        _song('v2', 'Second'),
      ]);

      final dto = HomeSectionDTO.fromHomeSection(section);
      expect(dto, isNotNull);

      final restored = dto!.toHomeSection();
      expect(restored.contents, hasLength(2));
      expect(restored.contents.every((c) => c is SongDetailed), isTrue);
      expect((restored.contents.first as SongDetailed).videoId, 'v1');
    });

    test('cached items satisfy the List<ContentItemDTO> cast the adapter uses', () {
      // HomeSectionDTOAdapter.read does
      // `(fields[1] as List).cast<ContentItemDTO>()`, which throws on the first
      // element that is not a ContentItemDTO. That silently discarded the whole
      // home cache whenever a shelf contained a track.
      final section = HomeSection(title: 'Mixed', contents: [
        _song('v1', 'Track'),
        _album('a1', 'Album'),
      ]);

      final dto = HomeSectionDTO.fromHomeSection(section)!;
      expect(dto.contents.every((c) => c is ContentItemDTO), isTrue);
      expect(() => dto.contents.cast<ContentItemDTO>().toList(), returnsNormally);
    });

    test('a mixed shelf keeps both kinds of content', () {
      final section = HomeSection(title: 'Mixed', contents: [
        _song('v1', 'Track'),
        _album('a1', 'Album'),
      ]);

      final restored = HomeSectionDTO.fromHomeSection(section)!.toHomeSection();
      expect(restored.contents, hasLength(2));
      expect(restored.contents.first, isA<SongDetailed>());
      expect(restored.contents.last, isA<AlbumDetailed>());
    });

    test('uncacheable content is dropped, not thrown, and empties the shelf', () {
      final section = HomeSection(title: 'Artists', contents: [
        ArtistDetailed(
          artistId: 'ar1',
          name: 'Artist',
          type: 'MUSIC_PAGE_TYPE_ARTIST',
          thumbnails: const [],
        ),
      ]);

      expect(HomeSectionDTO.fromHomeSection(section), isNull);
    });

    test('one uncacheable item does not discard the rest of the shelf', () {
      final section = HomeSection(title: 'Mixed', contents: [
        _album('a1', 'Album'),
        ArtistDetailed(
          artistId: 'ar1',
          name: 'Artist',
          type: 'MUSIC_PAGE_TYPE_ARTIST',
          thumbnails: const [],
        ),
        _song('v1', 'Track'),
      ]);

      final dto = HomeSectionDTO.fromHomeSection(section);
      expect(dto, isNotNull);
      expect(dto!.contents, hasLength(2));
    });
  });

  group('SongInfo.fromHistoryMap', () {
    test('reads a well-formed history row', () {
      final song = SongInfo.fromHistoryMap({
        'id': 'v1',
        'title': 'Track',
        'artists': [
          {'name': 'A', 'id': 'ar1'},
        ],
        'thumbnail': 'https://img/v1',
        'duration': 215,
      });

      expect(song, isNotNull);
      expect(song!.videoId, 'v1');
      expect(song.name, 'Track');
      expect(song.artists.first.name, 'A');
      expect(song.duration, const Duration(seconds: 215));
      expect(song.thumbnails.single.url, 'https://img/v1');
    });

    test('accepts a legacy row that stored duration as a string', () {
      final song = SongInfo.fromHistoryMap({
        'id': 'v1',
        'title': 'Track',
        'duration': '215',
      });

      expect(song!.duration, const Duration(seconds: 215));
    });

    test('returns null for a row with no id or no title', () {
      expect(SongInfo.fromHistoryMap({'title': 'Track'}), isNull);
      expect(SongInfo.fromHistoryMap({'id': 'v1'}), isNull);
      expect(SongInfo.fromHistoryMap({'id': '   ', 'title': 'Track'}), isNull);
    });

    test('yields an empty artist rather than an empty list', () {
      final song = SongInfo.fromHistoryMap({'id': 'v1', 'title': 'Track'});

      expect(song!.artists, hasLength(1));
      expect(song.artists.first.name, '');
    });
  });
}

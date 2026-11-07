import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/home/data/providers/personalized_recommendation_provider.dart';

void main() {
  group('PersonalizedRecommendationProvider.songInfoFromHomeContent', () {
    test('converts a SongDetailed into a playable SongInfo', () {
      final song = SongDetailed(
        type: 'SONG',
        videoId: 'song-1',
        name: 'Track',
        artist: ArtistBasic(artistId: 'artist-1', name: 'Artist'),
        duration: 215,
        thumbnails: [
          ThumbnailFull(url: 'https://img/1.jpg', width: 480, height: 480),
        ],
      );

      final info = PersonalizedRecommendationProvider.songInfoFromHomeContent(
        song,
      );

      expect(info, isNotNull);
      expect(info!.videoId, 'song-1');
      expect(info.name, 'Track');
      expect(info.artists.single.name, 'Artist');
      expect(info.artists.single.id, 'artist-1');
      expect(info.duration, const Duration(seconds: 215));
      expect(info.thumbnails.single.url, 'https://img/1.jpg');
    });

    test('converts a VideoDetailed into a playable SongInfo', () {
      final video = VideoDetailed(
        type: 'VIDEO',
        videoId: 'video-1',
        name: 'Clip',
        artist: ArtistBasic(name: 'Creator'),
        thumbnails: [
          ThumbnailFull(url: 'https://img/2.jpg', width: 320, height: 180),
        ],
      );

      final info = PersonalizedRecommendationProvider.songInfoFromHomeContent(
        video,
      );

      expect(info, isNotNull);
      expect(info!.videoId, 'video-1');
      expect(info.artists.single.name, 'Creator');
      expect(info.thumbnails.single.width, 320);
    });

    test('returns null for non-track shelf entries instead of throwing', () {
      final contents = <dynamic>[
        PlaylistDetailed(
          type: 'PLAYLIST',
          playlistId: 'playlist-1',
          name: 'Mix',
          artist: ArtistBasic(name: ''),
          thumbnails: const [],
        ),
        AlbumDetailed(
          type: 'ALBUM',
          albumId: 'album-1',
          playlistId: 'playlist-2',
          name: 'Album',
          artist: ArtistBasic(name: 'Artist'),
          thumbnails: const [],
        ),
        ArtistDetailed(
          artistId: 'artist-1',
          name: 'Artist',
          type: 'ARTIST',
          thumbnails: const [],
        ),
      ];

      for (final content in contents) {
        expect(
          PersonalizedRecommendationProvider.songInfoFromHomeContent(content),
          isNull,
        );
      }
    });
  });
}

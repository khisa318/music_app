# 1.2.0

## Added

- Added a personalized adaptive home page that learns from listening history and surfaces Listen Again, Top Artist Mixes, Discovery, Trending For You and Genre Exploration sections.
- Added podcast browsing, search, category and detail screens with an in-app podcast player.
- Added play-count, skip and completion tracking that feeds recommendations.
- Personalized sections fall back to the regular YouTube Music home sections for new users.

## Fixed

- Fixed a crash during startup that showed a white screen after the splash screen.
- Personalized home sections now generate on first launch instead of waiting for the periodic refresh.
- Personalized sections now load correctly from the local cache.
- Added the missing translations for the personalized home sections.
- Fixed a recommendation error caused by home-feed shelves mixing albums and playlists in with songs.
- Recommendations now refresh once the home feed and listening history finish loading, so played songs appear without waiting for the periodic refresh.
- New users now get trending songs from the API instead of an empty recommendation area.

## Notes

- Listening preferences are stored locally with Hive and survive app restarts.
- Built with Flutter.
- Full changelog: https://github.com/khisa318/music_app/compare/v1.1.0...v1.2.0

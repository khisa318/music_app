# MusiX v1.0.4

## New

- Import Spotify playlists: paste a Spotify or YouTube playlist link and MusiX detects the source automatically. Spotify playlists are matched track-by-track to YouTube Music and saved as a local, playable playlist, with a live import progress indicator.
- Redesigned player with a liquid-glass dock and a floating mini player that keeps playback controls within reach.
- Session resume: MusiX now remembers what you were playing and where you left off, and restores it on the next launch.
- Richer search with suggestions, and faster, clearer results as you type.
- More notification controls, including seek back and seek forward actions.

## Improvements

- New "Reduce Effects" appearance setting: tone down blur and transparency on floating panels for a flatter look or better performance on low-end devices.
- Home app bar now shows the MusiX app icon instead of a letter avatar.
- "Download all" action for playlists: queue every song in a playlist in one tap.
- Complete rebrand to MusiX across the app, settings, share sheets, storage folders, export files, and notification channels.
- About screen refreshed with the MusiX story, project links, and a changelog.

## Fixed

- Fixed a crash when playback started while notifications were disabled, by creating the media notification channel up front and making notification calls safe.
- Fixed the "Optimise Battery" action failing with a missing plugin error after the rebrand.
- Lyrics cache now reads and writes to the same folder, so cached lyrics are actually reused.

## Notes

- Built with Flutter. All tests and analysis pass.

**Full changelog**: https://github.com/khisa318/music_app/compare/v1.0.3...v1.0.4

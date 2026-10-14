# 1.0.5

## New

- Browse Categories grid on the search screen: 16 genres to jump into when you don't know what to search for yet.
- Playlist link import now accepts both YouTube and Spotify links in one flow, matching each Spotify track to YouTube Music and showing live progress as it goes.

## Improvements

- Search brought in line with the new look: the search field and the YouTube / YouTube Music toggles are now separate, roomier glass controls, the pinned category tabs use the same glass style, and the Local Music filters (All / Download / Music) gained larger tap targets.
- Local playlists now open in the same rich detail screen used for albums and remote playlists, so playback and queuing behave consistently everywhere.
- More reliable stream resolution: MusiX rotates across multiple YouTube clients and retries transient failures before giving up.

## Fixed

- Playback no longer stalls silently when YouTube asks you to verify you're not a bot; a throttled notice now explains what happened.
- New installs default the accent colour to the first swatch, so the first launch always looks intentional.

## Notes

- Built with Flutter. All tests and analysis pass.

**Full changelog**: https://github.com/khisa318/music_app/compare/v1.0.4...v1.0.5

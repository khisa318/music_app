# 1.0.6

## New

- Updates now look after themselves. When a new version is available, MusiX downloads it slowly in the background so it never competes with your music, and it picks up right where it left off even if you close the app. A banner at the top of Home shows live progress - pause, resume or cancel it there - and you'll be prompted to install the moment it's ready. If you prefer, automatic downloads can be limited to Wi-Fi.
- Manage downloads from a new settings sheet on the Downloads screen: choose download quality, how many downloads run at once (now three by default) and Wi-Fi-only downloads.
- Downloads now recover on their own. If one fails, it rotates to the back of the queue and is retried automatically instead of stopping everything.
- Rename the playlists you've created and set a playlist's cover from its top song. Each playlist also suggests more music you can add at the end.
- Fine-tune lyrics timing: nudge any song's lyrics earlier or later in 0.25s steps so they line up perfectly. The adjustment is remembered per song.

## Fixed

- The player no longer plays one song while showing another's title. After a track fails to load, playback returns to a clean state instead of resuming behind the wrong title - pressing play now resolves and plays the song you're actually looking at.

## Notes

- Built with Flutter. All tests and analysis pass.

**Full changelog**: https://github.com/khisa318/music_app/compare/v1.0.5...v1.0.6

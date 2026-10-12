# MusiX v1.0.3

## Improvements

- Redesigned the update screen: a clean themed layout with dedicated "What's New" and "Fixed" sections pulled straight from the release notes.
- Added a previous-versions picker so you can review and install any of the last 10 GitHub releases, and open any release on GitHub.
- Update controls are now grouped into a single "App Updates" section in Settings (current version, check for updates, auto-check, and update channel in one place).
- Added a download tracker right under the home app bar: see the song downloading, its progress, and pause, resume, or cancel without leaving Home. Tap it to open the full Downloads screen.
- Download pause/resume now shows clear, translated status on the tracker.

## Fixed

- The update prompt no longer overlaps the home screen; it now appears as a clean, centered dialog.
- External audio files opened from Android's Files app (ACTION_VIEW) now display correct title/artist instead of "Unknown Title/Artist". Content:// URIs are handled properly.
- Downloads now appear promptly in device storage after completion (media library scan triggered).
- Profile social/share links updated (Telegram, GitHub, Website).
- Home skeleton no longer flashes on reload; speed dial tracks made smaller for better density.
- Language option removed from settings.
- Android intent filters expanded to support more audio formats and file schemes.

## Notes

- Built with Flutter. All tests and analysis pass.

**Full changelog**: https://github.com/khisa318/music_app/compare/v1.0.2...v1.0.3

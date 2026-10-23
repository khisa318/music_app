# 1.0.8

## New

- Restored the frosted-glass styling across the dock and modal surfaces for a more polished and consistent visual experience.
- Added deduplicated crash-report forwarding to Telegram to make debugging and monitoring faster.
- Improved the Android experience with more intentional back-navigation behavior and cleaner idle playback teardown.

## Fixed

- The mini player now floats more cleanly and the dock’s reduced-effects treatment remains visually consistent.
- Android now requires a double back press to exit, preventing accidental app exits.
- Idle playback is now released correctly to avoid lingering background audio state.
- CI and release automation were hardened by removing broken SDK setup, pinning the NDK, and installing required tooling explicitly.
- Release secrets were moved to Dart defines and wired into CI to improve release security and reduce configuration drift.
- Added a security policy to clearly document reporting and disclosure expectations.

## Notes

- Built with Flutter.
- Full changelog: https://github.com/khisa318/music_app/compare/v1.0.7...v1.0.8

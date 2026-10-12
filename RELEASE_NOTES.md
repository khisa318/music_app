# MusiX 1.0.2

## New

- An animated background now runs across the whole app: slow-moving purple,
  violet and pink glows with drifting particles behind every screen. It replaces
  the flat opaque page colour and is theme-aware, with a subtler, lighter
  variant in light mode.
- The background is mounted once behind the navigator and painted with a single
  shared animation ticker, so it costs one `CustomPaint` for the entire app
  rather than one per screen.

## Improved

- App bars keep an opaque surface so titles and controls stay readable over the
  moving background, while content areas let the animation show through.
- Screens that genuinely need a solid fill (dialogs, bottom sheets, cards,
  code/log viewers) still set one explicitly, so the animation only shows where
  it is meant to.

## Fixed

- Repaired `test/update/apk_download_resume_test.dart` for Dio 5. It had been
  committed against Dio 4 APIs (subclassing `Dio`, which Dio 5 no longer allows)
  and left `flutter analyze` and `flutter test` failing on `main`. It now drives
  a real `Dio` through a scripted `HttpClientAdapter`, and the pause/resume
  assertions are unchanged. CI is green again.
- Updated the theme test to assert the new contract that scaffolds are
  transparent so the animated background is visible.

## Verification

- `flutter analyze`: no issues.
- `flutter test`: all 386 tests pass.
- Release build ran the full pipeline (analyze, test, signed APK, signature and
  native-library checks) and passed.

## Download

- `musix-1.0.2.apk` and its `musix-1.0.2.apk.sha256` checksum are attached to
  this release.

**Full changelog**: https://github.com/khisa318/music_app/compare/v1.0.1...v1.0.2

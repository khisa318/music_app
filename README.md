# MusiX

A music streaming and download app for Android, built with Flutter.

MusiX streams from YouTube Music, resolves playable audio URLs through isolated
helpers, plays back locally, and manages a downloadable local library with
full ID3 tag support.

## Platform support

**Android only.** The `ios/`, `linux/`, `macos/`, `web/`, and `windows/`
platform directories have been removed from this repository.

Two consequences to be aware of:

- The app will not build for any other target. `flutter build apk` /
  `flutter run` are the only supported commands.
- The app's `applicationId` is still the Flutter template default,
  `com.example.music_app`. Change it in `android/app/build.gradle.kts`
  before publishing.

## Requirements

| Tool | Version |
| --- | --- |
| Flutter | 3.47.5 (stable) |
| Dart | 3.13.4 |
| JDK | 17 |
| Android SDK | compileSdk 37.0.0, minSdk 24 |
| Gradle | 8.14 |
| Android Gradle Plugin | 8.11.1 |
| Kotlin | 2.2.20 |
| NDK | 28.2.13676358 |

### Rust is required

The app depends on [`metadata_god`][metadata_god], which reads and writes ID3
tags via a Rust native library. That library is compiled from source at build
time by [cargokit][cargokit], so a Rust toolchain must be installed or the
APK will build *without* `libmetadata_god.so` and every metadata feature will
fail silently at runtime.

Install via [rustup](https://www.rust-lang.org/tools/install), then add the
Android targets:

```bash
rustup target add aarch64-linux-android armv7-linux-android x86_64-linux-android
```

#### Windows host caveat

Rust needs a linker for the *host* toolchain to compile build scripts. On
Windows, the default `stable-x86_64-pc-windows-msvc` toolchain requires
Visual Studio's `link.exe`, which is a large install. To avoid it, use Rust's
bundled MinGW toolchain instead:

```bash
rustup toolchain install stable-x86_64-pc-windows-gnu --profile minimal
rustup target add --toolchain stable-x86_64-pc-windows-gnu \
  aarch64-linux-android armv7-linux-android x86_64-linux-android
rustup set default-host x86_64-pc-windows-gnu
```

The `set default-host` step matters: cargokit invokes `rustup run stable`, and
a bare `stable` resolves by **host triple**, not by `rustup default`. Without
it, the MSVC toolchain is still selected and the build fails with
``linker `link.exe` not found``. Setting `RUSTUP_TOOLCHAIN` does *not* work
here — it does not override an explicit `rustup run`.

To revert:

```bash
rustup set default-host x86_64-pc-windows-msvc
rustup default stable-x86_64-pc-windows-msvc
```

## Build

```bash
flutter pub get
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
```

Release builds split per ABI and are much smaller than the universal APK:

```bash
flutter build apk --release --split-per-abi
```

If a build reports `rustup not found in PATH` or `Cargokit BuildTool failed`,
restart your shell so the updated `PATH` is picked up, and stop any stale
Gradle daemon that cached the old environment:

```bash
android/gradlew --stop
```

Verify the Rust library actually landed in the APK:

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep metadata_god
```

Expect one `libmetadata_god.so` per ABI (`arm64-v8a`, `armeabi-v7a`,
`x86_64`). If it is missing, metadata features will not work.

## Architecture

```
lib/
  core/
    providers/    app state (player, downloads, settings, queue, favourites, stats)
    services/     playback, audio URL resolution, downloads, notifications, OTA
    theme/        Material 3 theming
  features/       one directory per user-facing screen
  shared/         cross-feature components
  widgets/        shared widgets
```

21 features under `lib/features/`, including `home`, `search`, `player`,
`library`, `downloads`, `playlists`, `lyrics`, `equalizer`, `stats`, and `ota`.

State management is `provider`; navigation is `go_router`; local persistence is
`hive_ce` with `shared_preferences` for settings.

### Background isolates

Audio URL resolution runs off the UI thread to keep playback responsive. There
are two providers, selected per track:

- `audio_url_isolate.dart` — YouTube (via `youtube_explode_dart`)
- `jiosaavn_isolate.dart` — JioSaavn (via `jiosaavn`)

Which one is used depends on `settingsProvider.jioSaavnEnabled`
(`temp_audio_cache_service.dart:33`).

### Playback

`media_kit` (libmpv) handles decoding. `audio_service` runs the foreground
notification and media-button controls. Playback state lives in
`player_provider.dart` and is driven by `player_service.dart`.

## Testing

```bash
flutter analyze
flutter test
```

`flutter analyze` should report no issues. Two test files exist under `test/`:
`widget_test.dart` and `home_section_cache_test.dart`.

## Notes

- `pubspec.yaml` still declares a few now-unused desktop packages
  (`smtc_windows`, `media_kit_libs_windows_audio`, `media_kit_libs_ios_audio`,
  `media_kit_libs_linux`). They are inert — Gradle only compiles plugins
  matching the target platform — but they can be dropped.
- The 68 `Platform.isWindows` / `isIOS` / `isLinux` guards in `lib/` are
  permanently false on Android. They are harmless and the analyzer is clean,
  but they are dead branches that could be removed.
- `docs/android-update-stable.json` feeds the in-app OTA update check.

[metadata_god]: https://pub.dev/packages/metadata_god
[cargokit]: https://pub.dev/packages/cargokit

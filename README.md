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
- The `applicationId` is `com.khisa318.musiX`. It is the permanent identity of
  the app: changing it after publication produces a different app that cannot
  update an existing install, so treat it as frozen.

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

## Versioning

`pubspec.yaml` is the single source of truth:

```yaml
version: 1.0.0+1   # versionName 1.0.0, versionCode 1
```

Gradle reads both halves via `flutter.versionName` / `flutter.versionCode`, so
there is no version number anywhere else to keep in sync.

Releases are driven by git tags. See [Releasing](#releasing) below.

## Branching and CI

`main` is the default branch and is protected by review.

- Work on a branch: `feat/...`, `fix/...`, `chore/...`, `docs/...`.
- Open a pull request. `.github/workflows/ci.yml` runs format, `flutter
  analyze`, `flutter test` and a debug build on every PR and on every push to
  `main`. Nothing merges without those checks passing.
- Merging to `main` **does not** publish anything. Releases are a separate,
  deliberate step.

CI pins Flutter to the version in `.flutter-version` (currently `3.47.5`)
rather than `latest`, so a Flutter release cannot change CI's behaviour
underneath you.

## Releasing

A release is a tag, and only a tag:

```bash
# 1. Bump the version in pubspec.yaml, e.g. to 1.1.0+2
# 2. Merge that bump through a PR to main
# 3. Tag the merge commit
git tag v1.1.0
git push origin v1.1.0
```

`.github/workflows/release.yml` then:

1. builds a release APK,
2. verifies it is signed and contains `libmetadata_god.so`,
3. renames it `musix-1.1.0.apk` and writes a `.sha256` companion,
4. creates the GitHub Release with auto-generated notes and attaches both.

It refuses to run if the tag disagrees with `version:` in `pubspec.yaml`, so a
release can never claim a version its APK does not have. Drafts and
pre-releases are handled too: a `-` in the tag marks the GitHub Release as a
pre-release.

Merging to `main` publishes nothing. Never delete or move a tag that has been
released.

### Release signing

Android only permits an update to install over an existing app if the APK is
signed with the **same key**. Losing this key means users can never update
in place — only uninstall and start over, losing their library.

Generate the keystore once:

```bash
keytool -genkeypair -v \
  -keystore musix-release.jks \
  -alias musix \
  -keyalg RSA -keysize 4096 -validity 10000
```

Back it up somewhere safe and permanently. For local builds, copy
`android/key.properties.template` to `android/key.properties`, point `storeFile`
at the keystore, and fill in the passwords. That file is gitignored.

For CI, add these repository secrets (`gh secret set NAME`):

| Secret | Contents |
| --- | --- |
| `MUSIX_KEYSTORE_BASE64` | `base64 -w0 musix-release.jks` |
| `MUSIX_KEYSTORE_PASSWORD` | keystore password |
| `MUSIX_KEY_ALIAS` | key alias, e.g. `musix` |
| `MUSIX_KEY_PASSWORD` | key password |

The workflow fails fast if any are missing, rather than silently publishing a
debug-signed APK that users could not update in place.

Without either route, a local `flutter build apk --release` falls back to the
Android debug key and prints a warning. That is fine for local testing and
**must never be published**.

## In-app updates

The app checks GitHub Releases for its own updates — no hand-maintained feed.

- Startup check is silent and non-blocking: offline, rate limiting and
  GitHub outages never interrupt playback or the UI.
- Settings offers a manual check and an update channel (`stable` / `beta`);
  pre-releases are only considered when opted in.
- Downloading shows progress and can be cancelled, writes to internal app
  storage, and verifies the published SHA-256 when one is attached.
- Installation goes through Android's own `PackageInstaller`, so the user
  always confirms. The app never silently installs anything and never requests
  a `file://` URI.

Only stable, non-draft releases with a version-shaped tag and an APK served
from this repository are ever offered.

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

`flutter analyze` should report no issues.

Test files:

| File | Covers |
| --- | --- |
| `test/home_section_cache_test.dart` | home section caching |
| `test/update/app_version_test.dart` | SemVer parsing and ordering |
| `test/update/github_release_test.dart` | release/asset parsing and host trust |
| `test/update/github_release_service_test.dart` | Releases API handling and failures |
| `test/update/update_checker_test.dart` | the installed-vs-release decision |

`test/update/` needs no network and no platform channels: the HTTP layer has a
seam, so `GitHubReleaseService` is tested with a fake transport.

`dart format` is currently **not** enforced in CI — the existing codebase is not
format-clean and reformatting it would bury real changes. Format what you touch.

## Notes

- `pubspec.yaml` still declares a few now-unused desktop packages
  (`smtc_windows`, `media_kit_libs_windows_audio`, `media_kit_libs_ios_audio`,
  `media_kit_libs_linux`). They are inert — Gradle only compiles plugins
  matching the target platform — but they can be dropped.
- The 68 `Platform.isWindows` / `isIOS` / `isLinux` guards in `lib/` are
  permanently false on Android. They are harmless and the analyzer is clean,
  but they are dead branches that could be removed.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the day-to-day workflow.

[metadata_god]: https://pub.dev/packages/metadata_god
[cargokit]: https://pub.dev/packages/cargokit

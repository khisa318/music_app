import '../../../../core/utils/app_version.dart';
import '../models/app_repository.dart';
import '../models/github_release.dart';
import '../services/github_release_service.dart';

/// The version of MusiX currently installed on the device.
class InstalledVersion {
  const InstalledVersion({
    required this.versionName,
    required this.buildNumber,
  });

  /// From `package_info_plus`, i.e. the `versionName` half of
  /// `version: 1.2.0+12` in pubspec.yaml.
  final String versionName;

  /// The `versionCode` half, i.e. `12`.
  final String buildNumber;

  /// The comparable public version. Unparseable input degrades to `0.0.0`
  /// rather than throwing, so a malformed build still runs the app.
  AppVersion get semver => AppVersion.parse(versionName);

  /// `1.2.0 (12)`, for display.
  String get display =>
      buildNumber.isEmpty ? versionName : '$versionName ($buildNumber)';
}

/// Outcome of one update check.
sealed class UpdateCheckResult {
  const UpdateCheckResult();

  /// Installed version is already the newest published release.
  const factory UpdateCheckResult.upToDate(InstalledVersion installed) =
      UpToDateResult;

  /// A strictly newer release exists.
  const factory UpdateCheckResult.available({
    required InstalledVersion installed,
    required GitHubRelease release,
  }) = UpdateAvailableResult;

  /// The check could not be completed. Never fatal.
  const factory UpdateCheckResult.failed({
    required InstalledVersion installed,
    required ReleaseCheckFailure failure,
    String? message,
  }) = UpdateCheckFailedResult;
}

class UpToDateResult extends UpdateCheckResult {
  const UpToDateResult(this.installed);

  final InstalledVersion installed;
}

class UpdateAvailableResult extends UpdateCheckResult {
  const UpdateAvailableResult({required this.installed, required this.release});

  final InstalledVersion installed;
  final GitHubRelease release;
}

class UpdateCheckFailedResult extends UpdateCheckResult {
  const UpdateCheckFailedResult({
    required this.installed,
    required this.failure,
    this.message,
  });

  final InstalledVersion installed;
  final ReleaseCheckFailure failure;
  final String? message;
}

/// Decides whether the running build should be offered an update.
///
/// Split out from `OTAProvider` so the decision logic can be tested with plain
/// objects and no network, no platform channels and no Flutter bindings.
///
/// The comparison is numeric on each of major / minor / patch, never
/// lexicographic, so `1.10.0` correctly beats `1.9.0`.
class UpdateChecker {
  const UpdateChecker();

  /// True when [release] is strictly newer than [installed] *and* safe to
  /// install.
  ///
  /// The Android build number is deliberately ignored: a rebuild of the same
  /// `1.2.0` is not something to nag a user about, and a higher build number
  /// on an older `1.1.9` would be a downgrade. Only the public semver decides.
  ///
  /// Installability is re-checked here rather than trusted from the caller, so
  /// that a draft, a tag that is not a version, a release with no APK, or an
  /// APK served from a host other than GitHub can never reach the download
  /// dialog even if a caller hands one over directly.
  bool isUpdateAvailable({
    required InstalledVersion installed,
    required GitHubRelease release,
    AppRepository? repository,
  }) {
    final repo = repository ?? AppRepository.current;

    if (!release.isInstallable(host: repo.host)) return false;

    final latest = release.version;
    if (latest == null) return false;

    return latest.isNewerThan(installed.semver);
  }

  /// Turns a release lookup plus the installed version into a result.
  ///
  /// [result] comes from `GitHubReleaseService`; a failure is passed straight
  /// through so the caller can decide whether it is worth surfacing (a manual
  /// "Check for updates" tap) or should stay silent (the startup check).
  UpdateCheckResult evaluate({
    required InstalledVersion installed,
    required ReleaseCheckResult result,
  }) {
    return switch (result) {
      ReleaseCheckResult(release: final release?) =>
        isUpdateAvailable(installed: installed, release: release)
            ? UpdateCheckResult.available(
                installed: installed,
                release: release,
              )
            : UpdateCheckResult.upToDate(installed),
      ReleaseCheckResult(failure: final failure?) => UpdateCheckResult.failed(
        installed: installed,
        failure: failure,
        // Carried through, not dropped: the manual "check for updates" sheet
        // shows *why* the check failed, so a silent generic error would hide a
        // reachable problem such as "no releases yet" or "rate limited".
        message: result.message,
      ),
      _ => UpdateCheckResult.upToDate(installed),
    };
  }
}

import '../../features/ota/data/models/github_release.dart';
import '../../features/ota/data/services/update_checker.dart';

/// Everything the update UI needs about a single published release.
///
/// Field names are unchanged from the previous hand-maintained JSON feed so
/// the existing OTA screens keep working; what changed is the source. These
/// are now built from a real GitHub Release rather than a file someone has to
/// remember to edit by hand.
class OTAUpdateInfo {
  const OTAUpdateInfo({
    required this.latestVersion,
    required this.installedVersion,
    required this.installedBuildNumber,
    required this.tagName,
    required this.releaseName,
    required this.releaseNotes,
    required this.updateLog,
    required this.features,
    required this.bugFixes,
    required this.releaseDate,
    required this.releaseUrl,
    required this.apkAsset,
    required this.checksumAsset,
    required this.isPrerelease,
  });

  /// Public version of the release, e.g. `1.2.0` (the `v` is stripped from the
  /// tag `v1.2.0`).
  final String latestVersion;

  /// Public version currently on the device, e.g. `1.1.0`.
  final String installedVersion;

  /// Android `versionCode` currently on the device.
  final String installedBuildNumber;

  /// `v1.2.0`
  final String tagName;

  /// GitHub release title, falling back to the tag when untitled.
  final String releaseName;

  /// Release notes exactly as published, shown verbatim in the dialog.
  final String releaseNotes;

  /// Release notes split into individual bullet points. Empty when the release
  /// has no notes, in which case the UI shows [releaseNotes] or nothing.
  final List<String> updateLog;

  /// Kept for the existing "New Features" block. Always empty today: GitHub
  /// generated notes are a flat list, and the UI hides the section when empty.
  /// Populated only if a release body uses a `### Features` heading.
  final List<String> features;

  /// Same idea for `### Fixes`. The UI hides the section when empty.
  final List<String> bugFixes;

  /// `41.2 MB`, or `unknown size` when GitHub reported no asset size.
  String get size => apkAsset.readableSize;

  /// When the release was published.
  final DateTime releaseDate;

  /// `https://github.com/khisa318/music_app/releases/tag/v1.2.0`
  final String releaseUrl;

  /// The APK to download. Its host is validated against the app's own GitHub
  /// repository before this object is ever constructed.
  final ReleaseAsset apkAsset;

  /// The `musix-1.2.0.apk.sha256` companion, when the release publishes one.
  /// Absent means the download can only be sanity-checked, never verified.
  final ReleaseAsset? checksumAsset;

  final bool isPrerelease;

  String get apkAssetName => apkAsset.name;

  /// Verified HTTPS URL on the app's own GitHub repository.
  String get apkDownloadUrl => apkAsset.downloadUrl.toString();

  bool get hasChecksum => checksumAsset != null;

  /// `1.1.0 (11)` -> `1.2.0`, the one-line version bump shown in the dialog.
  String get versionDelta => '$installedVersion -> $latestVersion';

  /// Builds update info from a real GitHub release.
  ///
  /// Returns `null` when the release has no usable APK, which is the only
  /// case in which a release is not offerable.
  static OTAUpdateInfo? fromRelease({
    required GitHubRelease release,
    required InstalledVersion installed,
    required String fallbackUrl,
  }) {
    final apk = release.apkAsset;
    final version = release.version;
    if (apk == null || version == null) return null;

    final changelog = release.changelog;
    final (features, bugFixes) = _splitSections(release.body);

    return OTAUpdateInfo(
      latestVersion: version.publicVersion,
      installedVersion: installed.versionName,
      installedBuildNumber: installed.buildNumber,
      tagName: release.tagName,
      releaseName: release.name.trim().isEmpty ? release.tagName : release.name,
      releaseNotes: release.body.trim(),
      updateLog: changelog,
      features: features,
      bugFixes: bugFixes,
      releaseDate: release.publishedAt,
      releaseUrl: release.htmlUrl.toString().isEmpty
          ? fallbackUrl
          : release.htmlUrl.toString(),
      apkAsset: apk,
      checksumAsset: release.checksumAssetFor(apk),
      isPrerelease: release.isPrerelease,
    );
  }

  /// Pulls `### Features` / `### Fixes` sections out of a release body.
  ///
  /// GitHub's generated notes do not use these headings, so both lists are
  /// normally empty and the UI simply omits those blocks. Supporting them
  /// costs nothing and lets a hand-written release body structure itself.
  static (List<String>, List<String>) _splitSections(String body) {
    final features = <String>[];
    final fixes = <String>[];

    var bucket = features;
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      final lower = line.toLowerCase();

      if (lower.startsWith('### ')) {
        final heading = lower.substring(4).trim();
        if (heading.contains('fix') || heading.contains('bug')) {
          bucket = fixes;
        } else if (heading.contains('feature') ||
            heading.contains('added') ||
            heading.contains('new')) {
          bucket = features;
        }
        continue;
      }

      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(line);
      if (bullet == null) continue;

      final text = bullet.group(1)!.trim();
      if (text.isNotEmpty) bucket.add(text);
    }

    return (features, fixes);
  }

  @override
  String toString() => 'OTAUpdateInfo($versionDelta)';
}

enum OTAStatus {
  idle,
  checking,
  updateAvailable,
  downloading,
  downloaded,
  installing,
  installed,
  error,
  noUpdate,
}

/// User-facing failure categories.
///
/// Kept deliberately coarse: the update flow is a convenience, and an
/// over-specific error string is worse than a short actionable one.
enum OTAError {
  networkError,
  downloadError,
  installError,
  parseError,
  permissionError,
  storageError,
  checksumError,
  cancelled,
  unknownError,
}

class OTADownloadProgress {
  OTADownloadProgress({
    required this.downloaded,
    required this.total,
    required this.percentage,
    required this.downloadSpeed,
    required this.eta,
  });

  final int downloaded;
  final int total;

  /// 0..100.
  final double percentage;
  final String downloadSpeed;
  final String eta;

  String get formattedDownloaded => formatBytes(downloaded);

  String get formattedTotal => total > 0 ? formatBytes(total) : '';

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

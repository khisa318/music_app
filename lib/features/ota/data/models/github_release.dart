import '../../../../core/utils/app_version.dart';

/// A downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.contentType,
  });

  /// Asset filename as uploaded, e.g. `musix-1.2.0.apk`.
  final String name;

  /// Size in bytes, or `0` when GitHub did not report it.
  final int sizeBytes;

  /// The `browser_download_url`. Only ever accepted when it points back at
  /// this app's own repository - see [isTrustedHost].
  final Uri downloadUrl;

  /// GitHub reports `application/vnd.android.package-archive` for APKs.
  final String contentType;

  bool get isApk => name.toLowerCase().endsWith('.apk');

  bool get isChecksum => name.toLowerCase().endsWith('.sha256');

  /// Human readable size, e.g. `41.2 MB`. Matches the format the previous
  /// hand-maintained JSON feed used, so the UI needs no special casing.
  String get readableSize {
    if (sizeBytes <= 0) return 'unknown size';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = sizeBytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final rounded = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rounded ${units[unit]}';
  }

  /// Guards against an asset URL that points somewhere other than GitHub.
  ///
  /// Release asset JSON is served over HTTPS by GitHub, but validating the
  /// host means a corrupted or spoofed response cannot redirect the download
  /// to an arbitrary server.
  bool isTrustedHost(String host) {
    final assetHost = downloadUrl.host.toLowerCase();
    final expected = host.toLowerCase();
    return assetHost == expected || assetHost == 'api.$expected';
  }

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      downloadUrl: Uri.parse(json['browser_download_url'] as String? ?? ''),
      contentType: json['content_type'] as String? ?? '',
    );
  }
}

/// One entry from the GitHub Releases API.
class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.isDraft,
    required this.isPrerelease,
    required this.assets,
  });

  /// `v1.2.0`
  final String tagName;

  /// Human title. Falls back to [tagName] when the release has no name.
  final String name;

  /// Raw release notes, exactly as written in GitHub.
  final String body;

  final Uri htmlUrl;
  final DateTime publishedAt;
  final bool isDraft;
  final bool isPrerelease;
  final List<ReleaseAsset> assets;

  /// The public semver encoded in the tag, e.g. `1.2.0` for `v1.2.0`.
  ///
  /// Null when the tag is not a version we understand (`nightly`, `latest`,
  /// ...), in which case the release is skipped instead of being guessed at.
  AppVersion? get version => AppVersion.tryParse(tagName);

  /// Release notes broken into individual bullet points.
  ///
  /// GitHub's generated notes look like:
  ///
  /// ```
  /// ## What's Changed
  /// * Fixed login by @someone in #12
  /// * Improved performance by @someone in #13
  ///
  /// **Full Changelog**: https://github.com/.../compare/v1.1.0...v1.2.0
  /// ```
  ///
  /// Section headings, the attribution suffix, the "Full Changelog" footer and
  /// blank lines are dropped so the update dialog shows a clean list of
  /// changes without inventing anything.
  List<String> get changelog {
    final notes = body.trim();
    if (notes.isEmpty) return const <String>[];

    final items = <String>[];

    for (final rawLine in notes.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      if (line.toLowerCase().startsWith('**full changelog**')) continue;

      // A line that is only a bullet marker is formatting noise, not a
      // change, so it is dropped rather than shown as a literal asterisk.
      final bullet = RegExp(r'^[-*+]\s*(.*)$').firstMatch(line);
      final text = (bullet?.group(1) ?? line).trim();
      if (text.isEmpty) continue;

      // Strip the "by @author in #12" suffix that generated notes append.
      final withoutAttribution = text
          .replaceFirst(RegExp(r'\s+by\s+@[\w-]+\s+in\s+#\d+\s*$'), '')
          .trim();

      items.add(withoutAttribution.isEmpty ? text : withoutAttribution);
    }

    return items;
  }

  /// The first bullet, used for the one-line preview in the settings banner.
  String? get changelogPreview {
    final items = changelog;
    return items.isEmpty ? null : items.first;
  }

  ReleaseAsset? get apkAsset {
    for (final asset in assets) {
      if (asset.isApk) return asset;
    }
    return null;
  }

  /// The `musix-1.2.0.apk.sha256` companion, when the release publishes one.
  ReleaseAsset? checksumAssetFor(ReleaseAsset apk) {
    for (final asset in assets) {
      if (asset.isChecksum && asset.name.startsWith(apk.name)) return asset;
    }
    return null;
  }

  /// A release is only usable when it is tagged with a version we understand
  /// and carries an APK we are willing to download.
  bool isInstallable({required String host}) {
    if (isDraft) return false;
    if (version == null) return false;

    final apk = apkAsset;
    if (apk == null) return false;

    return apk.isTrustedHost(host) && apk.downloadUrl.scheme == 'https';
  }

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];

    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final entry in rawAssets) {
        if (entry is Map) {
          assets.add(ReleaseAsset.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }

    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: Uri.parse(json['html_url'] as String? ?? ''),
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isDraft: json['draft'] as bool? ?? false,
      isPrerelease: json['prerelease'] as bool? ?? false,
      assets: List.unmodifiable(assets),
    );
  }
}

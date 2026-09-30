/// Immutable semantic version used for update decisions.
///
/// Deliberately dependency-free and free of `dart:io` / Flutter imports so the
/// comparison rules can be unit tested in plain `flutter test` without a
/// platform channel.
///
/// Accepts the shapes this project actually produces:
///
///   * `1.2.0`        - a GitHub release tag (`v1.2.0`, with the `v` stripped)
///   * `1.2.0+12`     - `versionName+versionCode` straight out of pubspec.yaml
///   * `1.2`          - tolerated, treated as `1.2.0`
///   * `1.2.0-beta.1` - a pre-release, ordered *below* `1.2.0`
///   * `1.2.0+build.5`- build metadata, ignored for ordering
///
/// Anything that cannot be read as a version is rejected by [tryParse] and
/// falls back to `0.0.0` in [parse], so a garbage tag can never be mistaken
/// for an upgrade.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
  });

  /// The parsed numeric core, e.g. `1.2.0`.
  final int major;
  final int minor;
  final int patch;

  /// Dot-separated pre-release identifiers, e.g. `['beta', '1']`.
  /// Empty for a stable release.
  final List<String> preRelease;

  static final RegExp _pattern = RegExp(
    r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
  );

  /// Parses [raw], returning `null` when it is not a recognisable version.
  ///
  /// Never throws: a malformed version from a release tag or from
  /// `package_info_plus` is a normal condition, not an exception.
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;

    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final match = _pattern.firstMatch(trimmed);
    if (match == null) return null;

    final preRelease = match.group(4);
    return AppVersion._(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2) ?? '0'),
      patch: int.parse(match.group(3) ?? '0'),
      preRelease: (preRelease == null || preRelease.isEmpty)
          ? const <String>[]
          : preRelease.split('.'),
    );
  }

  /// Parses [raw], falling back to `0.0.0` when it is unparseable.
  static AppVersion parse(String? raw) =>
      tryParse(raw) ??
      const AppVersion._(major: 0, minor: 0, patch: 0, preRelease: <String>[]);

  bool get isPreRelease => preRelease.isNotEmpty;

  /// `1.2.0`, or `1.2.0-beta.1` when a pre-release.
  String get publicVersion => isPreRelease
      ? '$major.$minor.$patch-${preRelease.join('.')}'
      : '$major.$minor.$patch';

  /// Numeric only, for Android `versionCode`-style display.
  int get buildNumber => major * 1000000 + minor * 1000 + patch;

  /// SemVer 2.0.0 precedence. Build metadata is explicitly ignored.
  ///
  /// Returns a negative number when `this` is older, `0` when equal and a
  /// positive number when `this` is newer. Numeric segments are compared as
  /// integers, so `1.10.0 > 1.9.0` rather than the string comparison that
  /// would get this wrong.
  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // A version with a pre-release tag has *lower* precedence than the
    // matching stable version: 1.2.0-beta.1 < 1.2.0.
    if (isPreRelease != other.isPreRelease) {
      return isPreRelease ? -1 : 1;
    }
    if (!isPreRelease) return 0;

    final length = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;

    for (var i = 0; i < length; i++) {
      // A larger set of pre-release fields has higher precedence when all
      // preceding identifiers are equal.
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;

      final a = preRelease[i];
      final b = other.preRelease[i];

      final aIsNumeric = int.tryParse(a) != null;
      final bIsNumeric = int.tryParse(b) != null;

      // Numeric identifiers always have lower precedence than alphanumeric.
      if (aIsNumeric && !bIsNumeric) return -1;
      if (!aIsNumeric && bIsNumeric) return 1;

      final result = aIsNumeric
          ? int.parse(a).compareTo(int.parse(b))
          : a.compareTo(b);
      if (result != 0) return result;
    }

    return 0;
  }

  /// True when this version is strictly newer than [other].
  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  /// Convenience wrapper for comparing two raw strings.
  ///
  /// Unparseable input is treated as `0.0.0`, which means a release tagged
  /// with nonsense never registers as an update.
  static int compare(String a, String b) => parse(a).compareTo(parse(b));

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() => publicVersion;
}

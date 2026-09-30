/// Where the app looks for its own releases.
///
/// Discovered from the Git remote (`git remote -v`), not hard-coded to a
/// placeholder. Every request the update system makes is built from this, so
/// a fork needs no code change to point at its own releases.
class AppRepository {
  const AppRepository._({
    required this.owner,
    required this.name,
    required this.host,
  });

  /// `khisa318`
  final String owner;

  /// `music_app`
  final String name;

  /// `github.com`
  final String host;

  /// The real repository this app ships from: `khisa318/music_app`.
  static const AppRepository current = AppRepository._(
    owner: 'khisa318',
    name: 'music_app',
    host: 'github.com',
  );

  String get slug => '$owner/$name';

  /// `api.github.com`
  ///
  /// Deliberately distinct from [host]. The JSON API is served from
  /// `api.github.com`; requesting `https://github.com/repos/...` returns the
  /// HTML web page, which would fail to parse as a release.
  String get apiHost => 'api.$host';

  /// `https://api.github.com/repos/khisa318/music_app/releases/latest`
  Uri get latestReleaseApi =>
      Uri.https(apiHost, '/repos/$slug/releases/latest');

  /// `https://api.github.com/repos/khisa318/music_app/releases?per_page=10`
  ///
  /// Used instead of `/latest` when pre-releases are enabled, because
  /// `/latest` always excludes pre-releases.
  Uri get releasesApi =>
      Uri.https(apiHost, '/repos/$slug/releases', {'per_page': '10'});

  /// `https://github.com/khisa318/music_app/releases`
  Uri get releasesPage => Uri.https(host, '/$slug/releases');

  /// `https://github.com/khisa318/music_app/releases/tag/v1.2.0`
  Uri releasePage(String tag) => Uri.https(host, '/$slug/releases/tag/$tag');
}

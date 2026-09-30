import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/ota/data/models/github_release.dart';

const _host = 'github.com';

Map<String, dynamic> _apkJson({
  String name = 'musix-1.2.0.apk',
  int size = 45000000,
  String url =
      'https://github.com/khisa318/music_app/releases/download/v1.2.0/musix-1.2.0.apk',
  String contentType = 'application/vnd.android.package-archive',
}) {
  return <String, dynamic>{
    'name': name,
    'size': size,
    'browser_download_url': url,
    'content_type': contentType,
  };
}

Map<String, dynamic> _releaseJson({
  String tag = 'v1.2.0',
  String? name = '1.2.0',
  String? body,
  String url = 'https://github.com/khisa318/music_app/releases/tag/v1.2.0',
  String? publishedAt = '2026-09-01T10:00:00Z',
  bool draft = false,
  bool prerelease = false,
  List<dynamic>? assets,
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'name': name,
    'body': body ?? '',
    'html_url': url,
    'published_at': publishedAt ?? '',
    'draft': draft,
    'prerelease': prerelease,
    'assets': assets ?? <Map<String, dynamic>>[_apkJson()],
  };
}

void main() {
  group('ReleaseAsset', () {
    test('parses a full asset', () {
      final asset = ReleaseAsset.fromJson(_apkJson());

      expect(asset.name, 'musix-1.2.0.apk');
      expect(asset.sizeBytes, 45000000);
      expect(asset.isApk, isTrue);
      expect(asset.isChecksum, isFalse);
      expect(asset.contentType, 'application/vnd.android.package-archive');
      expect(
        asset.downloadUrl.host,
        'github.com',
      );
      expect(asset.downloadUrl.scheme, 'https');
    });

    test('survives missing fields instead of throwing', () {
      final asset = ReleaseAsset.fromJson(<String, dynamic>{});

      expect(asset.name, isEmpty);
      expect(asset.sizeBytes, 0);
      expect(asset.contentType, isEmpty);
      expect(asset.isApk, isFalse);
      expect(asset.readableSize, 'unknown size');
    });

    test('detects APKs and checksums by extension, case-insensitively', () {
      expect(ReleaseAsset.fromJson(_apkJson(name: 'app.APK')).isApk, isTrue);
      expect(
        ReleaseAsset.fromJson(_apkJson(name: 'musix.sha256')).isChecksum,
        isTrue,
      );
      expect(
        ReleaseAsset.fromJson(_apkJson(name: 'musix-1.2.0.apk.sha256'))
            .isChecksum,
        isTrue,
      );
      // The checksum must not also be mistaken for the APK.
      expect(
        ReleaseAsset.fromJson(_apkJson(name: 'musix-1.2.0.apk.sha256')).isApk,
        isFalse,
      );
    });

    test('readableSize formats each unit', () {
      expect(
        ReleaseAsset.fromJson(_apkJson(size: 512)).readableSize,
        '512 B',
      );
      expect(
        ReleaseAsset.fromJson(_apkJson(size: 1024)).readableSize,
        '1.0 KB',
      );
      expect(
        ReleaseAsset.fromJson(_apkJson(size: 45 * 1024 * 1024)).readableSize,
        '45.0 MB',
      );
      expect(
        ReleaseAsset.fromJson(_apkJson(size: 3 * 1024 * 1024 * 1024))
            .readableSize,
        '3.0 GB',
      );
    });

    test('readableSize reports unknown when size is absent', () {
      expect(
        ReleaseAsset.fromJson(_apkJson(size: 0)).readableSize,
        'unknown size',
      );
      expect(
        ReleaseAsset.fromJson(<String, dynamic>{'size': -1}).readableSize,
        'unknown size',
      );
    });

    group('isTrustedHost', () {
      test('accepts the repository host', () {
        final asset = ReleaseAsset.fromJson(_apkJson());
        expect(asset.isTrustedHost(_host), isTrue);
      });

      test('accepts the api. subdomain of the expected host', () {
        final asset = ReleaseAsset.fromJson(
          _apkJson(
            url: 'https://api.github.com/repos/khisa318/music_app/x.apk',
          ),
        );
        expect(asset.isTrustedHost(_host), isTrue);
      });

      test('is case-insensitive on the host', () {
        final asset = ReleaseAsset.fromJson(
          _apkJson(url: 'https://GitHub.com/khisa318/music_app/x.apk'),
        );
        expect(asset.isTrustedHost(_host), isTrue);
      });

      test('rejects a lookalike or foreign host', () {
        // Substring matching would let "github.com.evil.example" through, and
        // a plain suffix check would let "notgithub.com" through.
        // Note the scheme is *not* considered here; `isInstallable` rejects
        // plain http separately.
        for (final url in <String>[
          'https://github.com.evil.example/x.apk',
          'https://notgithub.com/x.apk',
          'https://evil.example/github.com/x.apk',
          'https://raw.githubusercontent.com/khisa318/music_app/main/x.apk',
          'https://github.com.evil.example:443/x.apk',
        ]) {
          final asset = ReleaseAsset.fromJson(_apkJson(url: url));
          expect(
            asset.isTrustedHost(_host),
            isFalse,
            reason: '$url must not be trusted',
          );
        }
      });

      test('a trusted host over http passes the host check', () {
        // Guarding the scheme in isInstallable, not here, so the two rules
        // stay separately testable.
        final asset = ReleaseAsset.fromJson(
          _apkJson(url: 'http://github.com/khisa318/music_app/x.apk'),
        );
        expect(asset.isTrustedHost(_host), isTrue);
      });
    });
  });

  group('GitHubRelease.fromJson', () {
    test('parses a well-formed release', () {
      final release = GitHubRelease.fromJson(_releaseJson());

      expect(release.tagName, 'v1.2.0');
      expect(release.name, '1.2.0');
      expect(release.isDraft, isFalse);
      expect(release.isPrerelease, isFalse);
      expect(release.assets, hasLength(1));
      expect(release.publishedAt.toUtc().year, 2026);
    });

    test('falls back to the tag when there is no name', () {
      expect(
        GitHubRelease.fromJson(_releaseJson(name: '')).name,
        isEmpty,
        reason: 'name is reported verbatim; callers fall back to the tag',
      );
    });

    test('survives an entirely empty object', () {
      final release = GitHubRelease.fromJson(<String, dynamic>{});

      expect(release.tagName, isEmpty);
      expect(release.body, isEmpty);
      expect(release.assets, isEmpty);
      expect(release.isDraft, isFalse);
      expect(release.isPrerelease, isFalse);
      expect(release.version, isNull);
      expect(release.apkAsset, isNull);
      expect(release.changelog, isEmpty);
      expect(release.changelogPreview, isNull);
      expect(release.publishedAt.millisecondsSinceEpoch, 0);
    });

    test('ignores assets that are not objects', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <dynamic>[
            'not-an-object',
            42,
            _apkJson(),
          ],
        ),
      );
      // The non-map entries are skipped, so exactly one asset survives.
      expect(release.assets, hasLength(1));
    });

    test('tolerates a missing assets key', () {
      final json = _releaseJson()..remove('assets');
      expect(GitHubRelease.fromJson(json).assets, isEmpty);
    });

    test('tolerates an unparseable published_at', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(publishedAt: 'not-a-date'),
      );
      expect(release.publishedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('version', () {
    test('reads the version out of a v-prefixed tag', () {
      final release = GitHubRelease.fromJson(_releaseJson(tag: 'v1.2.0'));
      expect(release.version?.publicVersion, '1.2.0');
    });

    test('reads a bare tag', () {
      final release = GitHubRelease.fromJson(_releaseJson(tag: '2.0.0'));
      expect(release.version?.publicVersion, '2.0.0');
    });

    test('reads a pre-release tag', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(tag: 'v1.3.0-beta.1', prerelease: true),
      );
      expect(release.version?.publicVersion, '1.3.0-beta.1');
      expect(release.version?.isPreRelease, isTrue);
    });

    test('returns null for a non-version tag', () {
      for (final tag in <String>['nightly', 'latest', 'main', '']) {
        expect(
          GitHubRelease.fromJson(_releaseJson(tag: tag)).version,
          isNull,
          reason: 'tag "$tag" must not be guessed at',
        );
      }
    });
  });

  group('apkAsset / checksumAssetFor', () {
    test('finds the APK among other assets', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            _apkJson(name: 'notes.txt', contentType: 'text/plain'),
            _apkJson(name: 'musix-1.2.0.apk.sha256'),
            _apkJson(name: 'musix-1.2.0.apk'),
          ],
        ),
      );

      expect(release.apkAsset?.name, 'musix-1.2.0.apk');
    });

    test('pairs the APK with its own checksum', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            _apkJson(name: 'musix-1.2.0.apk'),
            _apkJson(name: 'musix-1.2.0.apk.sha256'),
          ],
        ),
      );

      final apk = release.apkAsset!;
      expect(release.checksumAssetFor(apk)?.name, 'musix-1.2.0.apk.sha256');
    });

    test('does not pair a checksum belonging to a different build', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            _apkJson(name: 'musix-1.2.0.apk'),
            // Must not be offered as the checksum for 1.2.0.
            _apkJson(name: 'musix-1.9.9.apk.sha256'),
          ],
        ),
      );

      expect(release.checksumAssetFor(release.apkAsset!), isNull);
    });

    test('returns null when the release has no APK', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            _apkJson(name: 'musix-1.2.0.apk.sha256'),
          ],
        ),
      );
      expect(release.apkAsset, isNull);
    });
  });

  group('isInstallable', () {
    test('accepts a proper release', () {
      expect(
        GitHubRelease.fromJson(_releaseJson()).isInstallable(host: _host),
        isTrue,
      );
    });

    test('rejects a draft', () {
      expect(
        GitHubRelease.fromJson(_releaseJson(draft: true))
            .isInstallable(host: _host),
        isFalse,
      );
    });

    test('rejects a non-version tag', () {
      expect(
        GitHubRelease.fromJson(_releaseJson(tag: 'nightly'))
            .isInstallable(host: _host),
        isFalse,
      );
    });

    test('rejects a release with no APK asset', () {
      expect(
        GitHubRelease.fromJson(
          _releaseJson(assets: <Map<String, dynamic>>[]),
        ).isInstallable(host: _host),
        isFalse,
      );
    });

    test('rejects an APK served over plain http', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            _apkJson(
              url:
                  'http://github.com/khisa318/music_app/releases/download/v1.2.0/musix-1.2.0.apk',
            ),
          ],
        ),
      );
      expect(release.isInstallable(host: _host), isFalse);
    });

    test('rejects an APK pointing at another host', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            _apkJson(url: 'https://cdn.evil.example/musix-1.2.0.apk'),
          ],
        ),
      );
      expect(release.isInstallable(host: _host), isFalse);
    });
  });

  group('changelog', () {
    test('returns nothing for empty notes', () {
      expect(GitHubRelease.fromJson(_releaseJson(body: '')).changelog, isEmpty);
      expect(
        GitHubRelease.fromJson(_releaseJson(body: '   \n\n  ')).changelog,
        isEmpty,
      );
    });

    test('extracts bullets from generated release notes', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          body: '''
## What's Changed
* Fixed login by @someone in #12
* Improved performance by @someone in #13

**Full Changelog**: https://github.com/khisa318/music_app/compare/v1.1.0...v1.2.0
''',
        ),
      );

      expect(release.changelog, <String>[
        'Fixed login',
        'Improved performance',
      ]);
    });

    test('keeps plain paragraphs when there are no bullets', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          body: 'Stability improvements.\nBugs fixed.',
        ),
      );
      expect(release.changelog, <String>[
        'Stability improvements.',
        'Bugs fixed.',
      ]);
    });

    test('handles -, * and + bullets and drops headings', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(
          body: '## Added\n- first\n* second\n+ third\n### Sub\n',
        ),
      );
      expect(release.changelog, <String>['first', 'second', 'third']);
    });

    test('does not invent content and never returns blank entries', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(body: '* \n* real change \n*   \n'),
      );
      expect(release.changelog, <String>['real change']);
    });

    test('preview is the first item', () {
      final release = GitHubRelease.fromJson(
        _releaseJson(body: '* First thing\n* Second thing'),
      );
      expect(release.changelogPreview, 'First thing');
    });

    test('preview is null when there are no notes', () {
      expect(
        GitHubRelease.fromJson(_releaseJson(body: '')).changelogPreview,
        isNull,
      );
    });

    test('leaves an author suffix that is not a generated-notes pattern', () {
      // Only the exact "by @user in #12" suffix is stripped; anything else is
      // real text and must survive.
      final release = GitHubRelease.fromJson(
        _releaseJson(body: '* Reworked @nowPlaying by the community'),
      );
      expect(release.changelog, <String>['Reworked @nowPlaying by the community']);
    });
  });
}
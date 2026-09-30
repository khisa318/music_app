import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/ota/data/models/github_release.dart';
import 'package:music_app/features/ota/data/services/github_release_service.dart';
import 'package:music_app/features/ota/data/services/update_checker.dart';

InstalledVersion _installed(
  String version, {
  String build = '1',
}) => InstalledVersion(versionName: version, buildNumber: build);

GitHubRelease _release({
  String tag = 'v1.2.0',
  bool draft = false,
  bool prerelease = false,
  String publishedAt = '2026-09-01T10:00:00Z',
  String apkName = 'musix-1.2.0.apk',
  String apkUrl =
      'https://github.com/khisa318/music_app/releases/download/v1.2.0/musix-1.2.0.apk',
}) {
  return GitHubRelease.fromJson(<String, dynamic>{
    'tag_name': tag,
    'name': tag,
    'body': '',
    'html_url': 'https://github.com/khisa318/music_app/releases/tag/$tag',
    'published_at': publishedAt,
    'draft': draft,
    'prerelease': prerelease,
    'assets': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': apkName,
        'size': 45000000,
        'browser_download_url': apkUrl,
        'content_type': 'application/vnd.android.package-archive',
      },
    ],
  });
}

void main() {
  const checker = UpdateChecker();

  group('InstalledVersion', () {
    test('exposes a comparable semver', () {
      expect(_installed('1.2.0').semver.publicVersion, '1.2.0');
    });

    test('degrades an unreadable version instead of throwing', () {
      expect(_installed('unknown').semver.publicVersion, '0.0.0');
      expect(_installed('').semver.publicVersion, '0.0.0');
    });

    test('display includes the build number when present', () {
      expect(_installed('1.2.0', build: '12').display, '1.2.0 (12)');
      expect(_installed('1.2.0', build: '').display, '1.2.0');
    });
  });

  group('UpdateChecker.isUpdateAvailable', () {
    test('offers a strictly newer release', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.1.0'),
          release: _release(tag: 'v1.2.0'),
        ),
        isTrue,
      );
    });

    test('does not offer the same version again', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.2.0'),
          release: _release(tag: 'v1.2.0'),
        ),
        isFalse,
      );
    });

    test('does not offer an older release', () {
      // A user who sideloaded a newer build must not be pushed backwards.
      expect(
        checker.isUpdateAvailable(
          installed: _installed('2.0.0'),
          release: _release(tag: 'v1.2.0'),
        ),
        isFalse,
      );
    });

    test('compares numerically, so 1.10.0 beats 1.9.0', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.9.0'),
          release: _release(tag: 'v1.10.0'),
        ),
        isTrue,
      );
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.10.0'),
          release: _release(tag: 'v1.9.0'),
        ),
        isFalse,
      );
    });

    test('ignores the build number, so a rebuild is not nagged about', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.2.0', build: '9'),
          release: _release(tag: 'v1.2.0'),
        ),
        isFalse,
      );
    });

    test('a higher build number on an older version is not an upgrade', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.1.9', build: '999'),
          release: _release(tag: 'v1.1.0'),
        ),
        isFalse,
      );
    });

    test('offers a stable release to a user on the matching pre-release', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.3.0-beta.1'),
          release: _release(tag: 'v1.3.0'),
        ),
        isTrue,
      );
    });

    test('offers a newer pre-release to a user on an older stable', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.2.0'),
          release: _release(tag: 'v1.3.0-beta.1', prerelease: true),
        ),
        isTrue,
      );
    });

    test('does not downgrade a beta user to the older stable release', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.3.0-beta.1'),
          release: _release(tag: 'v1.2.0'),
        ),
        isFalse,
      );
    });

    test('never offers a release with an unreadable tag', () {
      // Offering "update to nightly" would be worse than offering nothing.
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.1.0'),
          release: _release(tag: 'nightly'),
        ),
        isFalse,
      );
    });

    test('never offers a draft', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.1.0'),
          release: _release(tag: 'v1.2.0', draft: true),
        ),
        isFalse,
      );
    });

    test('never offers an APK from another host', () {
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.1.0'),
          release: _release(
            tag: 'v1.2.0',
            apkUrl: 'https://cdn.evil.example/musix-1.2.0.apk',
          ),
        ),
        isFalse,
      );
    });

    test('a release with no APK asset is not installable', () {
      final release = GitHubRelease.fromJson(<String, dynamic>{
        'tag_name': 'v1.2.0',
        'assets': <Map<String, dynamic>>[],
      });
      expect(
        checker.isUpdateAvailable(
          installed: _installed('1.1.0'),
          release: release,
        ),
        isFalse,
      );
    });
  });

  group('UpdateChecker.evaluate', () {
    test('turns a newer release into available', () {
      final result = checker.evaluate(
        installed: _installed('1.1.0'),
        result: ReleaseCheckResult.success(_release(tag: 'v1.2.0')),
      );

      expect(result, isA<UpdateAvailableResult>());
      final available = result as UpdateAvailableResult;
      expect(available.release.tagName, 'v1.2.0');
      expect(available.installed.versionName, '1.1.0');
    });

    test('turns the same version into upToDate', () {
      final result = checker.evaluate(
        installed: _installed('1.2.0'),
        result: ReleaseCheckResult.success(_release(tag: 'v1.2.0')),
      );

      expect(result, isA<UpToDateResult>());
      expect((result as UpToDateResult).installed.versionName, '1.2.0');
    });

    test('turns an older release into upToDate, not available', () {
      final result = checker.evaluate(
        installed: _installed('2.0.0'),
        result: ReleaseCheckResult.success(_release(tag: 'v1.2.0')),
      );

      expect(result, isA<UpToDateResult>());
    });

    test('passes a failure through unchanged', () {
      final result = checker.evaluate(
        installed: _installed('1.1.0'),
        result: const ReleaseCheckResult.failed(
          ReleaseCheckFailure.offline,
          'no network',
        ),
      );

      expect(result, isA<UpdateCheckFailedResult>());
      final failed = result as UpdateCheckFailedResult;
      expect(failed.failure, ReleaseCheckFailure.offline);
      expect(failed.message, 'no network');
      expect(failed.installed.versionName, '1.1.0');
    });

    test('an empty result reads as upToDate so nothing is nagged', () {
      final result = checker.evaluate(
        installed: _installed('1.1.0'),
        result: const ReleaseCheckResult.empty(),
      );

      expect(result, isA<UpToDateResult>());
    });

    test('every failure kind is carried through, not swallowed', () {
      for (final failure in ReleaseCheckFailure.values) {
        final result = checker.evaluate(
          installed: _installed('1.1.0'),
          result: ReleaseCheckResult.failed(failure),
        );
        expect((result as UpdateCheckFailedResult).failure, failure);
      }
    });
  });
}
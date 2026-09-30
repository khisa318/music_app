import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/utils/app_version.dart';

void main() {
  group('AppVersion.parse', () {
    test('reads a plain three-part version', () {
      final version = AppVersion.tryParse('1.2.0')!;
      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 0);
      expect(version.isPreRelease, isFalse);
      expect(version.publicVersion, '1.2.0');
    });

    test('strips the v prefix used by git tags', () {
      final version = AppVersion.tryParse('v1.2.0')!;
      expect(version.publicVersion, '1.2.0');
    });

    test('reads the pubspec versionName+versionCode form', () {
      final version = AppVersion.tryParse('1.2.0+12')!;
      expect(version.publicVersion, '1.2.0');
    });

    test('treats a missing minor or patch as zero', () {
      expect(AppVersion.tryParse('1')!.publicVersion, '1.0.0');
      expect(AppVersion.tryParse('1.2')!.publicVersion, '1.2.0');
    });

    test('tolerates surrounding whitespace', () {
      expect(AppVersion.tryParse('  1.2.0  ')!.publicVersion, '1.2.0');
    });

    test('reads a pre-release suffix', () {
      final version = AppVersion.tryParse('1.2.0-beta.1')!;
      expect(version.isPreRelease, isTrue);
      expect(version.preRelease, ['beta', '1']);
      expect(version.publicVersion, '1.2.0-beta.1');
    });

    test('returns null for input that is not a version', () {
      // A release tagged `nightly` or `latest` must not be treated as a
      // version at all - guessing here would offer a bogus update.
      for (final input in <String?>[
        null,
        '',
        '   ',
        'nightly',
        'latest',
        'v',
        'abc.def.ghi',
        '1.2.3.4.5.6',
        '-1.0.0',
        '1..0',
        '1.2.x',
      ]) {
        expect(
          AppVersion.tryParse(input),
          isNull,
          reason: 'expected $input to be rejected',
        );
      }
    });

    test('parse() falls back to 0.0.0 instead of throwing', () {
      expect(AppVersion.parse('garbage').publicVersion, '0.0.0');
      expect(AppVersion.parse(null).publicVersion, '0.0.0');
    });
  });

  group('AppVersion comparison', () {
    // The cases from the spec, plus the one that a string comparison gets
    // wrong.
    test('1.0.0 < 1.1.0', () {
      expect(AppVersion.compare('1.0.0', '1.1.0'), lessThan(0));
    });

    test('1.1.0 < 1.1.1', () {
      expect(AppVersion.compare('1.1.0', '1.1.1'), lessThan(0));
    });

    test('1.2.0 == 1.2.0', () {
      expect(AppVersion.compare('1.2.0', '1.2.0'), 0);
    });

    test('1.9.0 < 1.10.0 (not a string comparison)', () {
      // '1.10.0' < '1.9.0' lexicographically, which is exactly the bug this
      // guards against.
      expect('1.10.0'.compareTo('1.9.0'), lessThan(0));
      expect(AppVersion.compare('1.9.0', '1.10.0'), lessThan(0));
    });

    test('major beats minor and patch', () {
      expect(AppVersion.compare('2.0.0', '1.99.99'), greaterThan(0));
      expect(AppVersion.compare('1.0.0', '2.0.0'), lessThan(0));
    });

    test('minor beats patch', () {
      expect(AppVersion.compare('1.2.0', '1.1.99'), greaterThan(0));
    });

    test('compares numerically, not lexicographically, per segment', () {
      expect(AppVersion.compare('1.10.0', '1.9.0'), greaterThan(0));
      expect(AppVersion.compare('10.0.0', '9.0.0'), greaterThan(0));
      expect(AppVersion.compare('1.2.10', '1.2.9'), greaterThan(0));
    });

    test('a four-part version is not a valid semver and is rejected', () {
      // SemVer is exactly major.minor.patch. Guessing at `1.0.0.1` would let a
      // malformed tag through, so it must degrade to 0.0.0 instead.
      expect(AppVersion.tryParse('1.0.0.1'), isNull);
      expect(AppVersion.parse('1.0.0.1').publicVersion, '0.0.0');
    });

    test('v prefix does not affect ordering', () {
      expect(AppVersion.compare('v1.2.0', '1.2.0'), 0);
      expect(AppVersion.compare('v1.2.0', '1.3.0'), lessThan(0));
    });

    test('build metadata is ignored for ordering', () {
      expect(AppVersion.compare('1.2.0+1', '1.2.0+99'), 0);
      expect(AppVersion.compare('1.2.0+12', '1.3.0+1'), lessThan(0));
    });

    test('a pre-release ranks below its stable release', () {
      expect(AppVersion.compare('1.2.0-beta.1', '1.2.0'), lessThan(0));
      expect(AppVersion.compare('1.2.0', '1.2.0-beta.1'), greaterThan(0));
    });

    test('pre-release identifiers compare numerically', () {
      expect(AppVersion.compare('1.2.0-beta.2', '1.2.0-beta.10'), lessThan(0));
      expect(AppVersion.compare('1.2.0-rc.1', '1.2.0-beta.9'), greaterThan(0));
    });

    test('numeric pre-release identifiers rank below alphanumeric ones', () {
      expect(AppVersion.compare('1.2.0-1', '1.2.0-alpha'), lessThan(0));
    });

    test('more pre-release fields win when the prefix is equal', () {
      expect(AppVersion.compare('1.2.0-alpha', '1.2.0-alpha.1'), lessThan(0));
    });

    test('isNewerThan reads naturally', () {
      final installed = AppVersion.parse('1.1.0');
      expect(AppVersion.parse('1.2.0').isNewerThan(installed), isTrue);
      expect(AppVersion.parse('1.0.0').isNewerThan(installed), isFalse);
      expect(AppVersion.parse('1.1.0').isNewerThan(installed), isFalse);
    });

    test('unparseable versions never look like an upgrade', () {
      // A garbage installed version must not make every release look new, and
      // a garbage release tag must not look new either.
      expect(AppVersion.parse('nightly').isNewerThan(AppVersion.parse('1.0.0')),
          isFalse);
      expect(AppVersion.parse('1.0.0').isNewerThan(AppVersion.parse('nightly')),
          isTrue);
    });

    test('equality and hashCode agree with compareTo', () {
      final a = AppVersion.parse('1.2.0+5');
      final b = AppVersion.parse('v1.2.0');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });
  });

  group('AppVersion.buildNumber', () {
    test('encodes major/minor/patch into a single monotonic integer', () {
      expect(
        AppVersion.parse('1.2.0').buildNumber,
        lessThan(AppVersion.parse('1.3.0').buildNumber),
      );
      expect(
        AppVersion.parse('1.9.0').buildNumber,
        lessThan(AppVersion.parse('1.10.0').buildNumber),
      );
      expect(
        AppVersion.parse('0.99.0').buildNumber,
        lessThan(AppVersion.parse('1.0.0').buildNumber),
      );
    });
  });
}

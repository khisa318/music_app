import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/models/ota_model.dart';
import 'package:music_app/features/ota/data/providers/ota_provider.dart';
import 'package:music_app/features/ota/data/services/github_release_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers `PackageInfo.fromPlatform()` with a fixed version, so the provider
/// believes it is running a chosen build without a device.
void _mockInstalledVersion(String version, String build) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => <String, String>{
          'appName': 'MusiX',
          'packageName': 'com.khisa318.musiX',
          'version': version,
          'buildNumber': build,
          'installTime': '0',
          'updateTime': '0',
        },
      );
}

Map<String, dynamic> _releaseJson(String tag) => <String, dynamic>{
  'tag_name': tag,
  'name': tag,
  'body': '* Something changed',
  'html_url': 'https://github.com/khisa318/music_app/releases/tag/$tag',
  'published_at': '2026-10-01T10:00:00Z',
  'draft': false,
  'prerelease': false,
  'assets': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'musix-$tag.apk',
      'size': 63585047,
      'browser_download_url':
          'https://github.com/khisa318/music_app/releases/download/$tag/musix-$tag.apk',
      'content_type': 'application/vnd.android.package-archive',
    },
  ],
};

/// A provider wired to a fake GitHub that always publishes [tag], with
/// [downloadService] and [installerService] left at their defaults because
/// these tests never reach those steps.
OTAProvider _providerOffering(String tag) {
  final service = GitHubReleaseService();
  service.overrideHttpGet(
    (url) async => Response<dynamic>(
      requestOptions: RequestOptions(path: url.path),
      statusCode: 200,
      data: _releaseJson(tag),
    ),
  );
  return OTAProvider(releaseService: service);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('a version the user skipped', () {
    setUp(() {
      _mockInstalledVersion('1.0.0', '1');
      SharedPreferences.setMockInitialValues(<String, Object>{
        // What "Skip this version" persists.
        'flutter.ota_skipped_version': '1.2.0',
      });
    });

    test('stays skipped for the automatic launch prompt', () async {
      final provider = _providerOffering('1.2.0');

      await provider.checkForUpdates();

      // Silent: no dialog, and no claim that anything is wrong.
      expect(provider.status, OTAStatus.idle);
      expect(provider.updateInfo, isNull);
    });

    test('is still offered on an explicit "Check for updates"', () async {
      final provider = _providerOffering('1.2.0');

      await provider.checkForUpdates(showNoUpdateMessage: true);

      // The regression. This used to resolve to `noUpdate`, so Settings
      // rendered "you are on the latest version" for a release the app itself
      // had just advertised - seconds after the same app showed the update
      // prompt - leaving the user with no way to update from inside the app.
      expect(provider.status, OTAStatus.updateAvailable);
      expect(provider.updateInfo?.latestVersion, '1.2.0');
    });

    test('a manual check does not clear the stored skip', () async {
      final provider = _providerOffering('1.2.0');

      await provider.checkForUpdates(showNoUpdateMessage: true);

      // The user declined the *nagging*, not the knowledge that a release
      // exists. The next launch must still be quiet.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ota_skipped_version'), '1.2.0');
      expect(provider.status, OTAStatus.updateAvailable);
    });

    test('a manual check still reports no update when genuinely up to date',
        () async {
      final provider = _providerOffering('1.0.0');

      await provider.checkForUpdates(showNoUpdateMessage: true);

      // Bypassing the skip must not turn every manual check into a false
      // positive: 1.0.0 is the installed version, so there is nothing to offer.
      expect(provider.status, OTAStatus.noUpdate);
    });
  });

  group('without a skip', () {
    setUp(() {
      _mockInstalledVersion('1.0.0', '1');
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('an explicit check finds the published release', () async {
      final provider = _providerOffering('1.0.1');

      await provider.checkForUpdates(showNoUpdateMessage: true);

      expect(provider.status, OTAStatus.updateAvailable);
      expect(provider.updateInfo?.latestVersion, '1.0.1');
    });

    test('the automatic check finds it silently', () async {
      final provider = _providerOffering('1.0.1');

      await provider.checkForUpdates();

      expect(provider.status, OTAStatus.updateAvailable);
    });

    test('skipVersion persists what the user declined', () async {
      final provider = _providerOffering('1.0.1');
      await provider.checkForUpdates();
      expect(provider.status, OTAStatus.updateAvailable);

      await provider.skipVersion();

      expect(provider.status, OTAStatus.idle);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ota_skipped_version'), '1.0.1');
    });
  });
}
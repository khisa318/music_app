import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/models/ota_model.dart';
import 'package:music_app/features/ota/data/models/github_release.dart';
import 'package:music_app/features/ota/data/providers/ota_provider.dart';
import 'package:music_app/features/ota/data/services/apk_download_service.dart';
import 'package:music_app/features/ota/data/services/github_release_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// A download service whose single attempt resolves to a scripted failure, so
/// the provider's partial-file bookkeeping can be driven without a device.
class _ScriptedDownloadService extends ApkDownloadService {
  _ScriptedDownloadService(this.failure, {this.partial = false});

  final DownloadFailure failure;

  /// Whether [hasPartial] should report bytes left on disk.
  final bool partial;

  @override
  Future<DownloadResult> download({
    required ReleaseAsset apk,
    ReleaseAsset? checksumAsset,
    required String host,
    void Function(OTADownloadProgress progress)? onProgress,
    int? maxBytesPerSecond,
  }) async {
    return DownloadResult.failed(failure);
  }

  @override
  Future<bool> hasPartial(String apkName) async => partial;
}

OTAProvider _providerOffering(String tag, {ApkDownloadService? downloadService}) {
  final service = GitHubReleaseService();
  service.overrideHttpGet(
    (url) async => Response<dynamic>(
      requestOptions: RequestOptions(path: url.path),
      statusCode: 200,
      data: _releaseJson(tag),
    ),
  );
  return OTAProvider(
    releaseService: service,
    downloadService: downloadService,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _mockInstalledVersion('1.0.0', '1');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('a download interrupted by the network', () {
    test('keeps a partial on disk and returns to updateAvailable', () async {
      final provider = _providerOffering(
        '1.0.1',
        downloadService: _ScriptedDownloadService(
          DownloadFailure.offline,
        ),
      );

      await provider.checkForUpdates();
      expect(provider.status, OTAStatus.updateAvailable);

      await provider.startBackgroundDownload();

      // This is what lets the Wi-Fi-reconnect listener resume instead of
      // restarting: the update is available again, and the bytes are still on
      // disk to continue from.
      expect(provider.status, OTAStatus.updateAvailable);
      expect(provider.hasPartialOnDisk, isTrue);
    });

    test('a timeout keeps the partial too', () async {
      final provider = _providerOffering(
        '1.0.1',
        downloadService: _ScriptedDownloadService(DownloadFailure.timeout),
      );

      await provider.checkForUpdates();
      await provider.startBackgroundDownload();

      expect(provider.hasPartialOnDisk, isTrue);
    });
  });

  group('a download the user cancelled', () {
    test('discards the partial so it is not auto-resumed', () async {
      final provider = _providerOffering(
        '1.0.1',
        downloadService: _ScriptedDownloadService(DownloadFailure.cancelled),
      );

      await provider.checkForUpdates();
      await provider.startBackgroundDownload();

      expect(provider.status, OTAStatus.updateAvailable);
      expect(provider.hasPartialOnDisk, isFalse);
    });
  });

  group('an integrity failure', () {
    test('has nothing left to resume', () async {
      final provider = _providerOffering(
        '1.0.1',
        downloadService: _ScriptedDownloadService(DownloadFailure.integrity),
      );

      await provider.checkForUpdates();
      await provider.startBackgroundDownload();

      expect(provider.hasPartialOnDisk, isFalse);
      expect(provider.status, OTAStatus.error);
    });
  });

  group('a restored interrupted session', () {
    test('reports the partial discovered on disk at check time', () async {
      final provider = _providerOffering(
        '1.0.1',
        downloadService: _ScriptedDownloadService(
          DownloadFailure.offline,
          partial: true,
        ),
      );

      await provider.checkForUpdates();
      // The restore/resume sniff runs unawaited off the check; let it finish.
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasPartialOnDisk, isTrue);
    });

    test('reports no partial when none is on disk', () async {
      final provider = _providerOffering(
        '1.0.1',
        downloadService: _ScriptedDownloadService(
          DownloadFailure.offline,
          partial: false,
        ),
      );

      await provider.checkForUpdates();
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasPartialOnDisk, isFalse);
    });
  });
}

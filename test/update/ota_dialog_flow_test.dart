import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/constants/app_locales.dart';
import 'package:music_app/core/models/ota_model.dart';
import 'package:music_app/core/providers/settings_provider.dart';
import 'package:music_app/features/ota/data/models/github_release.dart';
import 'package:music_app/features/ota/data/providers/ota_provider.dart';
import 'package:music_app/features/ota/presentation/screens/ota_screen.dart';
import 'package:music_app/features/ota/presentation/widgets/ota_dialog.dart';
import 'package:music_app/features/ota/presentation/widgets/update_method_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the dialog asked the provider to do, so the choice can be
/// asserted without a browser or a download.
class _RecordingOTAProvider extends OTAProvider {
  int openWebsiteCalls = 0;

  @override
  Future<void> openReleasePage() async {
    openWebsiteCalls++;
  }
}

OTAUpdateInfo _updateInfo() => OTAUpdateInfo(
  latestVersion: '2.0.0',
  installedVersion: '1.0.0',
  installedBuildNumber: '1',
  tagName: 'v2.0.0',
  releaseName: 'MusiX 2.0.0',
  releaseNotes: '- Faster startup',
  updateLog: const ['Faster startup'],
  features: const [],
  bugFixes: const [],
  releaseDate: DateTime(2026, 10, 1),
  releaseUrl: 'https://github.com/khisa318/music_app/releases/tag/v2.0.0',
  apkAsset: ReleaseAsset(
    name: 'musix-2.0.0.apk',
    sizeBytes: 63585047,
    downloadUrl: Uri.parse(
      'https://github.com/khisa318/music_app/releases/download/v2.0.0/'
      'musix-2.0.0.apk',
    ),
    contentType: 'application/vnd.android.package-archive',
  ),
  checksumAsset: null,
  isPrerelease: false,
);

Widget _app({
  required OTAProvider ota,
  required OTAUpdateInfo info,
}) {
  return EasyLocalization(
    supportedLocales: AppLocales.supported,
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    saveLocale: false,
    assetLoader: const RootBundleAssetLoader(),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<OTAProvider>.value(value: ota),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (inner) => ElevatedButton(
                  onPressed: () => OTADialog.show(inner, info),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // EasyLocalization caches loaded translations across tests; clearing the
    // asset bundle makes each test load them fresh.
    rootBundle.clear();
  });

  Future<void> openMethodDialog(WidgetTester tester, OTAProvider ota) async {
    await tester.pumpWidget(_app(ota: ota, info: _updateInfo()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(OTADialog), findsOneWidget);

    await tester.tap(find.text('update_now'.tr()));
    await tester.pumpAndSettle();

    // The regression: this dialog used to open and then swallow the choice
    // because the caller had already disposed its own context.
    expect(find.byType(UpdateMethodDialog), findsOneWidget);
  }

  testWidgets('the update prompt opens the method chooser', (tester) async {
    await openMethodDialog(tester, OTAProvider());
  });

  testWidgets('choosing the in-app download opens the update screen', (
    tester,
  ) async {
    final ota = OTAProvider();

    await openMethodDialog(tester, ota);

    await tester.tap(find.byIcon(Icons.download_rounded));
    await tester.pumpAndSettle();

    expect(ota.isOTAScreenActive, isTrue);
    expect(find.byType(OTAScreen), findsOneWidget);
    expect(find.byType(UpdateMethodDialog), findsNothing);
    expect(find.byType(OTADialog), findsNothing);
  });

  testWidgets('choosing the website opens the release page', (tester) async {
    final ota = _RecordingOTAProvider();

    await openMethodDialog(tester, ota);

    await tester.tap(find.byIcon(Icons.open_in_browser_rounded));
    await tester.pumpAndSettle();

    expect(ota.openWebsiteCalls, 1);
    expect(find.byType(OTAScreen), findsNothing);
    expect(find.byType(UpdateMethodDialog), findsNothing);
    expect(find.byType(OTADialog), findsNothing);
  });
}

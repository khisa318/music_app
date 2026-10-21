import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/constants/app_locales.dart';
import 'package:music_app/features/library/presentation/widgets/local_song_options_bottomsheet.dart';

Widget _app({required Widget child}) => EasyLocalization(
  supportedLocales: AppLocales.supported,
  path: 'assets/translations',
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  saveLocale: false,
  assetLoader: const RootBundleAssetLoader(),
  child: Builder(
    builder: (context) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  final song = <String, dynamic>{
    'id': '42',
    'title': 'Local Track',
    'artist': 'Local Artist',
    'localPath': '/storage/emulated/0/Music/song.mp3',
    'isLocal': true,
    'duration': 200,
  };

  setUp(() {
    // The artwork lookup goes over a platform channel a widget test has no
    // answer for; return null so the sheet falls back to the placeholder.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.khisa318.musiX/local_songs'),
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.khisa318.musiX/local_songs'),
          null,
        );
  });

  testWidgets('local song sheet shows the full option set', (tester) async {
    var played = false;

    await tester.pumpWidget(
      _app(
        child: LocalSongOptionsBottomSheet(
          song: song,
          isDarkMode: true,
          onPlay: () => played = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local Track'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Open in YouTube'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Edit Metadata'), findsOneWidget);
    expect(find.text('Copy file path'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(played, isTrue);
  });
}

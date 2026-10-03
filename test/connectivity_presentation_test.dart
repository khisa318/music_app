import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/constants/app_locales.dart';
import 'package:music_app/core/errors/network_failure.dart';
import 'package:music_app/core/providers/connectivity_provider.dart';
import 'package:music_app/shared/components/app_snackbar.dart';
import 'package:music_app/shared/components/connectivity_status_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A deliberately small screen, so a long translation has to wrap rather than
/// happen to fit. The overflow this guards against needed about 360dp of width
/// that the row did not have.
const Size _phone = Size(320, 640);

/// Wraps [child] the way the app does: a MaterialApp under EasyLocalization
/// with [locale] already selected.
Widget _app({required Widget child, required Locale locale}) =>
    EasyLocalization(
      supportedLocales: AppLocales.supported,
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: locale,
      // The controller is a singleton, so a locale persisted by one test would
      // come back as the starting locale of the next one.
      saveLocale: false,
      assetLoader: const RootBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );

/// A button that shows a snackbar, since that is the only way these are reached.
Widget _showWith(void Function(BuildContext) show) => Builder(
  builder: (context) =>
      TextButton(onPressed: () => show(context), child: const Text('go')),
);

/// A connectivity provider stuck offline. The real one asks the platform, which
/// a widget test has no answer for.
class _OfflineProvider extends ConnectivityProvider {
  @override
  bool get isConnected => false;

  @override
  Future<void> refreshConnectivity() async {}
}

void main() {
  final locales = AppLocales.supported;

  // EasyLocalization reads the saved locale from SharedPreferences over a
  // platform channel, which a widget test has no answer for.
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(rootBundle.clear);

  Future<void> phoneSized(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Shows the snackbar and lets it finish animating in.
  ///
  /// The second pump matters: a snackbar's content is laid out as it slides in,
  /// so an overflowing row does not report itself on the frame it is created.
  Future<void> showSnackBar(WidgetTester tester) async {
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('ConnectivitySnackBar', () {
    for (final isConnected in [false, true]) {
      for (final locale in locales) {
        final label = isConnected ? 'restored' : 'offline';

        testWidgets('$label lays out in ${locale.languageCode}', (
          tester,
        ) async {
          await phoneSized(tester);

          await tester.pumpWidget(
            _app(
              locale: locale,
              child: _showWith(
                (context) => ConnectivitySnackBar.show(context, isConnected),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await showSnackBar(tester);

          expect(find.byType(SnackBar), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('ConnectivityRetryWidget', () {
    for (final locale in locales) {
      testWidgets('lays out in ${locale.languageCode}', (tester) async {
        await phoneSized(tester);

        await tester.pumpWidget(
          _app(
            locale: locale,
            child: ChangeNotifierProvider<ConnectivityProvider>(
              create: (_) => _OfflineProvider(),
              child: Builder(
                builder: (context) => SingleChildScrollView(
                  child: ConnectivityRetryWidget(
                    onRetry: () {},
                    message: 'no_internet_connection'.tr(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The retry label is translated, so the button is asserted, not the word.
        expect(find.byType(ElevatedButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AppSnackBar.showNetworkError', () {
    for (final locale in locales) {
      for (final kind in NetworkFailureKind.values) {
        testWidgets('${kind.name} lays out in ${locale.languageCode}', (
          tester,
        ) async {
          await phoneSized(tester);

          await tester.pumpWidget(
            _app(
              locale: locale,
              child: _showWith(
                (context) => AppSnackBar.showNetworkError(
                  context,
                  NetworkFailure(kind),
                  onRetry: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await showSnackBar(tester);

          expect(find.byType(SnackBar), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('the offline indicator', () {
    for (final locale in locales) {
      testWidgets('lays out in ${locale.languageCode}', (tester) async {
        await phoneSized(tester);

        await tester.pumpWidget(
          _app(
            locale: locale,
            child: ChangeNotifierProvider<ConnectivityProvider>(
              create: (_) => _OfflineProvider(),
              child: const ConnectivityStatusWidget(
                showPersistentIndicator: true,
                child: SizedBox(height: 100),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}

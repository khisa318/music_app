import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/constants/app_colors.dart';
import 'package:music_app/core/theme/app_theme.dart';

const Color _pink = Color(0xFFFF4FE3);
const Color _gold = Color(0xFFB8860B);

Color _accentOf(ThemeData theme) => theme.extension<MusiXAccent>()!.color;

void main() {
  group('AppTheme carries the accent', () {
    test('the light theme takes its primary from the accent', () {
      final theme = AppTheme.lightTheme(_pink);

      expect(theme.primaryColor, _pink);
      expect(theme.colorScheme.primary, _pink);
      expect(_accentOf(theme), _pink);
    });

    test('the dark theme takes its primary from the same accent', () {
      final theme = AppTheme.darkTheme(_pink);

      expect(theme.primaryColor, _pink);
      expect(theme.colorScheme.primary, _pink);
      expect(_accentOf(theme), _pink);
    });

    test('picking another accent rebuilds the theme around it', () {
      final before = AppTheme.lightTheme(_pink);
      final after = AppTheme.lightTheme(_gold);

      expect(before.colorScheme.primary, isNot(after.colorScheme.primary));
      expect(after.colorScheme.primary, _gold);
      expect(_accentOf(after), _gold);
    });

    test('the accent never falls back to the old hardcoded sky blue', () {
      for (final accent in MainScreenColors.accentColors) {
        expect(AppTheme.lightTheme(accent).colorScheme.primary, accent);
        expect(AppTheme.darkTheme(accent).colorScheme.primary, accent);
      }
    });

    test('the scaffold is transparent so the animated background shows', () {
      final light = AppTheme.lightTheme(_pink);
      final dark = AppTheme.darkTheme(_pink);

      // The app-wide AnimatedAppBackground is painted behind the navigator, so
      // a scaffold must not paint over it. Screens that want a solid surface
      // set one explicitly.
      expect(light.scaffoldBackgroundColor, Colors.transparent);
      expect(dark.scaffoldBackgroundColor, Colors.transparent);

      // The app-bar surfaces are deliberately left alone: a bar stays readable
      // over the moving background.
      expect(
        light.appBarTheme.backgroundColor,
        MainScreenColors.lightSurfaceColor,
      );
      expect(
        dark.appBarTheme.backgroundColor,
        MainScreenColors.darkSurfaceColor,
      );
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });
  });

  group('MusiXAccent', () {
    test('copyWith replaces the colour it is given', () {
      expect(const MusiXAccent(_pink).copyWith(color: _gold).color, _gold);
    });

    test('copyWith with no colour keeps the one it had', () {
      expect(const MusiXAccent(_pink).copyWith().color, _pink);
    });

    test('lerp travels from one accent to the other', () {
      final midway = const MusiXAccent(
        _pink,
      ).lerp(const MusiXAccent(_gold), 0.5);

      expect(midway.color, isNot(_pink));
      expect(midway.color, isNot(_gold));
    });

    test('lerp pins the ends', () {
      const start = MusiXAccent(_pink);
      const end = MusiXAccent(_gold);

      expect(start.lerp(end, 0).color, _pink);
      expect(start.lerp(end, 1).color, _gold);
    });

    test('lerp with something that is not an accent changes nothing', () {
      expect(const MusiXAccent(_pink).lerp(null, 0.5).color, _pink);
    });
  });

  group('context.accentColor', () {
    testWidgets('reads the accent off the surrounding theme', (tester) async {
      late Color resolved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(_gold),
          home: Builder(
            builder: (context) {
              resolved = context.accentColor;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, _gold);
    });

    testWidgets('falls back to the app default when a theme has none', (
      tester,
    ) async {
      late Color resolved;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = context.accentColor;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, MainScreenColors.secondaryPink);
    });
  });
}

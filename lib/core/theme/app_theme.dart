import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// The accent the reader picked, carried on the [ThemeData] itself.
///
/// The accent used to reach a widget only as a hand-passed
/// `SettingsProvider.accentColor` argument, so anything that resolved its
/// colour from `Theme.of(context)` fell back to [MainScreenColors.secondaryPink]
/// and ignored the choice that had been made.
@immutable
class MusiXAccent extends ThemeExtension<MusiXAccent> {
  const MusiXAccent(this.color);

  final Color color;

  @override
  MusiXAccent copyWith({Color? color}) => MusiXAccent(color ?? this.color);

  @override
  MusiXAccent lerp(ThemeExtension<MusiXAccent>? other, double t) {
    if (other is! MusiXAccent) {
      return this;
    }

    return MusiXAccent(Color.lerp(color, other.color, t) ?? color);
  }
}

extension MusiXThemeContext on BuildContext {
  /// The accent in force, falling back to the app default when the theme was
  /// built without one.
  Color get accentColor =>
      Theme.of(this).extension<MusiXAccent>()?.color ??
      MainScreenColors.secondaryPink;
}

class AppTheme {
  static ThemeData lightTheme(Color accentColor) => _build(
    ThemeData.light(),
    accentColor,
    surface: MainScreenColors.lightSurfaceColor,
    text: MainScreenColors.lightTextColor,
  );

  static ThemeData darkTheme(Color accentColor) => _build(
    ThemeData.dark(),
    accentColor,
    surface: MainScreenColors.darkSurfaceColor,
    text: MainScreenColors.darkTextColor,
  );

  static ThemeData _build(
    ThemeData base,
    Color accentColor, {
    required Color surface,
    required Color text,
  }) {
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      primaryColor: accentColor,
      // Transparent on purpose: the app-wide AnimatedAppBackground is painted
      // behind the navigator, and every Scaffold reveals it by leaving its own
      // background unset. A screen that wants a solid surface should set one
      // explicitly rather than relying on the scaffold colour.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
      ),
      // Both of these, because widgets reach for either one and only
      // colorScheme.primary used to stay sky-blue after the accent changed.
      colorScheme: base.colorScheme.copyWith(primary: accentColor),
      extensions: <ThemeExtension<dynamic>>[MusiXAccent(accentColor)],
    );
  }
}

class FadeForwardsPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeForwardsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

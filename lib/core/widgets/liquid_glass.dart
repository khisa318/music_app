import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// A frosted "liquid glass" surface: the backdrop is blurred and slightly
/// saturated, then covered with a faint tint and framed with a soft specular
/// rim, so it reads as a sheet of glass rather than a flat panel.
///
/// Whatever is painted behind the widget - scrolling content, the animated app
/// background - is still visible, just softened, so movement reads through the
/// glass. Keep the child itself transparent so the tint is the only surface
/// treatment.
///
/// Used for the floating bottom dock, the player chrome and the glass bars.
/// With "reduce effects" on, the backdrop blur and saturation are dropped while
/// the tint stays at its normal strength, so the surface becomes flatter
/// without turning into an opaque slab.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 16,
    this.tint = Colors.white,
    this.opacity = 0.10,
    this.highlight,
    this.borderWidth = 1.0,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.boxShadow,
    this.saturation = 1.3,
    this.reduceEffects,
  });

  final Widget child;

  /// Corner rounding of the glass sheet.
  final BorderRadius borderRadius;

  /// Backdrop blur amount, in logical pixels. Zero disables the blur.
  final double blur;

  /// Base tint laid over the blurred backdrop.
  final Color tint;

  /// Alpha of [tint]. Kept low so the backdrop stays fully legible.
  final double opacity;

  /// Backdrop saturation. Values above 1 make the colours behind the glass
  /// "pop" the way liquid glass does; 1.0 disables the effect.
  final double saturation;

  /// Colour of the specular rim. Defaults to a theme-aware translucent white.
  final Color? highlight;

  final double borderWidth;

  final EdgeInsetsGeometry padding;

  final EdgeInsetsGeometry margin;

  final List<BoxShadow>? boxShadow;

  /// Overrides the global "reduce effects" setting for this surface. When
  /// null, the [SettingsProvider] value is used. Callers that need the
  /// opposite of the global setting (for example the bottom dock, where the
  /// toggle is intentionally inverted) can pass an explicit value.
  final bool? reduceEffects;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color rim =
        highlight ?? Colors.white.withValues(alpha: isDark ? 0.28 : 0.65);

    final BorderRadius radius = borderRadius;

    final bool shouldReduceEffects =
        reduceEffects ?? _reduceEffectsEnabled(context);

    final double renderOpacity = opacity;

    final ImageFilter? filter = (shouldReduceEffects || blur <= 0)
        ? null
        : (saturation == 1.0
              ? ImageFilter.blur(sigmaX: blur, sigmaY: blur)
              : ImageFilter.compose(
                  outer: ColorFilter.matrix(_saturationMatrix(saturation)),
                  inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ));

    final Widget glassContent = Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: (renderOpacity * 1.5).clamp(0.0, 1.0)),
                  tint.withValues(alpha: renderOpacity),
                  tint.withValues(alpha: renderOpacity * 0.7),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: rim, width: borderWidth),
              ),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
        child: ClipRRect(
          borderRadius: radius,
          child: filter == null
              ? glassContent
              : BackdropFilter(filter: filter, child: glassContent),
        ),
      ),
    );
  }

  bool _reduceEffectsEnabled(BuildContext context) {
    try {
      return Provider.of<SettingsProvider>(context).reduceEffectsEnabled;
    } catch (_) {
      return false;
    }
  }
}

/// Luminance-preserving saturation matrix for [ColorFilter.matrix].
List<double> _saturationMatrix(double s) {
  const double lumR = 0.2126;
  const double lumG = 0.7152;
  const double lumB = 0.0722;
  final double inv = 1 - s;
  final double sr = inv * lumR;
  final double sg = inv * lumG;
  final double sb = inv * lumB;

  return <double>[
    sr + s,
    sg,
    sb,
    0,
    0,
    sr,
    sg + s,
    sb,
    0,
    0,
    sr,
    sg,
    sb + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

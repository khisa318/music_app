import 'dart:ui';

import 'package:flutter/material.dart';

/// A frosted, translucent "liquid glass" surface.
///
/// Whatever is painted behind the widget - scrolling content, the animated app
/// background - is blurred, slightly saturated and tinted, then framed with a
/// soft specular rim so it reads as a sheet of glass rather than a flat panel.
///
/// Used for the floating bottom dock and the player chrome. Keep the child
/// itself transparent: this widget owns the only [BackdropFilter] in the stack,
/// and nesting two of them blurs an already-blurred backdrop.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 20,
    this.tint = Colors.white,
    this.opacity = 0.10,
    this.highlight,
    this.borderWidth = 1.0,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.boxShadow,
    this.saturation = 1.6,
  });

  final Widget child;

  /// Corner rounding of the glass sheet.
  final BorderRadius borderRadius;

  /// Backdrop blur amount, in logical pixels.
  final double blur;

  /// Base tint laid over the blurred backdrop.
  final Color tint;

  /// Alpha of [tint]. Kept low so the backdrop stays legible through the glass.
  final double opacity;

  /// Colour of the specular rim. Defaults to a theme-aware translucent white.
  final Color? highlight;

  final double borderWidth;

  final EdgeInsetsGeometry padding;

  final EdgeInsetsGeometry margin;

  final List<BoxShadow>? boxShadow;

  /// Backdrop saturation. Values above 1 make the colours behind the glass
  /// "pop" the way liquid glass does; 1.0 disables the effect.
  final double saturation;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color rim =
        highlight ?? Colors.white.withValues(alpha: isDark ? 0.28 : 0.65);

    final ImageFilter blurFilter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);

    final ImageFilter filter = saturation == 1.0
        ? blurFilter
        : ImageFilter.compose(
            outer: ColorFilter.matrix(_saturationMatrix(saturation)),
            inner: blurFilter,
          );

    final BorderRadius radius = borderRadius;

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: filter,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tint.withValues(
                            alpha: (opacity * 1.5).clamp(0.0, 1.0),
                          ),
                          tint.withValues(alpha: opacity),
                          tint.withValues(alpha: opacity * 0.7),
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
            ),
          ),
        ),
      ),
    );
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

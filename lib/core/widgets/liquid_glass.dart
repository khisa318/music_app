import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// A translucent "liquid glass" surface: a faint tinted sheet with a soft
/// specular rim, so it reads as glass over the app background rather than a
/// flat panel.
///
/// Whatever is painted behind the widget - scrolling content, the animated app
/// background - stays fully visible: the sheet only adds a tint, a rim and an
/// optional shadow. Keep the child itself transparent so the tint is the only
/// surface treatment.
///
/// Used for the floating bottom dock and the player chrome. With "reduce
/// effects" on, the tint is strengthened for a flatter, more opaque look that
/// hides the backdrop instead of showing it off.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.tint = Colors.white,
    this.opacity = 0.10,
    this.highlight,
    this.borderWidth = 1.0,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.boxShadow,
  });

  final Widget child;

  /// Corner rounding of the glass sheet.
  final BorderRadius borderRadius;

  /// Base tint laid over the backdrop.
  final Color tint;

  /// Alpha of [tint]. Kept low so the backdrop stays fully legible.
  final double opacity;

  /// Colour of the specular rim. Defaults to a theme-aware translucent white.
  final Color? highlight;

  final double borderWidth;

  final EdgeInsetsGeometry padding;

  final EdgeInsetsGeometry margin;

  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color rim =
        highlight ?? Colors.white.withValues(alpha: isDark ? 0.28 : 0.65);

    final BorderRadius radius = borderRadius;

    final bool reduceEffects = _reduceEffectsEnabled(context);

    final double renderOpacity = reduceEffects
        ? (opacity * 2.5).clamp(0.25, 0.95).toDouble()
        : opacity;

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
        child: ClipRRect(borderRadius: radius, child: glassContent),
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

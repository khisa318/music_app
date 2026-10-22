import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimens.dart';
import 'liquid_glass.dart';

/// The frosted surface shared by modal sheets.
///
/// Wrap the sheet content in this and keep the `showModalBottomSheet`
/// background transparent, so the page behind the sheet stays visible through
/// the blur instead of being hidden by a flat panel. The inner [Material] is
/// transparent but keeps [InkWell]/[ListTile] ink working.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.vertical(
      top: Radius.circular(AppDimens.radiusXxl),
    ),
    this.opacity = 0.55,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;

  final BorderRadius borderRadius;

  /// Alpha of the surface tint over the blurred backdrop.
  final double opacity;

  final EdgeInsetsGeometry padding;

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: LiquidGlass(
        borderRadius: borderRadius,
        tint: MainScreenColors.getSurfaceColor(isDark),
        opacity: opacity,
        padding: padding,
        margin: margin,
        child: child,
      ),
    );
  }
}

/// The tint used by glass dialogs, so an `AlertDialog` that needs an explicit
/// colour can stay translucent instead of falling back to an opaque surface.
Color glassDialogColor(BuildContext context) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  return MainScreenColors.getSurfaceColor(isDark).withValues(alpha: 0.72);
}

/// Shows a dialog over a blurred page.
///
/// [showDialog] paints the barrier but leaves the page behind it sharp, which
/// is why dialogs read as flat panels. This route blurs the whole backdrop
/// first, so the translucent dialog (see `DialogThemeData` in `AppTheme`) looks
/// like frosted glass on every screen.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor:
        barrierColor ?? Colors.black.withValues(alpha: isDark ? 0.42 : 0.22),
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: const SizedBox.expand(),
            ),
          ),
          builder(context),
        ],
      );
    },
  );
}

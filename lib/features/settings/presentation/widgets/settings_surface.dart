import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';

/// The single source of truth for the "card" look used across every settings
/// surface, so sections can never drift apart again.
///
/// Follows the About MusiX design the Profile tab is built on: a soft accent
/// gradient, an accent hairline and a coloured lift instead of a flat slab
/// with a hard border.
class SettingsSurface extends StatelessWidget {
  final Widget child;
  final bool isDarkMode;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;
  final Clip clipBehavior;

  const SettingsSurface({
    super.key,
    required this.child,
    required this.isDarkMode,
    required this.accentColor,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = AppDimens.radiusXxl,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    // An explicit `color` means the caller asked for a flat surface (the update
    // banner), so the accent treatment is skipped rather than layered on top.
    final tinted = color == null;

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        gradient:
            tinted
                ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentColor.withValues(
                      alpha: isDarkMode ? 0.07 : 0.05,
                    ),
                    accentColor.withValues(
                      alpha: isDarkMode ? 0.03 : 0.02,
                    ),
                  ],
                )
                : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              tinted
                  ? accentColor.withValues(alpha: AppDimens.opacityLight)
                  : SettingsPalette.borderColor(isDarkMode),
          width: AppDimens.borderWidthThin,
        ),
        boxShadow: [
          BoxShadow(
            color:
                tinted
                    ? accentColor.withValues(alpha: 0.06)
                    : Colors.black.withValues(
                      alpha: isDarkMode ? 0.28 : 0.06,
                    ),
            blurRadius: AppDimens.paddingMd,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: clipBehavior,
        child: child,
      ),
    );
  }
}

/// Hairline separator between rows inside a [SettingsSurface].
///
/// Fades out towards the trailing edge so a long list of rows reads as one
/// card rather than a stack of bars.
class SettingsDivider extends StatelessWidget {
  final bool isDarkMode;
  final double indent;

  const SettingsDivider({
    super.key,
    required this.isDarkMode,
    this.indent = AppDimens.paddingLg,
  });

  @override
  Widget build(BuildContext context) {
    final color = SettingsPalette.borderColor(isDarkMode);

    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Container(
        height: AppDimens.dividerHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Trailing chevron used by every navigable settings row.
class SettingsChevron extends StatelessWidget {
  final bool isDarkMode;
  final Color accentColor;
  final bool muted;

  const SettingsChevron({
    super.key,
    required this.isDarkMode,
    required this.accentColor,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right_rounded,
      size: AppDimens.iconLg,
      color:
          muted
              ? SettingsPalette.mutedTextColor(
                isDarkMode,
              ).withValues(alpha: 0.35)
              : accentColor.withValues(alpha: AppDimens.opacityFaded),
    );
  }
}

/// Colours and metrics shared by the settings design system.
class SettingsPalette {
  const SettingsPalette._();

  static Color borderColor(bool isDarkMode) =>
      isDarkMode
      ? Colors.white.withValues(alpha: AppDimens.opacitySubtle)
      : Colors.black.withValues(alpha: AppDimens.opacitySubtle);

  static Color mutedTextColor(bool isDarkMode) =>
      MainScreenColors.getTextColor(isDarkMode);

  static Color fillColor(bool isDarkMode, Color accentColor, double alpha) =>
      accentColor.withValues(alpha: isDarkMode ? alpha : alpha * 1.3);
}

/// Page header shared by the settings screen and all of its sub-pages.
///
/// Matches the Profile tab: the accent spotlight fades down into the page
/// background, and the section icon sits in the same glowing gradient chip the
/// Profile cards use, so every settings page reads as part of the same product.
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData icon;
  final bool isDarkMode;
  final Color accentColor;
  final String? subtitle;
  final bool showBackButton;
  final List<Widget> actions;

  const SettingsAppBar({
    super.key,
    required this.title,
    required this.icon,
    required this.isDarkMode,
    required this.accentColor,
    this.subtitle,
    this.showBackButton = true,
    this.actions = const [],
  });

  @override
  Size get preferredSize => Size.fromHeight(
    subtitle == null ? kToolbarHeight : kToolbarHeight + AppDimens.spacingMd,
  );

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.of(context).textScaler.scale(1.0);
    final iconScale = textScale > 1.0
        ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
        : 1.0;
    final backgroundColor = MainScreenColors.getBackgroundColor(isDarkMode);

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: kToolbarHeight,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accentColor.withValues(
                alpha: isDarkMode ? 0.20 : 0.12,
              ),
              backgroundColor,
            ],
          ),
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.only(
          left: AppDimens.paddingLg,
          right: AppDimens.paddingSm,
        ),
        child: Row(
          children: [
            if (showBackButton) ...[
              _CircleAction(
                isDarkMode: isDarkMode,
                icon: Icons.arrow_back_rounded,
                iconScale: iconScale,
                onPressed: () => Navigator.maybePop(context),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              const SizedBox(width: AppDimens.spacingSm),
            ],

            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accentColor, accentColor.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(
                      alpha: AppDimens.opacityOverlay,
                    ),
                    blurRadius: AppDimens.spacingSm,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22 * iconScale),
            ),

            const SizedBox(width: AppDimens.spacingMd),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleLg(
                      isDarkMode: isDarkMode,
                    ).copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTextStyles.caption(isDarkMode: isDarkMode)
                          .copyWith(
                            color: SettingsPalette.mutedTextColor(
                              isDarkMode,
                            ).withValues(alpha: AppDimens.opacityMuted),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Neutral circular button used for app bar actions.
class _CircleAction extends StatelessWidget {
  final bool isDarkMode;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconScale;
  final String? tooltip;

  const _CircleAction({
    required this.isDarkMode,
    required this.icon,
    required this.onPressed,
    required this.iconScale,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: MainScreenColors.getTextColor(
          isDarkMode,
        ).withValues(alpha: isDarkMode ? 0.08 : 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: MainScreenColors.getTextColor(
            isDarkMode,
          ).withValues(alpha: isDarkMode ? 0.12 : 0.10),
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 21 * iconScale),
      ),
    );
  }
}

/// Scaffold used by every settings sub-page so they all look identical.
class SettingsSubPageScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;
  final String? subtitle;
  final bool leading;

  const SettingsSubPageScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    this.actions = const [],
    this.subtitle,
    this.leading = true,
  });

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context
        .read<SettingsProvider>();
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;

    return Scaffold(
      backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
      appBar: SettingsAppBar(
        title: title,
        icon: icon,
        subtitle: subtitle,
        isDarkMode: isDarkMode,
        accentColor: accentColor,
        showBackButton: leading,
        actions: actions,
      ),
      body: body,
    );
  }
}

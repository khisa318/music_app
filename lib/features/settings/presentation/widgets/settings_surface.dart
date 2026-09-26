import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';

/// The single source of truth for the "card" look used across every settings
/// surface, so sections can never drift apart again.
class SettingsSurface extends StatelessWidget {
  final Widget child;
  final bool isDarkMode;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;
  final Clip clipBehavior;

  const SettingsSurface({
    super.key,
    required this.child,
    required this.isDarkMode,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = AppDimens.radiusXxl,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color:
            color ??
            MainScreenColors.getSurfaceColor(isDarkMode),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: SettingsPalette.borderColor(isDarkMode),
          width: AppDimens.borderWidthThin,
        ),
        boxShadow: isDarkMode
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: clipBehavior,
        child: child,
      ),
    );
  }
}

/// Hairline separator that matches [SettingsSurface]'s border colour.
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
    return Divider(
      height: AppDimens.dividerHeight,
      thickness: AppDimens.borderWidthThin,
      indent: indent,
      color: SettingsPalette.borderColor(isDarkMode),
    );
  }
}

/// Trailing chevron used by every navigable settings row.
class SettingsChevron extends StatelessWidget {
  final bool isDarkMode;
  final bool muted;

  const SettingsChevron({
    super.key,
    required this.isDarkMode,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right_rounded,
      size: AppDimens.iconLg,
      color: SettingsPalette.mutedTextColor(
        isDarkMode,
      ).withValues(alpha: muted ? 0.35 : 0.7),
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
/// Uses the same visual language as the rest of the app: a circular accent
/// chip, a title, and circular action buttons.
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

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDarkMode
          ? MainScreenColors.darkSurfaceColor
          : MainScreenColors.lightSurfaceColor,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: kToolbarHeight,
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
                color: accentColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 23 * iconScale),
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
                            ).withValues(alpha: 0.6),
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

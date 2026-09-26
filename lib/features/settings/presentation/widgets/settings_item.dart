import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'settings_surface.dart';

/// A single row inside a [SettingsSurface].
///
/// The leading slot is a plain accent icon (no tinted chip) so that a screen
/// full of rows stays calm, and a themed chevron is rendered automatically
/// whenever the row is tappable and no explicit [trailing] is supplied.
class SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDarkMode;
  final Color accentColor;
  final bool showChevron;

  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    required this.isDarkMode,
    required this.accentColor,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accentColor.withValues(alpha: 0.08),
        highlightColor: accentColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.spacingSmMd,
          ),
          child: Row(
            children: [
              Icon(icon, color: accentColor, size: AppDimens.iconMd),

              const SizedBox(width: AppDimens.spacingMd),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.settingsItem(
                        isDarkMode: isDarkMode,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppDimens.spacingXxs),
                      Text(
                        subtitle!,
                        style: AppTextStyles.settingsSubtitle(
                          isDarkMode: isDarkMode,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              if (trailing != null) ...[
                const SizedBox(width: AppDimens.spacingSm),
                trailing!,
              ] else if (onTap != null && showChevron) ...[
                const SizedBox(width: AppDimens.spacingSm),
                SettingsChevron(isDarkMode: isDarkMode),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsToggleItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isDarkMode;
  final Color accentColor;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const SettingsToggleItem({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.isDarkMode,
    required this.accentColor,
    this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      showChevron: false,
      trailing: SettingsToggle(
        value: value,
        onChanged: enabled ? onChanged : null,
        accentColor: accentColor,
        isDarkMode: isDarkMode,
        enabled: enabled,
      ),
      onTap:
          onTap ??
          (enabled && onChanged != null ? () => onChanged!(!value) : null),
      isDarkMode: isDarkMode,
      accentColor: accentColor,
    );
  }
}

/// Hand-rolled switch so it can pick up the user accent colour.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accentColor,
    required this.isDarkMode,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isDarkMode;
  final Color accentColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final trackColor = !enabled
        ? MainScreenColors.getTextColor(
            isDarkMode,
          ).withValues(alpha: 0.08)
        : value
        ? (isDarkMode
              ? accentColor.withValues(alpha: 0.34)
              : accentColor)
        : accentColor.withValues(alpha: 0.16);

    final knobColor = !enabled
        ? Colors.grey.shade500
        : (isDarkMode ? accentColor : Colors.white);

    return Semantics(
      toggled: value,
      enabled: enabled,
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
      child: GestureDetector(
        onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 52,
          height: 30,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(AppDimens.radiusFull),
            border: Border.all(
              color: value && enabled
                  ? accentColor.withValues(alpha: 0.55)
                  : trackColor,
              width: AppDimens.borderWidthThin,
            ),
            boxShadow: value && enabled
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: knobColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Group label above a [SettingsSurface].
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isDarkMode;
  final Color accentColor;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.isDarkMode,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingXs,
        AppDimens.spacingXxl,
        AppDimens.paddingXs,
        AppDimens.spacingSm,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            ),
            child: Icon(icon, color: accentColor, size: AppDimens.iconXs),
          ),
          const SizedBox(width: AppDimens.spacingSmMd),
          Flexible(
            child: Text(
              title.toUpperCase(),
              style: AppTextStyles.caption(
                isDarkMode: isDarkMode,
              ).copyWith(
                color: accentColor,
                fontWeight: AppTextStyles.weightBold,
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience wrapper: a group label followed by its card.
///
/// Entries may be `null` so that conditionally visible rows do not leave a
/// dangling divider behind.
class SettingsGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isDarkMode;
  final Color accentColor;
  final List<Widget?> children;

  const SettingsGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.isDarkMode,
    required this.accentColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final visible = children.whereType<Widget>().toList();

    final rows = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      if (i != 0) rows.add(SettingsDivider(isDarkMode: isDarkMode));
      rows.add(visible[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: title,
          icon: icon,
          isDarkMode: isDarkMode,
          accentColor: accentColor,
        ),
        SettingsSurface(
          isDarkMode: isDarkMode,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

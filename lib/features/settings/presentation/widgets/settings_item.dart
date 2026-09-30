import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'settings_surface.dart';

/// A single row inside a [SettingsSurface].
///
/// The leading icon sits in a soft accent chip — the same gradient the Profile
/// cards use, dialled right down — and a themed chevron is rendered
/// automatically whenever the row is tappable and no explicit [trailing] is
/// supplied.
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
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        splashColor: accentColor.withValues(alpha: 0.08),
        highlightColor: accentColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.paddingMd,
          ),
          child: Row(
            children: [
              Container(
                width: AppDimens.buttonSizeLg,
                height: AppDimens.buttonSizeLg,
                padding: const EdgeInsets.all(AppDimens.spacingSm),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(
                        alpha: isDarkMode ? 0.22 : 0.16,
                      ),
                      accentColor.withValues(
                        alpha: isDarkMode ? 0.10 : 0.07,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: Icon(icon, color: accentColor, size: AppDimens.iconMd),
              ),

              const SizedBox(width: AppDimens.spacingMd),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLg(
                        isDarkMode: isDarkMode,
                      ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppDimens.spacingXxs),
                      Text(
                        subtitle!,
                        style: AppTextStyles.caption(
                          isDarkMode: isDarkMode,
                        ).copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: AppDimens.opacityMuted),
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
                SettingsChevron(
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                ),
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
///
/// Sized and coloured like the Profile page's section labels — a real heading
/// rather than a shouty uppercase micro-label — with the group icon lifted
/// into the glowing gradient chip the Profile cards use.
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
        AppDimens.spacingSmMd,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppDimens.spacingSmMd),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accentColor, accentColor.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
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
            child: Icon(icon, color: Colors.white, size: AppDimens.iconMd),
          ),
          const SizedBox(width: AppDimens.spacingMd),
          Flexible(
            child: Text(
              title,
              style: AppTextStyles.subtitle(
                isDarkMode: isDarkMode,
              ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
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
          accentColor: accentColor,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

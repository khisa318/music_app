import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimens.dart';
import '../../../core/constants/app_text_styles.dart';

/// The app's one "there is nothing here yet" panel.
///
/// Empty states used to be re-implemented per screen, and the copies drifted:
/// the badge was 88dp in one place, 82dp in another and missing entirely in a
/// third, the caption sat at 58% opacity against the muted subtitle the
/// Settings rows use, and the Downloads copy hardcoded grey so it ignored dark
/// mode. This keeps one badge, one type scale and one set of theme-aware
/// colors, matching the accent chip and muted subtitle of [SettingsItem].
///
/// [message] and the action are both optional so a caller can show a bare
/// heading, a heading with an explanation, or the full call to action.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool isDarkMode;
  final Color accentColor;

  /// The soft accent disc behind [icon]. The icon is drawn at half this, which
  /// is the proportion the Playlists states were drawn at.
  final double badgeSize;

  final EdgeInsetsGeometry padding;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.isDarkMode,
    required this.accentColor,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.badgeSize = AppDimens.iconSplash,
    this.padding = const EdgeInsets.all(AppDimens.paddingXxl),
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'An action needs both a label and a callback.',
       );

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: AppDimens.opacityLight),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: badgeSize / 2, color: accentColor),
            ),

            const SizedBox(height: AppDimens.spacingLg),

            Text(
              title,
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.titleSm(
                    isDarkMode: isDarkMode,
                  ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
            ),

            if (message != null) ...[
              const SizedBox(height: AppDimens.spacingSm),

              Text(
                message!,
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.caption(
                      isDarkMode: isDarkMode,
                      color: textColor.withValues(
                        alpha: AppDimens.opacityMuted,
                      ),
                    ),
              ),
            ],

            if (actionLabel != null) ...[
              const SizedBox(height: AppDimens.spacingXl),

              FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.paddingXl,
                    vertical: AppDimens.paddingMd,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMdLg),
                  ),
                ),
                icon: Icon(actionIcon ?? Icons.add_rounded, size: AppDimens.iconMd),
                label: Text(
                  actionLabel!,
                  style:
                      AppTextStyles.button(
                        color: Colors.black,
                      ).copyWith(fontWeight: AppTextStyles.weightBold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

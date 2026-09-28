import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

/// The card language of the About page, lifted out of that screen.
///
/// About MusiX was hand-built before [SettingsSurface] existed and its cards
/// are deliberately more expressive than the flat settings surfaces: a soft
/// accent gradient, an accent hairline and a coloured lift. The Profile page
/// now uses the same look, so the primitives live here rather than being
/// declared twice — the same reasoning that produced `settings_surface.dart`.
class PremiumGradientCard extends StatelessWidget {
  final Widget child;
  final bool isDarkMode;
  final Color accentColor;

  const PremiumGradientCard({
    super.key,
    required this.child,
    required this.isDarkMode,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [
                  accentColor.withValues(alpha: 0.08),
                  accentColor.withValues(alpha: 0.03),
                ]
              : [
                  accentColor.withValues(alpha: 0.05),
                  accentColor.withValues(alpha: 0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
        border: Border.all(
          color: accentColor.withValues(alpha: AppDimens.opacityLight),
          width: AppDimens.borderWidthThin,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: AppDimens.paddingMd,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A tappable row card: gradient icon chip, title, subtitle, accent chevron.
class PremiumActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDarkMode;
  final Color accentColor;

  const PremiumActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDarkMode,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusXl),
      child: Container(
        padding: const EdgeInsets.all(AppDimens.paddingXl),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: AppDimens.opacitySubtle)
                : Colors.black.withValues(alpha: AppDimens.opacitySubtle),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppDimens.paddingMd),
              decoration: BoxDecoration(
                gradient: LinearGradient(
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
              child: Icon(icon, color: Colors.white, size: AppDimens.iconLg),
            ),
            SizedBox(width: AppDimens.spacingLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyLg(isDarkMode: isDarkMode),
                  ),
                  SizedBox(height: AppDimens.spacingXs),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption(isDarkMode: isDarkMode)
                        .copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: AppDimens.opacityMid),
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: accentColor,
              size: AppDimens.iconSm,
            ),
          ],
        ),
      ),
    );
  }
}

/// A square social card: circular icon over the label.
///
/// Expands to fill its slot, so it has to be a direct child of a [Row].
class PremiumSocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accentColor;
  final bool isDarkMode;

  const PremiumSocialButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accentColor,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingXl),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.15),
                accentColor.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
            border: Border.all(
              color: accentColor.withValues(alpha: AppDimens.opacityMedium),
              width: AppDimens.borderWidthThick,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(AppDimens.paddingMd),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: AppDimens.iconXl),
              ),
              SizedBox(height: AppDimens.spacingMd),
              Text(
                label,
                style: AppTextStyles.body2(
                  isDarkMode: isDarkMode,
                ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section label and the gap that separates it from the card above.
///
/// Carries its own leading gap so callers cannot forget it, which is how the
/// About page spaced its sections.
class PremiumSectionLabel extends StatelessWidget {
  final String title;
  final bool isDarkMode;

  const PremiumSectionLabel({
    super.key,
    required this.title,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: AppDimens.spacingXxxl),
        Text(title, style: AppTextStyles.heading(isDarkMode: isDarkMode)),
        SizedBox(height: AppDimens.spacingLg),
      ],
    );
  }
}

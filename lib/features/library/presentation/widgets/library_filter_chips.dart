import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Evenly distributed filter chips for the Library page.
///
/// The reference design shows three equal-width pills that together span the
/// full content width, so the chips are laid out with [Expanded] rather than
/// being sized to their labels.
class LibraryFilterChips extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isDarkMode;
  final Color accentColor;

  const LibraryFilterChips({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelected,
    required this.isDarkMode,
    required this.accentColor,
  }) : assert(labels.length == icons.length);

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingXs,
        AppDimens.paddingLg,
        AppDimens.spacingMd,
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: AppDimens.spacingSm),
            Expanded(
              child: _LibraryFilterChip(
                label: labels[index],
                icon: icons[index],
                isSelected: index == selectedIndex,
                isDarkMode: isDarkMode,
                accentColor: accentColor,
                textColor: textColor,
                onTap: () => onSelected(index),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDarkMode;
  final Color accentColor;
  final Color textColor;
  final VoidCallback onTap;

  const _LibraryFilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDarkMode,
    required this.accentColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingSm),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : MainScreenColors.getSurfaceColor(
                    isDarkMode,
                  ).withValues(alpha: isDarkMode ? 0.55 : 0.85),
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : textColor.withValues(alpha: isDarkMode ? 0.10 : 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: AppDimens.iconSm,
                color: isSelected
                    ? Colors.black
                    : textColor.withValues(alpha: AppDimens.opacityMuted),
              ),

              const SizedBox(width: AppDimens.spacingXs),

              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.body2(
                        isDarkMode: isDarkMode,
                        color: isSelected
                            ? Colors.black
                            : textColor.withValues(
                                alpha: AppDimens.opacityMuted,
                              ),
                      ).copyWith(
                        fontWeight: isSelected
                            ? AppTextStyles.weightBold
                            : AppTextStyles.weightSemiBold,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

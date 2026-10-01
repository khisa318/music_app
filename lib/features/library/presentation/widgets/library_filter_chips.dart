import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

/// The Library's collection filters.
///
/// Every collection is laid out at once, wrapped onto as many rows as it needs,
/// so no filter is ever hidden behind a horizontal scroll. Scrolling was tried
/// first and it was a dead end on a phone: the six pills are wider than a
/// 360dp screen, and a tap that lands on the part of a pill sitting outside the
/// viewport is dropped before it reaches the pill, so the row looked inert.
/// Two rows also match the pill style used in Settings and About.
///
/// Wrapping instead of scrolling also means the selected filter is always on
/// screen, so it never has to be scrolled into view after the fact.
class LibraryFilterChips extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isDarkMode;
  final Color accentColor;

  /// Floor for a pill's width, so short labels stay visually consistent
  /// instead of collapsing into lozenges.
  final double minChipWidth;

  const LibraryFilterChips({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.isDarkMode,
    required this.accentColor,
    this.minChipWidth = 80,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Padding(
      padding: const EdgeInsets.only(
        left: AppDimens.paddingLg,
        right: AppDimens.paddingLg,
        top: AppDimens.spacingXs,
        bottom: AppDimens.spacingMd,
      ),
      child: Wrap(
        spacing: AppDimens.spacingSm,
        runSpacing: AppDimens.spacingSm,
        children: [
          for (var index = 0; index < labels.length; index++)
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: minChipWidth),
              child: _LibraryFilterChip(
                label: labels[index],
                isSelected: index == selectedIndex,
                isDarkMode: isDarkMode,
                accentColor: accentColor,
                textColor: textColor,
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _LibraryFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final Color accentColor;
  final Color textColor;
  final VoidCallback onTap;

  const _LibraryFilterChip({
    required this.label,
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
          height: AppDimens.buttonSizeCompact,
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingMd),
          alignment: Alignment.center,
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
                      : textColor.withValues(alpha: AppDimens.opacityMuted),
                ).copyWith(
                  fontWeight: isSelected
                      ? AppTextStyles.weightBold
                      : AppTextStyles.weightSemiBold,
                ),
          ),
        ),
      ),
    );
  }
}

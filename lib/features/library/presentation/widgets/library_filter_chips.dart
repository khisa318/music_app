import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

/// The Library's collection filters.
///
/// Every collection sits on one horizontally scrolling row. The six pills are
/// wider than a 360dp screen, so the row scrolls rather than wrapping; wrapping
/// stacked them one per line and read as a list instead of a tab bar.
///
/// Whichever pill is selected is scrolled back into view whenever the selection
/// changes, whether it came from a tap or from a swipe on the pages below.
class LibraryFilterChips extends StatefulWidget {
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
  State<LibraryFilterChips> createState() => _LibraryFilterChipsState();
}

class _LibraryFilterChipsState extends State<LibraryFilterChips> {
  final Map<int, GlobalKey> _chipKeys = {};

  @override
  void didUpdateWidget(LibraryFilterChips oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _revealSelected();
    }
  }

  void _revealSelected() {
    final chipContext = _chipKeys[widget.selectedIndex]?.currentContext;

    if (chipContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      chipContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(widget.isDarkMode);

    return Padding(
      padding: const EdgeInsets.only(
        left: AppDimens.paddingLg,
        right: AppDimens.paddingLg,
        top: AppDimens.spacingXs,
        bottom: AppDimens.spacingMd,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.labels.length; index++) ...[
              if (index > 0) const SizedBox(width: AppDimens.spacingSm),
              ConstrainedBox(
                key: _chipKeys.putIfAbsent(index, GlobalKey.new),
                constraints: BoxConstraints(minWidth: widget.minChipWidth),
                child: _LibraryFilterChip(
                  label: widget.labels[index],
                  isSelected: index == widget.selectedIndex,
                  isDarkMode: widget.isDarkMode,
                  accentColor: widget.accentColor,
                  textColor: textColor,
                  onTap: () => widget.onSelected(index),
                ),
              ),
            ],
          ],
        ),
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

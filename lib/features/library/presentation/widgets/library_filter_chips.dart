import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Horizontally scrollable filter chips for the Library page.
///
/// The page has six collections, which no longer fit as evenly distributed
/// pills: on a 360dp phone each pill would be ~59dp wide and leave ~20dp for
/// its label once the icon and padding are accounted for. The row therefore
/// scrolls, and each pill is sized to its own label with [minChipWidth] keeping
/// the shorter labels from collapsing into a lozenge.
class LibraryFilterChips extends StatefulWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isDarkMode;
  final Color accentColor;

  /// Floor for a pill's width, so chips stay visually consistent.
  final double minChipWidth;

  const LibraryFilterChips({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelected,
    required this.isDarkMode,
    required this.accentColor,
    this.minChipWidth = 96,
  }) : assert(labels.length == icons.length);

  @override
  State<LibraryFilterChips> createState() => _LibraryFilterChipsState();
}

class _LibraryFilterChipsState extends State<LibraryFilterChips> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _chipKeys = [];

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(LibraryFilterChips oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.labels.length != widget.labels.length) {
      _syncKeys();
    }

    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _revealSelected();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncKeys() {
    _chipKeys
      ..clear()
      ..addAll(List.generate(widget.labels.length, (_) => GlobalKey()));
  }

  /// Brings the selected pill into view.
  ///
  /// The selection also changes without a tap on this row — creating a
  /// playlist jumps to Playlists and the filter sheet jumps to Favourites —
  /// and those pills can sit off-screen.
  ///
  /// Scrolls [ScrollPosition.ensureVisible] on this row only, rather than
  /// [Scrollable.ensureVisible], so the surrounding page is not re-centred
  /// vertically as a side effect.
  void _revealSelected() {
    if (!_scrollController.hasClients) return;
    if (widget.selectedIndex < 0 || widget.selectedIndex >= _chipKeys.length) {
      return;
    }

    final target = _chipKeys[widget.selectedIndex].currentContext;
    if (target == null) return;

    final renderObject = target.findRenderObject();
    if (renderObject == null) return;

    _scrollController.position.ensureVisible(
      renderObject,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(widget.isDarkMode);

    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimens.spacingXs,
        bottom: AppDimens.spacingMd,
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
        child: Row(
          children: [
            for (var index = 0; index < widget.labels.length; index++) ...[
              if (index > 0) const SizedBox(width: AppDimens.spacingSm),
              ConstrainedBox(
                key: _chipKeys[index],
                constraints: BoxConstraints(minWidth: widget.minChipWidth),
                child: _LibraryFilterChip(
                  label: widget.labels[index],
                  icon: widget.icons[index],
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppDimens.iconSm,
                color: isSelected
                    ? Colors.black
                    : textColor.withValues(alpha: AppDimens.opacityMuted),
              ),

              const SizedBox(width: AppDimens.spacingXs),

              // Not a Flexible: this Row lives in a horizontal scroll view, so
              // its width constraint is unbounded and any flexed child throws
              // "non-zero flex but incoming width constraints are unbounded",
              // which took the whole Library page down with it. The pill sizes
              // to its label instead, and the row scrolls.
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
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
            ],
          ),
        ),
      ),
    );
  }
}

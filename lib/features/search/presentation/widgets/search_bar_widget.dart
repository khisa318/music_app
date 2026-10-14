import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../data/search_screen_services.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode focusNode;
  final bool isDarkMode;
  final Color accentColor;
  final SearchMode searchMode;
  final ValueChanged<String> onSearchTextChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSearchPressed;
  final VoidCallback onClearPressed;
  final VoidCallback onVoiceSearchPressed;
  final VoidCallback onModeChangedToYouTubeMusic;
  final VoidCallback onModeChangedToYouTube;

  const SearchBarWidget({
    super.key,
    required this.searchController,
    required this.focusNode,
    required this.isDarkMode,
    required this.accentColor,
    required this.searchMode,
    required this.onSearchTextChanged,
    required this.onSubmitted,
    required this.onSearchPressed,
    required this.onClearPressed,
    required this.onVoiceSearchPressed,
    required this.onModeChangedToYouTubeMusic,
    required this.onModeChangedToYouTube,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = AppDimens.isMobile(context);
    final isDesktop = AppDimens.isDesktop(context);
    final maxWidth = isDesktop ? AppDimens.maxContentWidth : double.infinity;

    final double fieldRadius = AppDimens.radiusXxl;
    final double pillRadius = AppDimens.radiusXxxl;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AppDimens.paddingLg : AppDimens.paddingXxl,
        vertical: AppDimens.paddingLg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            children: [
              LiquidGlass(
                borderRadius: BorderRadius.circular(fieldRadius),
                opacity: isDarkMode ? 0.12 : 0.5,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDarkMode ? 0.28 : 0.14,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                child: TextField(
                  controller: searchController,
                  focusNode: focusNode,
                  cursorColor: accentColor,
                  style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                  decoration: InputDecoration(
                    hintText: searchMode == SearchMode.youtube
                        ? 'Search YouTube videos...'
                        : 'search_hint'.tr(),
                    hintStyle: AppTextStyles.caption(isDarkMode: isDarkMode)
                        .copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: 0.5),
                        ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(fieldRadius),
                      borderSide: BorderSide(
                        color: accentColor.withValues(alpha: 0.9),
                        width: AppDimens.borderWidthThick,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.paddingXl,
                      vertical: AppDimens.paddingLg,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchController,
                      builder: (context, value, child) {
                        return value.text.isNotEmpty
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.search,
                                      color: MainScreenColors.getTextColor(
                                        isDarkMode,
                                      ).withValues(alpha: 0.5),
                                    ),
                                    onPressed: onSearchPressed,
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: MainScreenColors.getTextColor(
                                        isDarkMode,
                                      ).withValues(alpha: 0.5),
                                    ),
                                    onPressed: onClearPressed,
                                  ),
                                ],
                              )
                            : IconButton(
                                icon: Icon(
                                  Icons.mic,
                                  color: MainScreenColors.getTextColor(
                                    isDarkMode,
                                  ).withValues(alpha: 0.5),
                                ),
                                onPressed: onVoiceSearchPressed,
                                tooltip: 'Voice search',
                              );
                      },
                    ),
                  ),
                  onChanged: onSearchTextChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              const SizedBox(height: AppDimens.spacingMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModeToggleButton(
                    context,
                    'YouTube Music',
                    searchMode == SearchMode.youtubeMusic,
                    onModeChangedToYouTubeMusic,
                    pillRadius,
                  ),
                  const SizedBox(width: AppDimens.spacingMd),
                  _buildModeToggleButton(
                    context,
                    'YouTube',
                    searchMode == SearchMode.youtube,
                    onModeChangedToYouTube,
                    pillRadius,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggleButton(
    BuildContext context,
    String text,
    bool isSelected,
    VoidCallback onPressed,
    double radius,
  ) {
    final bool isMobile = AppDimens.isMobile(context);
    final double horizontalPadding = isMobile
        ? AppDimens.paddingXl
        : AppDimens.paddingXxl;
    final double verticalPadding = isMobile
        ? AppDimens.spacingMd
        : AppDimens.paddingLg;

    final TextStyle textStyle = AppTextStyles.caption(isDarkMode: isDarkMode)
        .copyWith(
          fontWeight: isSelected
              ? AppTextStyles.weightSemiBold
              : AppTextStyles.weightMedium,
          fontSize: isMobile
              ? AppTextStyles.fontSizeBody2
              : AppTextStyles.fontSizeBodyLg,
          color: isSelected
              ? Colors.white.withValues(alpha: 0.95)
              : MainScreenColors.getTextColor(isDarkMode),
        );

    return LiquidGlass(
      borderRadius: BorderRadius.circular(radius),
      tint: isSelected ? accentColor : Colors.white,
      opacity: isSelected ? 0.85 : (isDarkMode ? 0.10 : 0.45),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Text(text, style: textStyle),
          ),
        ),
      ),
    );
  }
}

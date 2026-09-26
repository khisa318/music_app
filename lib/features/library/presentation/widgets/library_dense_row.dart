import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

/// The single list-row shape used across the Library page.
///
/// The reference design puts the text block on the left and the square artwork
/// flush to the right edge, which is the opposite of the classic
/// leading-thumbnail list row. Rows are flat with no card fill or elevation;
/// separation comes from spacing alone.
class LibraryDenseRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? meta;
  final String? artworkUrl;
  final Widget? artwork;
  final IconData placeholderIcon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? actions;
  final bool isSelected;
  final bool isPlaying;
  final bool isDarkMode;
  final Color accentColor;
  final double artworkSize;

  const LibraryDenseRow({
    super.key,
    required this.title,
    required this.placeholderIcon,
    required this.isDarkMode,
    required this.accentColor,
    this.subtitle,
    this.meta,
    this.artworkUrl,
    this.artwork,
    this.onTap,
    this.onLongPress,
    this.actions,
    this.isSelected = false,
    this.isPlaying = false,
    this.artworkSize = AppDimens.thumbnailDefault,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    final titleColor = isPlaying ? accentColor : textColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: AppDimens.opacityLight)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTextStyles.bodyLg(
                            isDarkMode: isDarkMode,
                            color: titleColor,
                          ).copyWith(
                            height: AppTextStyles.lineHeightDefault,
                            fontWeight: AppTextStyles.weightSemiBold,
                          ),
                    ),

                    if (subtitle != null || meta != null) ...[
                      const SizedBox(height: AppDimens.spacingXxs),

                      Row(
                        children: [
                          if (subtitle != null)
                            Flexible(
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    AppTextStyles.body2(
                                      isDarkMode: isDarkMode,
                                      color: textColor.withValues(
                                        alpha: isPlaying
                                            ? AppDimens.opacityMuted
                                            : AppDimens.opacityMid,
                                      ),
                                    ).copyWith(
                                      height: AppTextStyles.lineHeightDefault,
                                    ),
                              ),
                            ),

                          if (subtitle != null && meta != null)
                            Text(
                              ' • ',
                              style: AppTextStyles.body2(
                                isDarkMode: isDarkMode,
                                color: textColor.withValues(
                                  alpha: AppDimens.opacitySemi,
                                ),
                              ),
                            ),

                          if (meta != null)
                            Text(
                              meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  AppTextStyles.body2(
                                    isDarkMode: isDarkMode,
                                    color: textColor.withValues(
                                      alpha: AppDimens.opacitySemi,
                                    ),
                                  ).copyWith(
                                    height: AppTextStyles.lineHeightDefault,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: AppDimens.spacingMd),

              if (actions != null) ...[
                actions!,
                const SizedBox(width: AppDimens.spacingSm),
              ],

              _buildArtwork(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    if (artwork != null) {
      return artwork!;
    }

    final url = artworkUrl;

    final placeholder = Container(
      width: artworkSize,
      height: artworkSize,
      color: MainScreenColors.getSurfaceColor(isDarkMode),
      child: Icon(placeholderIcon, color: accentColor, size: artworkSize * 0.4),
    );

    if (url == null || url.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        child: placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      child: CachedNetworkImage(
        imageUrl: url,
        width: artworkSize,
        height: artworkSize,
        fit: BoxFit.cover,
        memCacheWidth: artworkSize.toInt(),
        memCacheHeight: artworkSize.toInt(),
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) => placeholder,
      ),
    );
  }
}

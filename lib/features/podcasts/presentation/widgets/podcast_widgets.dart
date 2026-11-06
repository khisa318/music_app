import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/podcast_models.dart';
import '../../data/providers/podcast_provider.dart';

const _podcastIconFallback = Icons.podcasts_rounded;

class PodcastArtwork extends StatelessWidget {
  const PodcastArtwork({
    super.key,
    required this.imageUrl,
    this.size,
    this.radius = AppDimens.radiusXl,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
  final double? size;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final content = imageUrl.trim().isEmpty
        ? _fallback(context)
        : CachedNetworkImage(
            imageUrl: imageUrl,
            fit: fit,
            width: size,
            height: size,
            placeholder: (_, _) => _placeholder(context),
            errorWidget: (_, _, _) => _fallback(context),
          );

    final child = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: content),
    );

    return size == null ? AspectRatio(aspectRatio: 1, child: child) : child;
  }

  Widget _placeholder(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.18),
      child: Container(color: Colors.white.withValues(alpha: 0.08)),
    );
  }

  Widget _fallback(BuildContext context) {
    final accent = context.accentColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.55),
            MainScreenColors.primaryPurple.withValues(alpha: 0.7),
            MainScreenColors.backgroundColor,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          _podcastIconFallback,
          color: Colors.white.withValues(alpha: 0.85),
          size: size == null ? 46 : (size! * 0.38).clamp(18, 52),
        ),
      ),
    );
  }
}

class PodcastSectionHeader extends StatelessWidget {
  const PodcastSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppDimens.paddingLg,
    ),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            margin: const EdgeInsets.only(right: AppDimens.spacingSm),
            decoration: BoxDecoration(
              color: context.accentColor,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleSm(isDarkMode: isDark).copyWith(
                fontSize: AppTextStyles.fontSizeSubtitle + 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.paddingSm,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: AppTextStyles.caption(
                  isDarkMode: isDark,
                  color: context.accentColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PodcastCard extends StatelessWidget {
  const PodcastCard({
    super.key,
    required this.show,
    required this.onTap,
    this.width = 154,
    this.height = 214,
    this.showPublisher = true,
  });

  final PodcastShow show;
  final VoidCallback onTap;
  final double width;
  final double height;
  final bool showPublisher;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PodcastArtwork(
                imageUrl: show.artworkUrl,
                size: width,
                radius: AppDimens.radiusXl,
              ),
              const SizedBox(height: AppDimens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      show.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd(isDarkMode: isDark).copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (showPublisher) ...[
                      const SizedBox(height: AppDimens.spacingXxs),
                      Text(
                        show.displayPublisher,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(
                          isDarkMode: isDark,
                          color: MainScreenColors.getTextColor(
                            isDark,
                          ).withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PodcastFeaturedCard extends StatelessWidget {
  const PodcastFeaturedCard({
    super.key,
    required this.show,
    required this.onTap,
    this.width = 300,
  });

  final PodcastShow show;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return SizedBox(
      width: width,
      height: 196,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: show.artworkUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => ColoredBox(
                    color: MainScreenColors.darkSurfaceColor,
                    child: Center(
                      child: Icon(
                        _podcastIconFallback,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 48,
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.86),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: AppDimens.paddingLg,
                  right: AppDimens.paddingLg,
                  bottom: AppDimens.paddingLg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              show.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleSm(
                                isDarkMode: true,
                              ).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppDimens.spacingXxs),
                            Text(
                              show.displayPublisher,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption(
                                isDarkMode: true,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppDimens.spacingMd),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: AppDimens.paddingMd,
                  left: AppDimens.paddingMd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.spacingSmMd,
                      vertical: AppDimens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      'podcast_featured_badge'.tr(),
                      style: AppTextStyles.finePrint(
                        isDarkMode: true,
                        color: Colors.white,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PodcastListTile extends StatelessWidget {
  const PodcastListTile({
    super.key,
    required this.show,
    required this.onTap,
    this.isSubscribed = false,
    this.onSubscribe,
  });

  final PodcastShow show;
  final VoidCallback onTap;
  final bool isSubscribed;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.spacingSm,
          ),
          child: Row(
            children: [
              PodcastArtwork(imageUrl: show.artworkUrl, size: 64),
              const SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      show.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd(isDarkMode: isDark).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingXxs),
                    Text(
                      show.displayPublisher,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        isDarkMode: isDark,
                        color: MainScreenColors.getTextColor(
                          isDark,
                        ).withValues(alpha: 0.55),
                      ),
                    ),
                    if (show.genre != null && show.genre!.isNotEmpty) ...[
                      const SizedBox(height: AppDimens.spacingXxs),
                      Text(
                        show.genre!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.finePrint(
                          isDarkMode: isDark,
                          color: context.accentColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onSubscribe != null)
                IconButton(
                  onPressed: onSubscribe,
                  tooltip: isSubscribed
                      ? 'podcast_subscribed'.tr()
                      : 'podcast_subscribe'.tr(),
                  icon: Icon(
                    isSubscribed
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    color: isSubscribed
                        ? context.accentColor
                        : MainScreenColors.getTextColor(
                            isDark,
                          ).withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PodcastEpisodeTile extends StatelessWidget {
  const PodcastEpisodeTile({
    super.key,
    required this.episode,
    required this.onTap,
    this.onFavorite,
    this.isFavorite = false,
    this.isPlaying = false,
    this.progress,
    this.showArtwork = true,
  });

  final PodcastEpisode episode;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final bool isPlaying;
  final PodcastProgress? progress;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.accentColor;
    final muted = MainScreenColors.getTextColor(
      isDark,
    ).withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppDimens.spacingSm),
          padding: const EdgeInsets.all(AppDimens.paddingMd),
          decoration: BoxDecoration(
            color: MainScreenColors.getSurfaceColor(
              isDark,
            ).withValues(alpha: isDark ? 0.4 : 0.7),
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
            border: Border.all(
              color: isPlaying
                  ? accent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: isDark ? 0.05 : 0.0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showArtwork) ...[
                PodcastArtwork(
                  imageUrl: episode.imageUrl,
                  size: 58,
                  radius: AppDimens.radiusMd,
                ),
                const SizedBox(width: AppDimens.spacingMd),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd(isDarkMode: isDark).copyWith(
                        fontWeight: FontWeight.w600,
                        color: isPlaying ? accent : null,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingXs),
                    Row(
                      children: [
                        if (episode.publishedAt != null) ...[
                          Flexible(
                            child: Text(
                              formatPodcastDate(episode.publishedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.finePrint(
                                isDarkMode: isDark,
                                color: muted,
                              ),
                            ),
                          ),
                          Text(
                            '  ·  ',
                            style: AppTextStyles.finePrint(
                              isDarkMode: isDark,
                              color: muted,
                            ),
                          ),
                        ],
                        Text(
                          formatPodcastDuration(episode.duration),
                          style: AppTextStyles.finePrint(
                            isDarkMode: isDark,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    if (progress != null && progress!.fraction > 0) ...[
                      const SizedBox(height: AppDimens.spacingSm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusPill,
                        ),
                        child: LinearProgressIndicator(
                          value: progress!.fraction,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.spacingSm),
              Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? accent
                          : accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: onTap,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: isPlaying ? Colors.white : accent,
                        size: AppDimens.iconLg,
                      ),
                    ),
                  ),
                  if (onFavorite != null)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      onPressed: onFavorite,
                      icon: Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: AppDimens.iconSm,
                        color: isFavorite
                            ? accent
                            : muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PodcastContinueCard extends StatelessWidget {
  const PodcastContinueCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 286,
  });

  final PodcastListeningItem item;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.accentColor;
    final episode = item.episode;
    final progress = item.progress;
    final remaining = episode.duration > progress.position
        ? episode.duration - progress.position
        : Duration.zero;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          child: Container(
            padding: const EdgeInsets.all(AppDimens.paddingMd),
            decoration: BoxDecoration(
              color: MainScreenColors.getSurfaceColor(
                isDark,
              ).withValues(alpha: isDark ? 0.5 : 0.85),
              borderRadius: BorderRadius.circular(AppDimens.radiusXl),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.0),
              ),
            ),
            child: Row(
              children: [
                PodcastArtwork(
                  imageUrl: episode.imageUrl,
                  size: 66,
                  radius: AppDimens.radiusMd,
                ),
                const SizedBox(width: AppDimens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMd(
                          isDarkMode: isDark,
                        ).copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: AppDimens.spacingXs),
                      Text(
                        remaining > Duration.zero
                            ? 'podcast_time_left'.tr(
                                args: [formatPodcastDuration(remaining)],
                              )
                            : episode.showTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.finePrint(
                          isDarkMode: isDark,
                          color: MainScreenColors.getTextColor(
                            isDark,
                          ).withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: AppDimens.spacingSm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusPill,
                        ),
                        child: LinearProgressIndicator(
                          value: progress.fraction,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.spacingSm),
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: accent,
                  size: 34,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PodcastCategoryTile extends StatelessWidget {
  const PodcastCategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    required this.index,
  });

  final PodcastCategory category;
  final VoidCallback onTap;
  final int index;

  static const _icons = <IconData>[
    Icons.mic_external_on_rounded,
    Icons.newspaper_rounded,
    Icons.trending_up_rounded,
    Icons.memory_rounded,
    Icons.sports_soccer_rounded,
    Icons.spa_rounded,
    Icons.favorite_rounded,
    Icons.psychology_alt_rounded,
  ];

  static const _colors = <List<Color>>[
    [Color(0xFFFF7A00), Color(0xFFFF3D71)],
    [Color(0xFF3D8BFF), Color(0xFF6B4EFF)],
    [Color(0xFF13B98A), Color(0xFF0E8C7A)],
    [Color(0xFF6C63FF), Color(0xFF3F51B5)],
    [Color(0xFF00B4DB), Color(0xFF0083B0)],
    [Color(0xFFFF63B8), Color(0xFFB863FF)],
    [Color(0xFFFF6363), Color(0xFFB02E5C)],
    [Color(0xFF5B5F97), Color(0xFF2B2D42)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _colors[index % _colors.length];
    final icon = _icons[index % _icons.length];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.first.withValues(alpha: 0.9),
                colors.last.withValues(alpha: 0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                bottom: -10,
                child: Icon(
                  icon,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppDimens.paddingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: Colors.white, size: 24),
                    Text(
                      category.titleKey.tr(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd(isDarkMode: true).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PodcastEmptyState extends StatelessWidget {
  const PodcastEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = _podcastIconFallback,
    this.onRetry,
    this.retryLabel,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = MainScreenColors.getTextColor(
      isDark,
    ).withValues(alpha: 0.55);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.paddingXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: context.accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: context.accentColor),
            ),
            const SizedBox(height: AppDimens.spacingLg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSm(isDarkMode: isDark),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppDimens.spacingSm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body2(isDarkMode: isDark, color: muted),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppDimens.spacingXl),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel ?? 'podcast_retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PodcastHomeSkeleton extends StatelessWidget {
  const PodcastHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.black.withValues(alpha: 0.1);

    Widget box(double width, double height, [double radius = 14]) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.paddingLg,
          AppDimens.spacingXl,
          AppDimens.paddingLg,
          AppDimens.bottomDockClearance,
        ),
        children: [
          box(150, 30),
          const SizedBox(height: AppDimens.spacingMd),
          Row(
            children: [
              box(90, 30, 20),
              const SizedBox(width: AppDimens.spacingSm),
              box(90, 30, 20),
              const SizedBox(width: AppDimens.spacingSm),
              box(90, 30, 20),
            ],
          ),
          const SizedBox(height: AppDimens.spacingXl),
          box(220, 20),
          const SizedBox(height: AppDimens.spacingMd),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppDimens.spacingMd),
              itemBuilder: (_, _) => box(300, 196, 20),
            ),
          ),
          const SizedBox(height: AppDimens.spacingXl),
          box(180, 20),
          const SizedBox(height: AppDimens.spacingMd),
          Row(
            children: [
              box(154, 200, 16),
              const SizedBox(width: AppDimens.spacingMd),
              box(154, 200, 16),
            ],
          ),
        ],
      ),
    );
  }
}

String formatPodcastDuration(Duration? duration) {
  if (duration == null || duration <= Duration.zero) return '—';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return hours >= 1 && minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  if (minutes > 0) return '${minutes}m';
  return '${duration.inSeconds}s';
}

String formatPodcastDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) return 'podcast_today'.tr();
  if (difference == 1) return 'podcast_yesterday'.tr();
  if (difference > 1 && difference < 7) {
    return 'podcast_days_ago'.tr(args: ['$difference']);
  }

  if (local.year == now.year) {
    return DateFormat('MMM d').format(local);
  }
  return DateFormat('MMM d, yyyy').format(local);
}

String formatPodcastTime(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

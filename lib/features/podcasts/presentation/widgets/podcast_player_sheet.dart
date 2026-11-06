import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/providers/podcast_provider.dart';
import 'podcast_widgets.dart';

class PodcastPlayerSheet extends StatelessWidget {
  const PodcastPlayerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (_) => const PodcastPlayerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PodcastProvider, PlayerProvider>(
      builder: (context, podcast, player, _) {
        final episode = podcast.currentEpisode;
        if (episode == null) {
          return const SizedBox.shrink();
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = context.accentColor;
        final duration = podcast.currentDuration > Duration.zero
            ? podcast.currentDuration
            : episode.duration;
        final durationMs = duration.inMilliseconds;
        final maxValue = durationMs > 0 ? durationMs.toDouble() : 1.0;

        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: MainScreenColors.getSurfaceColor(isDark),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDimens.radiusXxxl),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(
                    alpha: isDark ? 0.12 : 0.0,
                  ),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(
              AppDimens.paddingXl,
              AppDimens.spacingSm,
              AppDimens.paddingXl,
              AppDimens.paddingXl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AppDimens.dragHandleWidth,
                  height: AppDimens.dragHandleHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  ),
                ),
                const SizedBox(height: AppDimens.spacingLg),
                Row(
                  children: [
                    PodcastArtwork(
                      imageUrl: episode.imageUrl,
                      size: 62,
                      radius: AppDimens.radiusMd,
                    ),
                    const SizedBox(width: AppDimens.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'podcast_now_playing'.tr(),
                            style: AppTextStyles.finePrint(
                              isDarkMode: isDark,
                              color: accent,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppDimens.spacingXxs),
                          Text(
                            episode.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMd(
                              isDarkMode: isDark,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppDimens.spacingXxs),
                          Text(
                            episode.showTitle,
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
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.spacingLg),
                StreamBuilder<Duration>(
                  stream: player.playerService.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final value = position.inMilliseconds
                        .clamp(0, maxValue.toInt())
                        .toDouble();
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: AppDimens.sliderTrackHeight,
                            activeTrackColor: accent,
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            thumbColor: accent,
                            overlayColor: accent.withValues(alpha: 0.18),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            value: value,
                            min: 0,
                            max: maxValue,
                            onChanged: (next) => podcast.seek(
                              Duration(milliseconds: next.round()),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.spacingXs,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatPodcastTime(position),
                                style: AppTextStyles.finePrint(
                                  isDarkMode: isDark,
                                  color: MainScreenColors.getTextColor(
                                    isDark,
                                  ).withValues(alpha: 0.55),
                                ),
                              ),
                              Text(
                                formatPodcastTime(duration),
                                style: AppTextStyles.finePrint(
                                  isDarkMode: isDark,
                                  color: MainScreenColors.getTextColor(
                                    isDark,
                                  ).withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppDimens.spacingSm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlButton(
                      icon: Icons.replay_10_rounded,
                      onTap: () => podcast.seekBy(
                        const Duration(seconds: -15),
                      ),
                      isDark: isDark,
                    ),
                    _ControlButton(
                      icon: Icons.skip_previous_rounded,
                      onTap: podcast.playPrevious,
                      isDark: isDark,
                    ),
                    _PlayPauseButton(podcast: podcast, accent: accent),
                    _ControlButton(
                      icon: Icons.skip_next_rounded,
                      onTap: podcast.playNext,
                      isDark: isDark,
                    ),
                    _ControlButton(
                      icon: Icons.forward_10_rounded,
                      onTap: () => podcast.seekBy(
                        const Duration(seconds: 15),
                      ),
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.spacingLg),
                Row(
                  children: [
                    _PillAction(
                      icon: Icons.favorite_rounded,
                      label: podcast.isFavorite(episode.id)
                          ? 'podcast_favorited'.tr()
                          : 'podcast_favorite'.tr(),
                      isActive: podcast.isFavorite(episode.id),
                      onTap: () => podcast.toggleFavorite(episode),
                      accent: accent,
                      isDark: isDark,
                    ),
                    const SizedBox(width: AppDimens.spacingSm),
                    _PillAction(
                      icon: Icons.speed_rounded,
                      label: '${podcast.playbackSpeed}x',
                      onTap: podcast.cycleSpeed,
                      accent: accent,
                      isDark: isDark,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: podcast.playNext,
                      tooltip: 'podcast_next_episode'.tr(),
                      icon: Icon(
                        Icons.queue_music_rounded,
                        color: MainScreenColors.getTextColor(
                          isDark,
                        ).withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.podcast, required this.accent});

  final PodcastProvider podcast;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: context.read<PlayerProvider>().playerService.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? podcast.isPlaying;
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: IconButton(
            onPressed: podcast.togglePlayPause,
            iconSize: 34,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 28,
      icon: Icon(
        icon,
        color: MainScreenColors.getTextColor(
          isDark,
        ).withValues(alpha: 0.8),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    required this.isDark,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;
  final bool isDark;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.spacingMd,
            vertical: AppDimens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: isDark ? 0.06 : 0.0),
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            border: Border.all(
              color: isActive
                  ? accent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: isDark ? 0.08 : 0.0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppDimens.iconSm,
                color: isActive
                    ? accent
                    : MainScreenColors.getTextColor(
                        isDark,
                      ).withValues(alpha: 0.65),
              ),
              const SizedBox(width: AppDimens.spacingXs),
              Text(
                label,
                style: AppTextStyles.caption(
                  isDarkMode: isDark,
                  color: isActive
                      ? accent
                      : MainScreenColors.getTextColor(
                          isDark,
                        ).withValues(alpha: 0.65),
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

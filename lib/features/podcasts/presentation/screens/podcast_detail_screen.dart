import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../shared/components/app_snackbar.dart';
import '../../data/models/podcast_models.dart';
import '../../data/providers/podcast_provider.dart';
import '../widgets/podcast_player_sheet.dart';
import '../widgets/podcast_widgets.dart';

class PodcastDetailScreen extends StatefulWidget {
  const PodcastDetailScreen({super.key, required this.show});

  final PodcastShow show;

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen> {
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PodcastProvider>().loadShowEpisodes(widget.show);
    });
  }

  Future<void> _playEpisode(PodcastEpisode episode) async {
    final provider = context.read<PodcastProvider>();
    await provider.playEpisode(episode);
    if (!mounted) return;
    PodcastPlayerSheet.show(context);
  }

  Future<void> _playLatest(List<PodcastEpisode> episodes) async {
    if (episodes.isEmpty) {
      AppSnackBar.showInfo(context, 'podcast_no_episodes'.tr());
      return;
    }
    await _playEpisode(episodes.first);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PodcastProvider>();
    final show = provider.showById(widget.show.id) ?? widget.show;
    final episodes = provider.episodesFor(show.id);
    final isLoading = provider.isLoadingEpisodes(show.id);
    final error = provider.episodeError(show.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.paddingSm,
                  AppDimens.spacingSm,
                  AppDimens.paddingSm,
                  0,
                ),
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    _SubscribeButton(
                      isSubscribed: provider.isSubscribed(show.id),
                      onTap: () => provider.toggleSubscription(show),
                    ),
                    const SizedBox(width: AppDimens.spacingXs),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.paddingLg,
                  AppDimens.spacingLg,
                  AppDimens.paddingLg,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PodcastArtwork(
                      imageUrl: show.artworkUrl,
                      size: 136,
                      radius: AppDimens.radiusXxl,
                    ),
                    const SizedBox(width: AppDimens.spacingLg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            show.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleLg(
                              isDarkMode: isDark,
                            ).copyWith(height: 1.2),
                          ),
                          const SizedBox(height: AppDimens.spacingXs),
                          Text(
                            show.displayPublisher,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body2(
                              isDarkMode: isDark,
                              color: MainScreenColors.getTextColor(
                                isDark,
                              ).withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: AppDimens.spacingSm),
                          Wrap(
                            spacing: AppDimens.spacingSm,
                            runSpacing: AppDimens.spacingXs,
                            children: [
                              if (show.genre != null &&
                                  show.genre!.isNotEmpty)
                                _InfoPill(label: show.genre!),
                              if (show.country != null &&
                                  show.country!.isNotEmpty)
                                _InfoPill(
                                  label: show.country!.toUpperCase(),
                                ),
                              if (episodes.isNotEmpty)
                                _InfoPill(
                                  label: 'podcast_episode_count'.tr(
                                    args: ['${episodes.length}'],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppDimens.spacingMd),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: episodes.isEmpty
                                  ? null
                                  : () => _playLatest(episodes),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: AppDimens.iconLg,
                              ),
                              label: Text('podcast_play_latest'.tr()),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.accentColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppDimens.spacingMd,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusPill,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (show.description.trim().isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.paddingLg,
                    AppDimens.spacingXl,
                    AppDimens.paddingLg,
                    0,
                  ),
                  child: LiquidGlass(
                    borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                    tint: MainScreenColors.getSurfaceColor(isDark),
                    opacity: isDark ? 0.25 : 0.6,
                    padding: const EdgeInsets.all(AppDimens.paddingLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'podcast_about'.tr(),
                          style: AppTextStyles.bodyMd(
                            isDarkMode: isDark,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: AppDimens.spacingSm),
                        AnimatedSize(
                          duration: AppDimens.animFast,
                          alignment: Alignment.topCenter,
                          child: Text(
                            show.description,
                            maxLines: _descriptionExpanded ? null : 3,
                            overflow: _descriptionExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: AppTextStyles.body2(
                              isDarkMode: isDark,
                              color: MainScreenColors.getTextColor(
                                isDark,
                              ).withValues(alpha: 0.72),
                            ).copyWith(height: 1.5),
                          ),
                        ),
                        if (show.description.length > 160)
                          GestureDetector(
                            onTap: () => setState(
                              () => _descriptionExpanded = !_descriptionExpanded,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: AppDimens.spacingSm,
                              ),
                              child: Text(
                                _descriptionExpanded
                                    ? 'podcast_show_less'.tr()
                                    : 'podcast_show_more'.tr(),
                                style: AppTextStyles.caption(
                                  isDarkMode: isDark,
                                  color: context.accentColor,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.paddingLg,
                  AppDimens.spacingXl,
                  AppDimens.paddingLg,
                  AppDimens.spacingMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'podcast_latest_episodes'.tr(),
                        style: AppTextStyles.titleSm(isDarkMode: isDark),
                      ),
                    ),
                    if (isLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.accentColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isLoading && episodes.isEmpty)
              const SliverToBoxAdapter(child: _EpisodeSkeleton())
            else if (error != null && episodes.isEmpty)
              SliverToBoxAdapter(
                child: PodcastEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'podcast_load_error'.tr(),
                  subtitle: 'podcast_load_error_body'.tr(),
                  onRetry: () =>
                      provider.loadShowEpisodes(show, force: true),
                ),
              )
            else if (episodes.isEmpty)
              SliverToBoxAdapter(
                child: PodcastEmptyState(
                  icon: Icons.podcasts_rounded,
                  title: 'podcast_no_episodes'.tr(),
                  subtitle: 'podcast_no_episodes_body'.tr(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.paddingLg,
                ),
                sliver: SliverList.builder(
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final isPlaying =
                        provider.isPodcastPlaying &&
                        provider.currentEpisode?.id == episode.id;
                    return PodcastEpisodeTile(
                      episode: episode,
                      isPlaying: isPlaying,
                      isFavorite: provider.isFavorite(episode.id),
                      progress: provider.progressFor(episode.id),
                      onFavorite: () => provider.toggleFavorite(episode),
                      onTap: () => _playEpisode(episode),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppDimens.bottomDockClearance),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: MainScreenColors.getSurfaceColor(
        isDark,
      ).withValues(alpha: isDark ? 0.6 : 0.9),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          color: MainScreenColors.getTextColor(isDark),
          size: AppDimens.iconMdLg,
        ),
      ),
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({
    required this.isSubscribed,
    required this.onTap,
  });

  final bool isSubscribed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        isSubscribed
            ? Icons.check_circle_rounded
            : Icons.add_circle_outline_rounded,
        size: AppDimens.iconSm,
      ),
      label: Text(
        isSubscribed ? 'podcast_subscribed'.tr() : 'podcast_subscribe'.tr(),
      ),
      style: TextButton.styleFrom(
        foregroundColor: context.accentColor,
        textStyle: AppTextStyles.caption(isDarkMode: isDark).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingSmMd,
        vertical: AppDimens.spacingXxs,
      ),
      decoration: BoxDecoration(
        color: MainScreenColors.getSurfaceColor(
          isDark,
        ).withValues(alpha: isDark ? 0.5 : 0.8),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.0),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.finePrint(
          isDarkMode: isDark,
          color: MainScreenColors.getTextColor(
            isDark,
          ).withValues(alpha: 0.62),
        ),
      ),
    );
  }
}

class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.black.withValues(alpha: 0.1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
      child: Column(
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.spacingSm),
            child: Shimmer.fromColors(
              baseColor: base,
              highlightColor: highlight,
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    ),
                  ),
                  const SizedBox(width: AppDimens.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 13, color: base),
                        const SizedBox(height: AppDimens.spacingSm),
                        Container(height: 10, width: 120, color: base),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

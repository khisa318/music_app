import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/podcast_models.dart';
import '../../data/providers/podcast_provider.dart';
import '../widgets/podcast_player_sheet.dart';
import '../widgets/podcast_widgets.dart';
import 'podcast_category_screen.dart';
import 'podcast_detail_screen.dart';
import 'podcast_search_screen.dart';

class PodcastsScreen extends StatefulWidget {
  const PodcastsScreen({super.key});

  @override
  State<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends State<PodcastsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PodcastProvider>().initialize();
    });
  }

  void _openShow(PodcastShow show) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PodcastDetailScreen(show: show)));
  }

  void _openCategory(PodcastCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PodcastCategoryScreen(category: category),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PodcastSearchScreen()));
  }

  Future<void> _playContinue(PodcastListeningItem item) async {
    final provider = context.read<PodcastProvider>();
    await provider.playEpisode(item.episode);
    if (!mounted) return;
    PodcastPlayerSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PodcastProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (provider.isHomeLoading &&
        provider.featuredShows.isEmpty &&
        provider.trendingShows.isEmpty) {
      return const SafeArea(bottom: false, child: PodcastHomeSkeleton());
    }

    if (provider.homeHasError &&
        provider.featuredShows.isEmpty &&
        provider.trendingShows.isEmpty) {
      return SafeArea(
        bottom: false,
        child: PodcastEmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'podcast_load_error'.tr(),
          subtitle: 'podcast_load_error_body'.tr(),
          onRetry: provider.refreshHome,
        ),
      );
    }

    final continueListening = provider.continueListening;
    final categories = PodcastCategory.values;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: provider.refreshHome,
        color: context.accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppDimens.spacingSm),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.paddingLg,
                AppDimens.spacingSm,
                AppDimens.paddingSm,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'podcasts'.tr(),
                          style: AppTextStyles.display(isDarkMode: isDark),
                        ),
                        const SizedBox(height: AppDimens.spacingXxs),
                        Text(
                          'podcasts_subtitle'.tr(),
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
                    onPressed: _openSearch,
                    tooltip: 'podcast_search'.tr(),
                    icon: Icon(
                      Icons.search_rounded,
                      color: MainScreenColors.getTextColor(isDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.spacingLg),

            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.paddingLg,
                ),
                itemCount: categories.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppDimens.spacingSm),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return _CategoryChip(
                    label: category.titleKey.tr(),
                    onTap: () => _openCategory(category),
                  );
                },
              ),
            ),

            if (continueListening.isNotEmpty) ...[
              const SizedBox(height: AppDimens.spacingXl),
              PodcastSectionHeader(title: 'podcast_continue_listening'.tr()),
              const SizedBox(height: AppDimens.spacingMd),
              SizedBox(
                height: 106,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.paddingLg,
                  ),
                  itemCount: continueListening.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppDimens.spacingMd),
                  itemBuilder: (context, index) {
                    final item = continueListening[index];
                    return PodcastContinueCard(
                      item: item,
                      onTap: () => _playContinue(item),
                    );
                  },
                ),
              ),
            ],

            if (provider.featuredShows.isNotEmpty) ...[
              const SizedBox(height: AppDimens.spacingXl),
              PodcastSectionHeader(
                title: 'podcast_made_in_kenya'.tr(),
                actionLabel: 'podcast_see_all'.tr(),
                onAction: () => _openCategory(PodcastCategory.news),
              ),
              const SizedBox(height: AppDimens.spacingMd),
              SizedBox(
                height: 196,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.paddingLg,
                  ),
                  itemCount: provider.featuredShows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppDimens.spacingMd),
                  itemBuilder: (context, index) {
                    final show = provider.featuredShows[index];
                    return PodcastFeaturedCard(
                      show: show,
                      onTap: () => _openShow(show),
                    );
                  },
                ),
              ),
            ],

            if (provider.trendingShows.isNotEmpty) ...[
              const SizedBox(height: AppDimens.spacingXl),
              PodcastSectionHeader(title: 'podcast_trending'.tr()),
              const SizedBox(height: AppDimens.spacingMd),
              _HorizontalShowList(
                shows: provider.trendingShows,
                onTap: _openShow,
              ),
            ],

            const SizedBox(height: AppDimens.spacingXl),
            PodcastSectionHeader(title: 'podcast_browse_categories'.tr()),
            const SizedBox(height: AppDimens.spacingMd),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.paddingLg,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 4 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppDimens.spacingMd,
                      crossAxisSpacing: AppDimens.spacingMd,
                      mainAxisExtent: 96,
                    ),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return PodcastCategoryTile(
                        category: category,
                        index: index,
                        onTap: () => _openCategory(category),
                      );
                    },
                  );
                },
              ),
            ),

            if (provider.subscriptions.isNotEmpty) ...[
              const SizedBox(height: AppDimens.spacingXl),
              PodcastSectionHeader(title: 'podcast_your_shows'.tr()),
              const SizedBox(height: AppDimens.spacingMd),
              _HorizontalShowList(
                shows: provider.subscriptions,
                onTap: _openShow,
              ),
            ],

            if (provider.recentlyUpdatedShows.isNotEmpty) ...[
              const SizedBox(height: AppDimens.spacingXl),
              PodcastSectionHeader(title: 'podcast_recently_updated'.tr()),
              const SizedBox(height: AppDimens.spacingMd),
              _HorizontalShowList(
                shows: provider.recentlyUpdatedShows,
                onTap: _openShow,
              ),
            ],

            if (provider.recommendedShows.isNotEmpty) ...[
              const SizedBox(height: AppDimens.spacingXl),
              PodcastSectionHeader(title: 'podcast_recommended'.tr()),
              const SizedBox(height: AppDimens.spacingMd),
              _HorizontalShowList(
                shows: provider.recommendedShows,
                onTap: _openShow,
              ),
            ],

            const SizedBox(height: AppDimens.bottomDockClearance),
          ],
        ),
      ),
    );
  }
}

class _HorizontalShowList extends StatelessWidget {
  const _HorizontalShowList({required this.shows, required this.onTap});

  final List<PodcastShow> shows;
  final ValueChanged<PodcastShow> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
        itemCount: shows.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppDimens.spacingMd),
        itemBuilder: (context, index) {
          final show = shows[index];
          return PodcastCard(show: show, onTap: () => onTap(show));
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: MainScreenColors.getSurfaceColor(
              isDark,
            ).withValues(alpha: isDark ? 0.55 : 0.9),
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.0),
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.caption(
              isDarkMode: isDark,
              color: MainScreenColors.getTextColor(
                isDark,
              ).withValues(alpha: 0.8),
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

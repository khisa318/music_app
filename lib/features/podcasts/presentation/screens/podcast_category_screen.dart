import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/podcast_models.dart';
import '../../data/providers/podcast_provider.dart';
import '../widgets/podcast_widgets.dart';
import 'podcast_detail_screen.dart';

class PodcastCategoryScreen extends StatefulWidget {
  const PodcastCategoryScreen({super.key, required this.category});

  final PodcastCategory category;

  @override
  State<PodcastCategoryScreen> createState() => _PodcastCategoryScreenState();
}

class _PodcastCategoryScreenState extends State<PodcastCategoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PodcastProvider>().loadCategory(widget.category);
    });
  }

  void _openShow(PodcastShow show) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PodcastDetailScreen(show: show)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PodcastProvider>();
    final shows = provider.showsForCategory(widget.category);
    final isLoading = provider.isCategoryLoading(widget.category);
    final error = provider.categoryError(widget.category);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          widget.category.titleKey.tr(),
          style: AppTextStyles.titleSm(isDarkMode: isDark),
        ),
      ),
      body: isLoading && shows.isEmpty
          ? const _CategorySkeleton()
          : error != null && shows.isEmpty
          ? PodcastEmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'podcast_load_error'.tr(),
              subtitle: 'podcast_load_error_body'.tr(),
              onRetry: () =>
                  provider.loadCategory(widget.category, force: true),
            )
          : shows.isEmpty
          ? PodcastEmptyState(
              icon: Icons.podcasts_rounded,
              title: 'podcast_no_results'.tr(),
              subtitle: 'podcast_no_results_body'.tr(
                args: [widget.category.titleKey.tr()],
              ),
            )
          : RefreshIndicator(
              color: context.accentColor,
              onRefresh: () =>
                  provider.loadCategory(widget.category, force: true),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.paddingLg,
                  AppDimens.spacingMd,
                  AppDimens.paddingLg,
                  AppDimens.spacing4Xl,
                ),
                itemCount: shows.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 176,
                  mainAxisSpacing: AppDimens.spacingLg,
                  crossAxisSpacing: AppDimens.spacingMd,
                  mainAxisExtent: 246,
                ),
                itemBuilder: (context, index) {
                  final show = shows[index];
                  return PodcastCard(
                    show: show,
                    width: 154,
                    onTap: () => _openShow(show),
                  );
                },
              ),
            ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.black.withValues(alpha: 0.1);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: GridView.builder(
        padding: const EdgeInsets.all(AppDimens.paddingLg),
        itemCount: 8,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 176,
          mainAxisSpacing: AppDimens.spacingLg,
          crossAxisSpacing: AppDimens.spacingMd,
          mainAxisExtent: 246,
        ),
        itemBuilder: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.spacingSm),
            Container(
              height: 13,
              width: double.infinity,
              color: base,
            ),
            const SizedBox(height: AppDimens.spacingXs),
            Container(height: 10, width: 100, color: base),
          ],
        ),
      ),
    );
  }
}

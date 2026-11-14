import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/podcast_models.dart';
import '../../data/providers/podcast_provider.dart';
import '../widgets/podcast_widgets.dart';
import 'podcast_detail_screen.dart';

class PodcastSearchScreen extends StatefulWidget {
  const PodcastSearchScreen({super.key});

  @override
  State<PodcastSearchScreen> createState() => _PodcastSearchScreenState();
}

class _PodcastSearchScreenState extends State<PodcastSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      context.read<PodcastProvider>().search(value);
    });
  }

  void _runSearch(String value) {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() => _query = value);
    context.read<PodcastProvider>().search(value);
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    setState(() => _query = '');
    context.read<PodcastProvider>().clearSearch();
  }

  void _openShow(PodcastShow show) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PodcastDetailScreen(show: show)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PodcastProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trimmed = _query.trim();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Container(
          height: 42,
          margin: const EdgeInsets.only(right: AppDimens.paddingLg),
          decoration: BoxDecoration(
            color: MainScreenColors.getSurfaceColor(
              isDark,
            ).withValues(alpha: isDark ? 0.75 : 1),
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.0),
            ),
          ),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _runSearch,
            style: AppTextStyles.bodyMd(isDarkMode: isDark),
            decoration: InputDecoration(
              hintText: 'podcast_search_hint'.tr(),
              hintStyle: AppTextStyles.bodyMd(
                isDarkMode: isDark,
                color: MainScreenColors.getTextColor(
                  isDark,
                ).withValues(alpha: 0.4),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDimens.paddingLg,
                vertical: AppDimens.spacingMd,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: AppDimens.iconMd,
                color: context.accentColor,
              ),
              suffixIcon: trimmed.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clear,
                      icon: const Icon(Icons.close_rounded),
                      iconSize: AppDimens.iconSm,
                    ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 42,
                minHeight: 42,
              ),
            ),
          ),
        ),
      ),
      body: trimmed.isEmpty
          ? _SearchLanding(
              recentSearches: provider.recentSearches,
              onSearch: _runSearch,
              onRemove: provider.removeRecentSearch,
              onClear: provider.clearRecentSearches,
              onCategory: (category) {
                _runSearch(_categoryQuery(category));
              },
            )
          : _SearchResults(
              provider: provider,
              query: trimmed,
              onShow: _openShow,
              onRetry: () => _runSearch(trimmed),
            ),
    );
  }

  String _categoryQuery(PodcastCategory category) {
    switch (category) {
      case PodcastCategory.comedy:
        return 'comedy podcast';
      case PodcastCategory.news:
        return 'news podcast';
      case PodcastCategory.business:
        return 'business podcast';
      case PodcastCategory.technology:
        return 'technology podcast';
      case PodcastCategory.sports:
        return 'sports podcast';
      case PodcastCategory.lifestyle:
        return 'lifestyle podcast';
      case PodcastCategory.relationships:
        return 'relationships podcast';
      case PodcastCategory.trueCrime:
        return 'true crime podcast';
    }
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.provider,
    required this.query,
    required this.onShow,
    required this.onRetry,
  });

  final PodcastProvider provider;
  final String query;
  final ValueChanged<PodcastShow> onShow;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (provider.isSearching && provider.searchResults.isEmpty) {
      return const _SearchSkeleton();
    }

    if (provider.searchError != null && provider.searchResults.isEmpty) {
      final isEmpty =
          provider.searchError == 'empty' || provider.searchError == 'no_match';
      return PodcastEmptyState(
        icon: isEmpty ? Icons.search_off_rounded : Icons.wifi_off_rounded,
        title: isEmpty
            ? 'podcast_no_results'.tr()
            : 'podcast_search_error'.tr(),
        subtitle: isEmpty
            ? 'podcast_no_results_body'.tr(args: [query])
            : 'podcast_load_error_body'.tr(),
        onRetry: isEmpty ? null : onRetry,
      );
    }

    if (provider.searchResults.isEmpty) {
      return PodcastEmptyState(
        icon: Icons.search_off_rounded,
        title: 'podcast_no_results'.tr(),
        subtitle: 'podcast_no_results_body'.tr(args: [query]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(
        top: AppDimens.spacingSm,
        bottom: AppDimens.spacing4Xl,
      ),
      itemCount: provider.searchResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppDimens.spacingXxs),
      itemBuilder: (context, index) {
        final show = provider.searchResults[index];
        return PodcastListTile(
          show: show,
          onTap: () => onShow(show),
          isSubscribed: provider.isSubscribed(show.id),
          onSubscribe: () => provider.toggleSubscription(show),
        );
      },
    );
  }
}

class _SearchLanding extends StatelessWidget {
  const _SearchLanding({
    required this.recentSearches,
    required this.onSearch,
    required this.onRemove,
    required this.onClear,
    required this.onCategory,
  });

  final List<String> recentSearches;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;
  final ValueChanged<PodcastCategory> onCategory;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = MainScreenColors.getTextColor(isDark).withValues(alpha: 0.55);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingXl,
        AppDimens.paddingLg,
        AppDimens.spacing4Xl,
      ),
      children: [
        if (recentSearches.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'podcast_recent_searches'.tr(),
                  style: AppTextStyles.titleSm(isDarkMode: isDark),
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: Text(
                  'podcast_clear'.tr(),
                  style: AppTextStyles.caption(
                    isDarkMode: isDark,
                    color: context.accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.spacingSm),
          Wrap(
            spacing: AppDimens.spacingSm,
            runSpacing: AppDimens.spacingSm,
            children: recentSearches.map((term) {
              return InputChip(
                label: Text(term),
                onPressed: () => onSearch(term),
                onDeleted: () => onRemove(term),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                backgroundColor: MainScreenColors.getSurfaceColor(
                  isDark,
                ).withValues(alpha: isDark ? 0.55 : 0.9),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.0),
                ),
                labelStyle: AppTextStyles.caption(isDarkMode: isDark),
              );
            }).toList(),
          ),
          const SizedBox(height: AppDimens.spacingXxl),
        ],
        Text(
          'podcast_browse_categories'.tr(),
          style: AppTextStyles.titleSm(isDarkMode: isDark),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 620 ? 4 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: PodcastCategory.values.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppDimens.spacingMd,
                crossAxisSpacing: AppDimens.spacingMd,
                mainAxisExtent: 96,
              ),
              itemBuilder: (context, index) {
                final category = PodcastCategory.values[index];
                return PodcastCategoryTile(
                  category: category,
                  index: index,
                  onTap: () => onCategory(category),
                );
              },
            );
          },
        ),
        const SizedBox(height: AppDimens.spacingXxl),
        Row(
          children: [
            Icon(Icons.tips_and_updates_rounded, color: context.accentColor),
            const SizedBox(width: AppDimens.spacingSm),
            Expanded(
              child: Text(
                'podcast_search_tip'.tr(),
                style: AppTextStyles.caption(isDarkMode: isDark, color: muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

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
      child: ListView.separated(
        padding: const EdgeInsets.all(AppDimens.paddingLg),
        itemCount: 8,
        separatorBuilder: (_, _) => const SizedBox(height: AppDimens.spacingMd),
        itemBuilder: (_, _) => Row(
          children: [
            Container(
              width: 64,
              height: 64,
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
                  Container(height: 14, color: base),
                  const SizedBox(height: AppDimens.spacingSm),
                  Container(height: 11, width: 140, color: base),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

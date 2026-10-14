import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';

class _SearchCategory {
  final String label;
  final String query;
  final IconData icon;
  final Color color;

  const _SearchCategory(this.label, this.query, this.icon, this.color);
}

const List<_SearchCategory> _searchCategories = [
  _SearchCategory('Pop', 'pop music', Icons.star_rounded, Color(0xFFFF4FE3)),
  _SearchCategory(
    'Rock',
    'rock music',
    Icons.electric_bolt_rounded,
    Color(0xFFFF6363),
  ),
  _SearchCategory(
    'Hip-Hop',
    'hip hop music',
    Icons.mic_rounded,
    Color(0xFF7A5CFF),
  ),
  _SearchCategory(
    'R&B',
    'rnb music',
    Icons.favorite_rounded,
    Color(0xFFB863FF),
  ),
  _SearchCategory('Jazz', 'jazz music', Icons.piano_rounded, Color(0xFF3F51B5)),
  _SearchCategory(
    'Electronic',
    'electronic music',
    Icons.graphic_eq_rounded,
    Color(0xFF00BCD4),
  ),
  _SearchCategory(
    'Classical',
    'classical music',
    Icons.music_note_rounded,
    Color(0xFFB8860B),
  ),
  _SearchCategory(
    'Country',
    'country music',
    Icons.landscape_rounded,
    Color(0xFF808000),
  ),
  _SearchCategory(
    'Reggae',
    'reggae music',
    Icons.waves_rounded,
    Color(0xFF00A86B),
  ),
  _SearchCategory(
    'K-Pop',
    'kpop music',
    Icons.auto_awesome_rounded,
    Color(0xFFFF6EC7),
  ),
  _SearchCategory(
    'Latin',
    'latin music',
    Icons.local_fire_department_rounded,
    Color(0xFFFF8C42),
  ),
  _SearchCategory(
    'Metal',
    'metal music',
    Icons.bolt_rounded,
    Color(0xFF546E7A),
  ),
  _SearchCategory(
    'Blues',
    'blues music',
    Icons.nightlife_rounded,
    Color(0xFF1976D2),
  ),
  _SearchCategory('Soul', 'soul music', Icons.spa_rounded, Color(0xFF8E24AA)),
  _SearchCategory(
    'Dance',
    'dance music',
    Icons.disc_full_rounded,
    Color(0xFF26C6DA),
  ),
  _SearchCategory(
    'Indie',
    'indie music',
    Icons.headphones_rounded,
    Color(0xFF5C6BC0),
  ),
];

class SearchSuggestionsList extends StatelessWidget {
  final bool isDarkMode;
  final Color accentColor;
  final String searchText;
  final ValueNotifier<List<String>> searchHistoryNotifier;
  final ValueNotifier<List<String>> searchSuggestionsNotifier;
  final ValueNotifier<List<dynamic>> quickSongsNotifier;
  final VoidCallback onInitializeSearchHistory;
  final ValueChanged<String> onSuggestionTapped;
  final ValueChanged<String> onHistoryItemTapped;
  final ValueChanged<String> onHistoryItemRemoved;
  final VoidCallback? onClearAllHistory;
  final ValueChanged<dynamic> onQuickSongTapped;
  final ValueChanged<String> onCategoryTapped;

  const SearchSuggestionsList({
    super.key,
    required this.isDarkMode,
    required this.accentColor,
    required this.searchText,
    required this.searchHistoryNotifier,
    required this.searchSuggestionsNotifier,
    required this.quickSongsNotifier,
    required this.onInitializeSearchHistory,
    required this.onSuggestionTapped,
    required this.onHistoryItemTapped,
    required this.onHistoryItemRemoved,
    this.onClearAllHistory,
    required this.onQuickSongTapped,
    required this.onCategoryTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppDimens.isDesktop(context);
    final maxWidth = isDesktop ? AppDimens.maxContentWidth : double.infinity;

    if (searchText.trim().isEmpty) {
      return _buildSearchHistory(maxWidth);
    }

    return _buildSuggestionsAndQuickResults(maxWidth);
  }

  Widget _buildSearchHistory(double maxWidth) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: searchHistoryNotifier,
      builder: (context, searchHistory, child) {
        if (searchHistory.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => onInitializeSearchHistory(),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: const EdgeInsets.only(
                bottom: AppDimens.bottomDockClearance,
              ),
              children: [
                if (onClearAllHistory != null && searchHistory.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.paddingLg,
                      AppDimens.spacingSm,
                      AppDimens.paddingMd,
                      AppDimens.spacingXxs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'search_history_card_title'.tr(),
                          style: AppTextStyles.subtitle(isDarkMode: isDarkMode)
                              .copyWith(
                                color: MainScreenColors.getTextColor(
                                  isDarkMode,
                                ).withValues(alpha: 0.7),
                                fontWeight: AppTextStyles.weightSemiBold,
                              ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: onClearAllHistory,
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.spacingSm,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          child: Text(
                            'clear'.tr(),
                            style: AppTextStyles.caption(
                              isDarkMode: isDarkMode,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...searchHistory.map(
                  (item) => ListTile(
                    leading: Icon(
                      Icons.history,
                      color: MainScreenColors.getTextColor(
                        isDarkMode,
                      ).withValues(alpha: 0.5),
                    ),
                    title: Text(
                      item,
                      style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: MainScreenColors.getTextColor(
                          isDarkMode,
                        ).withValues(alpha: 0.5),
                      ),
                      onPressed: () => onHistoryItemRemoved(item),
                    ),
                    onTap: () => onHistoryItemTapped(item),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppDimens.paddingLg,
                    searchHistory.isNotEmpty
                        ? AppDimens.spacingXl
                        : AppDimens.spacingSm,
                    AppDimens.paddingLg,
                    AppDimens.spacingXxs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Browse Categories'),
                      const SizedBox(height: AppDimens.spacingSm),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: _searchCategories.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: AppDimens.spacingMd,
                              mainAxisSpacing: AppDimens.spacingMd,
                              childAspectRatio: 2.8,
                            ),
                        itemBuilder: (context, index) =>
                            _buildCategoryTile(_searchCategories[index]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTextStyles.subtitle(isDarkMode: isDarkMode).copyWith(
        color: MainScreenColors.getTextColor(isDarkMode).withValues(alpha: 0.7),
        fontWeight: AppTextStyles.weightSemiBold,
      ),
    );
  }

  Widget _buildCategoryTile(_SearchCategory category) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      onTap: () => onCategoryTapped(category.query),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingMd),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              category.color.withValues(alpha: 0.9),
              category.color.withValues(alpha: 0.55),
            ],
          ),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
        child: Row(
          children: [
            Icon(category.icon, color: Colors.white, size: AppDimens.iconLg),
            const SizedBox(width: AppDimens.spacingMd),
            Expanded(
              child: Text(
                category.label,
                style: AppTextStyles.bodyLg(isDarkMode: isDarkMode).copyWith(
                  color: Colors.white,
                  fontWeight: AppTextStyles.weightSemiBold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsAndQuickResults(double maxWidth) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: searchSuggestionsNotifier,
      builder: (context, searchSuggestions, child) {
        return ValueListenableBuilder<List<dynamic>>(
          valueListenable: quickSongsNotifier,
          builder: (context, quickSongs, child) {
            if (searchSuggestions.isEmpty && quickSongs.isEmpty) {
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Text(
                    'search_hint'.tr(),
                    style: AppTextStyles.bodyMd(isDarkMode: isDarkMode)
                        .copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: 0.5),
                        ),
                  ),
                ),
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: const EdgeInsets.only(
                    bottom: AppDimens.bottomDockClearance,
                  ),
                  children: [
                    ...searchSuggestions.map(
                      (suggestion) => ListTile(
                        leading: Icon(
                          Icons.search,
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: 0.5),
                        ),
                        title: Text(
                          suggestion,
                          style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                        ),
                        onTap: () => onSuggestionTapped(suggestion),
                      ),
                    ),
                    if (quickSongs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.paddingLg,
                        ),
                        child: Text(
                          'Quick Results',
                          style: AppTextStyles.subtitle(isDarkMode: isDarkMode)
                              .copyWith(
                                color: MainScreenColors.getTextColor(
                                  isDarkMode,
                                ).withValues(alpha: 0.7),
                                fontWeight: AppTextStyles.weightSemiBold,
                              ),
                        ),
                      ),
                      ...quickSongs.map(
                        (song) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.paddingLg,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusSm,
                            ),
                            child: CachedNetworkImage(
                              imageUrl: song.thumbnails.first.url,
                              width: AppDimens.shimmerListTile,
                              height: AppDimens.shimmerListTile,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: MainScreenColors.getSurfaceColor(
                                  isDarkMode,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: MainScreenColors.getSurfaceColor(
                                  isDarkMode,
                                ),
                                child: Icon(
                                  Icons.error,
                                  color: MainScreenColors.getTextColor(
                                    isDarkMode,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            song.name,
                            style: AppTextStyles.bodyLg(isDarkMode: isDarkMode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song.artist.name,
                            style: AppTextStyles.body2(isDarkMode: isDarkMode)
                                .copyWith(
                                  color: MainScreenColors.getTextColor(
                                    isDarkMode,
                                  ).withValues(alpha: 0.5),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => onQuickSongTapped(song),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

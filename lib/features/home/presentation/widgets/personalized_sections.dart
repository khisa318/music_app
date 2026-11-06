import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/models/song_model.dart';
import '../../data/providers/personalized_recommendation_provider.dart';
import '../../data/services/home_screen_queue_service.dart';

class PersonalizedSections extends StatelessWidget {
  const PersonalizedSections({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonalizedRecommendationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    // Show loading shimmer on first load
    if (provider.isLoading && provider.sections.isEmpty) {
      return _buildShimmer(context, isDark);
    }

    // Show error state if there's an error and no sections
    if (provider.error != null && provider.sections.isEmpty) {
      return _buildError(context, provider.error!, isDark);
    }

    // Show empty state if no sections (shouldn't happen with defaults)
    if (provider.sections.isEmpty) {
      return _buildEmpty(context, isDark);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: provider.sections.map((section) {
        return _buildSection(context, section, accentColor, colorScheme, isDark);
      }).toList(),
    );
  }

  Widget _buildSection(
    BuildContext context,
    PersonalizedSection section,
    Color accentColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    if (section.songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.spacingXs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: AppTextStyles.titleLg().copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (section.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        section.subtitle,
                        style: AppTextStyles.body2(
                          isDarkMode: isDark,
                          color: colorScheme.onSurface.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (section.seedArtist != null)
                Text(
                  'artist_mix'.tr(args: [section.seedArtist!]),
                  style: AppTextStyles.body2(
                    isDarkMode: isDark,
                    color: colorScheme.onSurface.withValues(alpha: 0.50),
                  ),
                ),
            ],
          ),
        ),

        // Song list
        SizedBox(
          height: AppDimens.shimmerListTile + AppDimens.spacingXxs,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
            itemCount: section.songs.length,
            itemBuilder: (context, index) {
              final song = section.songs[index];
              return _PersonalizedSongCard(
                song: song,
                sectionType: section.type,
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShimmer(BuildContext context, bool isDark) {
    return Column(
      children: List.generate(3, (index) => _shimmerSection(context, isDark)),
    );
  }

  Widget _shimmerSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.spacingXs,
          ),
          child: Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[300],
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            ),
          ),
        ),
        SizedBox(
          height: AppDimens.shimmerListTile + AppDimens.spacingXxs,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
            itemCount: 5,
            itemBuilder: (context, index) => Container(
              width: 220,
              margin: const EdgeInsets.only(right: AppDimens.spacingSm),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[200],
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String error, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.paddingLg),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppDimens.spacingMd),
          Text(
            'failed_to_load_recommendations'.tr(),
            style: AppTextStyles.titleSm(isDarkMode: isDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimens.spacingXs),
          Text(
            error,
            style: AppTextStyles.bodyMd(isDarkMode: isDark).copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.paddingLg),
      child: Column(
        children: [
          Icon(
            Icons.music_note_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppDimens.spacingMd),
          Text(
            'no_recommendations_yet'.tr(),
            style: AppTextStyles.titleSm(isDarkMode: isDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimens.spacingXs),
          Text(
            'start_listening_to_get_personalized'.tr(),
            style: AppTextStyles.bodyMd(isDarkMode: isDark).copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PersonalizedSongCard extends StatelessWidget {
  final SongInfo song;
  final SectionType sectionType;
  final int index;

  const _PersonalizedSongCard({
    required this.song,
    required this.sectionType,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: AppDimens.spacingSm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playSong(context),
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppDimens.spacingXxs),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                // Artwork
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                  child: song.thumbnails.isNotEmpty
                      ? Image.network(
                          song.thumbnails.first.url,
                          width: AppDimens.songTileImage,
                          height: AppDimens.songTileImage,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _placeholderArtwork(isDark),
                        )
                      : _placeholderArtwork(isDark),
                ),

                const SizedBox(width: AppDimens.spacingSm),

                // Song info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        song.name,
                        style: AppTextStyles.bodyMd(isDarkMode: isDark).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artists.map((a) => a.name).join(', '),
                        style: AppTextStyles.body2(
                          isDarkMode: isDark,
                          color: colorScheme.onSurface.withValues(alpha: 0.60),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Play button
                Icon(
                  Icons.play_arrow_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderArtwork(bool isDark) {
    return Container(
      width: AppDimens.songTileImage,
      height: AppDimens.songTileImage,
      color: isDark ? Colors.grey[850] : Colors.grey[300],
      child: Icon(
        Icons.music_note,
        color: isDark ? Colors.grey[600] : Colors.grey[500],
      ),
    );
  }

  void _playSong(BuildContext context) {
    HomeScreenQueueService(context).playSong(
      song,
      'personalized_${sectionType.name}',
    );
  }
}
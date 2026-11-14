import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easy_localization/easy_localization.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/song_model.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../data/providers/personalized_recommendation_provider.dart';
import '../../data/services/home_screen_queue_service.dart';

/// Personalized suggestion shelves rendered above the Speed Dial.
///
/// Each provider section is laid out as a compact grid so a whole shelf is
/// visible without a horizontal swipe. Every shelf, Listen Again included, shows
/// up to nine tracks (three rows of three) with tight gutters so the artwork
/// stays as large as possible.
class PersonalizedSections extends StatelessWidget {
  const PersonalizedSections({super.key});

  static const int _columns = 3;
  static const int _maxTiles = 9;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonalizedRecommendationProvider>();
    final accentColor = context.select((SettingsProvider p) => p.accentColor);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (provider.isLoading && provider.sections.isEmpty) {
      return const SizedBox.shrink();
    }

    if (provider.error != null && provider.sections.isEmpty) {
      return const SizedBox.shrink();
    }

    if (provider.sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.spacingSm,
          ),
          child: Text(
            'personalized_suggestion'.tr(),
            style: AppTextStyles.titleLg(
              isDarkMode: isDark,
              color: accentColor,
            ),
          ),
        ),
        ...provider.sections.map((section) {
          if (section.songs.isEmpty) return const SizedBox.shrink();
          return _PersonalizedSectionBlock(section: section, isDark: isDark);
        }),
      ],
    );
  }
}

class _PersonalizedSectionBlock extends StatelessWidget {
  final PersonalizedSection section;
  final bool isDark;

  const _PersonalizedSectionBlock({
    required this.section,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingMd,
            AppDimens.paddingLg,
            AppDimens.spacingXs,
          ),
          child: Text(
            section.title,
            style: AppTextStyles.titleSm(
              isDarkMode: isDark,
              color: accentColor,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (section.subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.paddingLg,
              0,
              AppDimens.paddingLg,
              AppDimens.spacingXs,
            ),
            child: Text(
              section.subtitle,
              style: AppTextStyles.body2(
                isDarkMode: isDark,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.60),
              ),
            ),
          ),
        _PersonalizedGrid(
          section: section,
          isDark: isDark,
          onPlay: (song) => _playSong(context, song, section.type),
        ),
        const SizedBox(height: AppDimens.spacingSm),
      ],
    );
  }

  void _playSong(BuildContext context, SongInfo song, SectionType type) {
    try {
      HomeScreenQueueService(
        context,
      ).playSong(song, 'personalized_${type.name}');
    } catch (e) {
      debugPrint('Personalized playback failed: $e');
    }
  }
}

class _PersonalizedTile extends StatelessWidget {
  final SongInfo song;
  final bool isDark;
  final VoidCallback onTap;

  const _PersonalizedTile({
    required this.song,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.videoId == song.videoId,
    );
    final accentColor = context.select((SettingsProvider p) => p.accentColor);
    final thumbnailUrl = song.thumbnails.isEmpty
        ? ''
        : song.thumbnails.last.url;
    final artistName = song.artists.isEmpty ? '' : song.artists.first.name;

    return InkWell(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  child: thumbnailUrl.isEmpty
                      ? _thumbnailFallback(context)
                      : CachedNetworkImage(
                          imageUrl: thumbnailUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              _thumbnailFallback(context, showSpinner: true),
                          errorWidget: (context, url, error) =>
                              _thumbnailFallback(context),
                        ),
                ),
                if (isPlaying)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: accentColor,
                        size: AppDimens.iconXl,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.spacingXs),
          Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? accentColor : null,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Text(
            artistName.isEmpty ? 'unknown_artist'.tr() : artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(
              isDarkMode: isDark,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailFallback(BuildContext context, {bool showSpinner = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: showSpinner
            ? SizedBox(
                width: AppDimens.iconMd,
                height: AppDimens.iconMd,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              )
            : Icon(
                Icons.music_note_rounded,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
      ),
    );
  }
}

class _PersonalizedGrid extends StatelessWidget {
  final PersonalizedSection section;
  final bool isDark;
  final ValueChanged<SongInfo> onPlay;

  const _PersonalizedGrid({
    required this.section,
    required this.isDark,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = AppDimens.paddingLg * 2;
        final available = constraints.maxWidth - padding;

        final columns = PersonalizedSections._columns;
        final songs = section.songs
            .take(PersonalizedSections._maxTiles)
            .toList();

        final tileWidth =
            (available - AppDimens.spacingXs * (columns - 1)) / columns;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
          itemCount: songs.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppDimens.spacingXs,
            crossAxisSpacing: AppDimens.spacingXs,
            mainAxisExtent: tileWidth + 48,
          ),
          itemBuilder: (context, index) {
            final song = songs[index];
            return _PersonalizedTile(
              song: song,
              isDark: isDark,
              onTap: () => onPlay(song),
            );
          },
        );
      },
    );
  }
}

// Back-compat aliases for older callers/tests.
class PersonalizedSectionsView extends PersonalizedSections {
  const PersonalizedSectionsView({super.key});
}

class PersonalizedSuggestionSection extends PersonalizedSections {
  const PersonalizedSuggestionSection({super.key});
}

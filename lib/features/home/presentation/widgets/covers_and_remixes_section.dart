import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/song_model.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../../shared/components/app_snackbar.dart';
import '../../data/providers/covers_and_remixes_provider.dart';
import 'home_screen_shimmer.dart';

/// Alternate versions of what the listener has played: covers, remixes,
/// acoustic and live takes.
///
/// YT Music derives the same shelf from recent listening, so this is seeded
/// from local play history rather than a global chart.
class CoversAndRemixesSection extends StatefulWidget {
  const CoversAndRemixesSection({super.key});

  @override
  State<CoversAndRemixesSection> createState() =>
      _CoversAndRemixesSectionState();
}

class _CoversAndRemixesSectionState extends State<CoversAndRemixesSection> {
  bool _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  /// Play history is restored from disk asynchronously during startup, so the
  /// lookup is retried from the build phase instead of only once on mount.
  /// A one-shot read in `initState` almost always saw an empty history and
  /// left the section permanently blank.
  ///
  /// Deferred to after the frame because [CoversAndRemixesProvider.load]
  /// notifies synchronously, and that must not happen during build.
  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted) return;

      final player = context.read<PlayerProvider>();
      if (player.isLoadingLastPlayedSongs) return;

      final history = player.lastPlayedSongs;
      if (history.isEmpty) return;

      context.read<CoversAndRemixesProvider>().load(history);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watching keeps the section in sync while the history is still being
    // restored from disk during startup, and as playback advances the seeds.
    final player = context.watch<PlayerProvider>();
    final provider = context.watch<CoversAndRemixesProvider>();

    if (provider.results.isEmpty &&
        !provider.isLoading &&
        !player.isLoadingLastPlayedSongs &&
        player.lastPlayedSongs.isNotEmpty) {
      _scheduleLoad();
    }

    final accentColor = context.select((SettingsProvider p) => p.accentColor);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (provider.isLoading) {
      return ShimmerLoading.buildShimmerList();
    }

    if (provider.results.isEmpty) {
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'covers_and_remixes'.tr(),
                      style: AppTextStyles.titleLg(
                        isDarkMode: isDarkMode,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingXxs),
                    Text(
                      'covers_and_remixes_subtitle'.tr(),
                      style: AppTextStyles.caption(
                        isDarkMode: isDarkMode,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              _SectionAction(
                icon: Icons.play_arrow_rounded,
                tooltip: 'play_all'.tr(),
                onPressed: () => _play(context, provider.results, 0),
              ),
              const SizedBox(width: AppDimens.spacingSm),
              _SectionAction(
                icon: Icons.shuffle_rounded,
                tooltip: 'shuffle'.tr(),
                onPressed: () => _play(
                  context,
                  provider.results,
                  math.Random().nextInt(provider.results.length),
                ),
              ),
            ],
          ),
        ),
        _CoversList(songs: provider.results, isDarkMode: isDarkMode),
      ],
    );
  }

  static Future<void> _play(
    BuildContext context,
    List<SongInfo> songs,
    int startIndex,
  ) async {
    if (songs.isEmpty) return;

    final playerProvider = context.read<PlayerProvider>();
    final queueProvider = context.read<QueueProvider>();
    final index = startIndex.clamp(0, songs.length - 1);

    try {
      await ContentDetailsService().playSong(
        songs[index],
        playerProvider,
        queueProvider,
        songs,
        playlistId: 'covers_and_remixes',
        playlistName: 'covers_and_remixes'.tr(),
      );
      queueProvider.setQueue(
        songs,
        currentIndex: index,
        playlistId: 'covers_and_remixes',
        playlistName: 'covers_and_remixes'.tr(),
      );
      await queueProvider.saveQueue();
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.showError(context, 'failed_to_play_song_error'.tr());
      debugPrint('Covers/remixes playback failed: $e');
    }
  }
}

class _SectionAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _SectionAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.spacingSm),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: AppDimens.iconLg, color: accentColor),
        ),
      ),
    );
  }
}

class _CoversList extends StatelessWidget {
  final List<SongInfo> songs;
  final bool isDarkMode;

  const _CoversList({required this.songs, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(
          constraints.maxWidth - AppDimens.paddingLg * 2,
          AppDimens.maxContentWidth - AppDimens.paddingLg * 2,
        );
        final columns = math.max(
          1,
          ((available + AppDimens.spacingMd) / (280 + AppDimens.spacingMd))
              .floor(),
        );

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
          itemCount: songs.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppDimens.spacingXs,
            crossAxisSpacing: AppDimens.spacingMd,
            mainAxisExtent: 64,
          ),
          itemBuilder: (context, index) {
            final song = songs[index];

            return _CoversTile(
              song: song,
              isDarkMode: isDarkMode,
              onTap: () =>
                  _CoversAndRemixesSectionState._play(context, songs, index),
            );
          },
        );
      },
    );
  }
}

class _CoversTile extends StatelessWidget {
  final SongInfo song;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _CoversTile({
    required this.song,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Selected here rather than in the grid's `itemBuilder`: a select there
    // would subscribe the whole sliver and rebuild every tile on each change.
    final isPlaying = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.videoId == song.videoId,
    );
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    final artistName = song.artists.isEmpty ? '' : song.artists.first.name;
    final thumbnailUrl = song.thumbnails.isEmpty
        ? ''
        : song.thumbnails.last.url;

    return InkWell(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            child: SizedBox(
              width: 64,
              height: 64,
              child: thumbnailUrl.isEmpty
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppDimens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaying ? accentColor : null,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artistName.isEmpty ? 'unknown_artist'.tr() : artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(
                    isDarkMode: isDarkMode,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (isPlaying)
            Icon(
              Icons.graphic_eq_rounded,
              size: AppDimens.iconMd,
              color: accentColor,
            )
          else
            Icon(
              Icons.play_circle_outline_rounded,
              size: AppDimens.iconMd,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          const SizedBox(width: AppDimens.spacingSm),
        ],
      ),
    );
  }
}

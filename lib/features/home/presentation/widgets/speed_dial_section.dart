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
import '../../data/providers/home_screen_provider.dart';
import 'home_screen_shimmer.dart';

/// YouTube Music's quick-access area.
///
/// Prefers the genuine "Listen again" shelf returned inside the Home browse
/// response, and falls back to local play history when the feed does not carry
/// one — the shelf is account-scoped, so an anonymous or freshly-installed
/// client never receives it.
class SpeedDialSection extends StatelessWidget {
  const SpeedDialSection({super.key});

  static const String _playlistId = 'listen_again';

  /// Upper bound on tiles so the section stays a glanceable strip.
  static const int _maxTiles = 12;

  /// Recent local plays used when the remote shelf is unavailable.
  static const int _maxHistoryTiles = 8;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeScreenProvider>();
    final accentColor = context.select((SettingsProvider p) => p.accentColor);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (provider.isHomeSectionsLoading) {
      return ShimmerLoading.buildShimmerList();
    }

    final songs = _resolveSongs(context, provider);
    if (songs.isEmpty) {
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
                child: Text(
                  'speed_dial'.tr(),
                  style: AppTextStyles.titleLg(
                    isDarkMode: isDarkMode,
                    color: accentColor,
                  ),
                ),
              ),
              _SpeedDialAction(
                icon: Icons.play_arrow_rounded,
                tooltip: 'play_all'.tr(),
                onPressed: () => _playAll(context, songs, 0),
              ),
              const SizedBox(width: AppDimens.spacingSm),
              _SpeedDialAction(
                icon: Icons.shuffle_rounded,
                tooltip: 'shuffle'.tr(),
                onPressed: () => _playAll(
                  context,
                  songs,
                  math.Random().nextInt(songs.length),
                ),
              ),
            ],
          ),
        ),
        _SpeedDialGrid(songs: songs, isDarkMode: isDarkMode),
      ],
    );
  }

  /// Remote shelf first, local play history second.
  ///
  /// Watching [PlayerProvider] keeps the section in sync while the history is
  /// still being restored from disk during startup.
  static List<SongInfo> _resolveSongs(
    BuildContext context,
    HomeScreenProvider provider,
  ) {
    final remote = provider.listenAgainSongs;
    if (remote.isNotEmpty) {
      return remote.length > _maxTiles ? remote.sublist(0, _maxTiles) : remote;
    }

    final history = context.watch<PlayerProvider>().lastPlayedSongs;
    final seen = <String>{};
    final songs = <SongInfo>[];

    for (final entry in history) {
      final song = SongInfo.fromHistoryMap(entry);
      if (song == null || !seen.add(song.videoId)) continue;
      songs.add(song);
      if (songs.length >= _maxHistoryTiles) break;
    }

    return songs;
  }

  static Future<void> _playAll(
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
        playlistId: _playlistId,
        playlistName: 'speed_dial'.tr(),
      );
      queueProvider.setQueue(
        songs,
        currentIndex: index,
        playlistId: _playlistId,
        playlistName: 'speed_dial'.tr(),
      );
      await queueProvider.saveQueue();
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.showError(context, 'failed_to_play_song_error'.tr());
      debugPrint('Speed dial playback failed: $e');
    }
  }
}

class _SpeedDialAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _SpeedDialAction({
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

/// Responsive grid: the column count follows the available width instead of
/// being pinned to 3, so the row stays usable from a 360dp phone up to a
/// desktop window.
class _SpeedDialGrid extends StatelessWidget {
  final List<SongInfo> songs;
  final bool isDarkMode;

  const _SpeedDialGrid({required this.songs, required this.isDarkMode});

  static const double _maxTileWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(
          constraints.maxWidth - AppDimens.paddingLg * 2,
          AppDimens.maxContentWidth - AppDimens.paddingLg * 2,
        );
        final columns = math.max(2, (available / _maxTileWidth).floor());
        // The grid also spends `crossAxisSpacing` between tiles, so the real
        // tile width is narrower than the raw share. Using the raw share made
        // every tile taller than it was wide and stretched the covers.
        final tileWidth =
            (available - AppDimens.spacingMdLg * (columns - 1)) / columns;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
          itemCount: songs.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppDimens.spacingMdLg,
            crossAxisSpacing: AppDimens.spacingMdLg,
            mainAxisExtent: tileWidth + 42,
          ),
          itemBuilder: (context, index) {
            final song = songs[index];

            return _SpeedDialTile(
              song: song,
              isDarkMode: isDarkMode,
              onTap: () => SpeedDialSection._playAll(context, songs, index),
            );
          },
        );
      },
    );
  }
}

class _SpeedDialTile extends StatelessWidget {
  final SongInfo song;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _SpeedDialTile({
    required this.song,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Selected here rather than in the grid's `itemBuilder`: a select there
    // would subscribe the whole sliver and rebuild every tile on each change.
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
          Expanded(
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
              isDarkMode: isDarkMode,
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

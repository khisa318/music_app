import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/favorite_artists_section.dart';
import '../widgets/home_sections.dart';
import '../widgets/speed_dial_section.dart';
import '../widgets/covers_and_remixes_section.dart';
import '../../../../core/providers/favorite_song_provider.dart';
import '../../data/providers/home_screen_provider.dart';
import '../../../../shared/components/song_list_tile.dart';
import '../../../../core/models/song_model.dart';
import '../../data/services/home_screen_queue_service.dart';
import '../../../trending/data/provider/trending_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/components/app_snackbar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FavoriteSongProvider>(
        context,
        listen: false,
      ).loadLikedSongs();
    });
  }

  Future<void> _onRefresh(BuildContext context) async {
    final homeScreenProvider = Provider.of<HomeScreenProvider>(
      context,
      listen: false,
    );

    await homeScreenProvider.refreshData();
  }

  int _selectedIndex = 0;

  // ---------------------------------------------------------------------------
  // TABS
  // ---------------------------------------------------------------------------

  Widget _buildTabs(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    Widget tab(String title, int index) {
      final selected = _selectedIndex == index;

      return GestureDetector(
        onTap: () async {
          setState(() => _selectedIndex = index);

          if (index == 1) {
            final trendingProvider = Provider.of<TrendingProvider>(
              context,
              listen: false,
            );

            final kenya = trendingProvider.countries.first;

            if (trendingProvider.selectedCountry?.playlistId !=
                kenya.playlistId) {
              await trendingProvider.setSelectedCountry(kenya);
            }

            if (trendingProvider.getTrendingSongs(kenya.playlistId).isEmpty) {
              trendingProvider.loadTrendingSongs(kenya.playlistId);
            }
          }

          if (!context.mounted) return;

          if (index == 2) {
            final favoriteProvider = Provider.of<FavoriteSongProvider>(
              context,
              listen: false,
            );

            if (favoriteProvider.likedSongs.isEmpty) {
              favoriteProvider.loadLikedSongs();
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingMd + 4,
            vertical: AppDimens.paddingXs + 2,
          ),
          margin: const EdgeInsets.only(right: AppDimens.spacingSm),
          decoration: BoxDecoration(
            color: selected
                ? accentColor
                : colorScheme.onSurface.withValues(
                    alpha: isDarkMode ? 0.08 : 0.06,
                  ),
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            border: Border.all(
              color: selected
                  ? accentColor
                  : colorScheme.onSurface.withValues(
                      alpha: isDarkMode ? 0.12 : 0.10,
                    ),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: selected ? Colors.white : colorScheme.onSurface,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.paddingXs,
        AppDimens.paddingLg,
        AppDimens.paddingSm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            tab('all'.tr(), 0),
            tab('trending'.tr(), 1),
            tab('favorites'.tr(), 2),
            tab('recently_played'.tr(), 3),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRENDING
  // ---------------------------------------------------------------------------

  List<Widget> _buildTrendingSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    final trendingProvider = Provider.of<TrendingProvider>(context);

    final countryName = trendingProvider.selectedCountry?.name ?? 'Kenya';

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingMd,
            AppDimens.paddingLg,
            AppDimens.paddingSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trending in $countryName',
                style: AppTextStyles.titleSm(
                  isDarkMode: isDarkMode,
                  color: accentColor,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: AppDimens.spacingXs),

              Text(
                'The songs people are listening to right now',
                style: AppTextStyles.body2(
                  isDarkMode: isDarkMode,
                  color: colorScheme.onSurface.withValues(alpha: 0.60),
                ),
              ),
            ],
          ),
        ),
      ),

      _buildTrendingSliverList(context),
    ];
  }

  Widget _buildTrendingSliverList(BuildContext context) {
    final trendingProvider = Provider.of<TrendingProvider>(context);

    final playlistId = trendingProvider.selectedCountry?.playlistId;

    if (playlistId == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final songs = trendingProvider.getTrendingSongs(playlistId);

    final isLoading = trendingProvider.isLoading(playlistId);

    if (isLoading && songs.isEmpty) {
      final accentColor = context.select((SettingsProvider p) => p.accentColor);

      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingLg),
          child: Center(child: CircularProgressIndicator(color: accentColor)),
        ),
      );
    }

    if (songs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingLg),
          child: Center(
            child: Text(
              'No trending songs found.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final song = songs[index];

        return Builder(
          builder: (itemContext) {
            final isPlaying = itemContext.select<PlayerProvider, bool>(
              (p) => p.currentSong?.videoId == song.videoId,
            );

            final isDark = Theme.of(context).brightness == Brightness.dark;

            final accentColor = itemContext.select(
              (SettingsProvider p) => p.accentColor,
            );

            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: AppDimens.paddingLg,
                vertical: AppDimens.spacingXxs,
              ),
              decoration: BoxDecoration(
                color: isPlaying
                    ? accentColor.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
              child: SongListTile(
                song: song,
                onPlay: () {
                  final playlistName =
                      '${trendingProvider.selectedCountry?.name ?? 'Kenya'} Trending';

                  trendingProvider.playSong(
                    song,
                    context,
                    playlistId,
                    playlistName: playlistName,
                  );
                },
                isDarkMode: isDark,
                isPlaying: isPlaying,
              ),
            );
          },
        );
      }, childCount: songs.length),
    );
  }

  // ---------------------------------------------------------------------------
  // MAP SONG LIST
  // ---------------------------------------------------------------------------

  Widget _buildMapSliverList(
    BuildContext context,
    List<Map<String, dynamic>> list,
    String playlistType,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (list.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingLg),
          child: Center(
            child: Text(
              'no_songs_found'.tr(),
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final songMap = list[index];

        final songInfo = SongInfo(
          videoId: songMap['id'] ?? songMap['videoId'] ?? '',
          name: songMap['title'] ?? songMap['name'] ?? '',
          artists:
              (songMap['artists'] as List<dynamic>?)
                  ?.map(
                    (a) => Artist(
                      name: (a is Map)
                          ? (a['name'] ?? '') as String
                          : a.toString(),
                      id: (a is Map) ? (a['id'] ?? '') as String : '',
                    ),
                  )
                  .toList() ??
              [
                Artist(
                  name: songMap['artist'] ?? '',
                  id: songMap['artistId'] ?? '',
                ),
              ],
          thumbnails: [
            Thumbnail(url: songMap['thumbnail'] ?? '', width: 480, height: 360),
          ],
          duration: Duration(seconds: songMap['duration'] ?? 0),
        );

        return Builder(
          builder: (itemContext) {
            final isPlaying = itemContext.select<PlayerProvider, bool>(
              (p) => p.currentSong?.videoId == songInfo.videoId,
            );

            final isDark = Theme.of(context).brightness == Brightness.dark;

            final accentColor = itemContext.select(
              (SettingsProvider p) => p.accentColor,
            );

            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: AppDimens.paddingLg,
                vertical: AppDimens.spacingXxs,
              ),
              decoration: BoxDecoration(
                color: isPlaying
                    ? accentColor.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
              child: SongListTile(
                song: songInfo,
                onPlay: () async {
                  try {
                    await HomeScreenQueueService(
                      context,
                    ).playAll(playlistType, currentIndex: index);

                    if (!context.mounted) return;
                  } catch (e) {
                    debugPrint('Error playing song: $e');

                    AppSnackBar.showError(
                      context,
                      'failed_to_play_song_error'.tr(),
                    );
                  }
                },
                isDarkMode: isDark,
                isPlaying: isPlaying,
              ),
            );
          },
        );
      }, childCount: list.length),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    return RefreshIndicator(
      color: accentColor,
      onRefresh: () => _onRefresh(context),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildTabs(context)),

          if (_selectedIndex == 0) ...[
            const SliverToBoxAdapter(child: SpeedDialSection()),

            const SliverToBoxAdapter(child: CoversAndRemixesSection()),

            SliverToBoxAdapter(child: FavoriteArtistsSection()),

            SliverToBoxAdapter(child: HomeSections()),
          ] else if (_selectedIndex == 1) ...[
            ..._buildTrendingSlivers(context),
          ] else if (_selectedIndex == 2) ...[
            _buildMapSliverList(
              context,
              Provider.of<FavoriteSongProvider>(context).likedSongs,
              'liked_songs',
            ),
          ] else ...[
            _buildMapSliverList(
              context,
              Provider.of<PlayerProvider>(context).lastPlayedSongs,
              'recently_played',
            ),
          ],

          const SliverToBoxAdapter(
            child: SizedBox(height: AppDimens.paddingXl),
          ),
        ],
      ),
    );
  }
}

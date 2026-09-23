import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../widgets/favorite_artists_section.dart';
import '../widgets/home_sections.dart';
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
  // COVERS AND REMIXES
  // ---------------------------------------------------------------------------

  Widget _buildForYouCarousel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final trendingProvider = context.watch<TrendingProvider>();

    final songs = trendingProvider.getTrendingSongs(
      TrendingProvider.top100GlobalPlaylistId,
    );

    if (songs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (trendingProvider
            .getTrendingSongs(TrendingProvider.top100GlobalPlaylistId)
            .isEmpty) {
          trendingProvider.loadTrendingSongs(
            TrendingProvider.top100GlobalPlaylistId,
          );
        }
      });

      return const SizedBox.shrink();
    }

    final displaySongs = songs.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingSm,
            AppDimens.paddingLg,
            AppDimens.spacingSm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Covers and remixes',
                  style: AppTextStyles.titleSm(
                    isDarkMode: isDarkMode,
                    color: colorScheme.onSurface,
                  ).copyWith(fontWeight: FontWeight.bold, fontSize: 24),
                ),
              ),

              OutlinedButton(
                onPressed: () {
                  if (displaySongs.isEmpty) return;

                  context.read<TrendingProvider>().playSong(
                    displaySongs.first,
                    context,
                    TrendingProvider.top100GlobalPlaylistId,
                    playlistName: 'Covers and remixes',
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onSurface,
                  side: BorderSide(
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
                  ),
                ),
                child: const Text('Play all'),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
          child: Column(
            children: displaySongs.map((song) {
              final artistName = song.artists.isNotEmpty
                  ? song.artists.map((artist) => artist.name).join(', ')
                  : 'Unknown Artist';

              final thumbnail = song.thumbnails.isNotEmpty
                  ? song.thumbnails.last.url
                  : '';

              return InkWell(
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                onTap: () {
                  context.read<TrendingProvider>().playSong(
                    song,
                    context,
                    TrendingProvider.top100GlobalPlaylistId,
                    playlistName: 'Covers and remixes',
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                        child: _buildPopularThumbnail(thumbnail, size: 64),
                      ),

                      const SizedBox(width: AppDimens.spacingMd),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.name,
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                            const SizedBox(height: 3),

                            Text(
                              '$artistName • music',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.58,
                                ),
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: colorScheme.onSurface.withValues(alpha: 0.70),
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SPEED DIAL
  // ---------------------------------------------------------------------------

  Widget _buildPopularTracks(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final playerProvider = context.watch<PlayerProvider>();

    final songs = playerProvider.lastPlayedSongs;

    if (songs.isEmpty) {
      return const SizedBox.shrink();
    }

    final displaySongs = songs.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.spacingMd,
            AppDimens.paddingLg,
            AppDimens.spacingSm,
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ARMSTRONG KHISA',
                    style: AppTextStyles.caption(isDarkMode: isDarkMode)
                        .copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.58),
                        ),
                  ),

                  Text(
                    'Speed dial',
                    style: AppTextStyles.titleLg(
                      isDarkMode: isDarkMode,
                      color: colorScheme.onSurface,
                    ).copyWith(fontWeight: FontWeight.w900, fontSize: 28),
                  ),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displaySongs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              final songMap = displaySongs[index];

              final title = songMap['title'] ?? 'Unknown';

              final artist =
                  (songMap['artists'] != null &&
                      (songMap['artists'] as List).isNotEmpty)
                  ? ((songMap['artists'] as List).first is Map
                        ? (songMap['artists'] as List).first['name'] ?? ''
                        : (songMap['artists'] as List).first.toString())
                  : (songMap['artist'] ?? 'Unknown Artist');

              final thumbnail = songMap['thumbnail'] ?? '';

              return InkWell(
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                onTap: () async {
                  try {
                    await HomeScreenQueueService(
                      context,
                    ).playAndQueueSongs(songMap);
                  } catch (e) {
                    debugPrint('Speed Dial radio error: $e');
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                        child: SizedBox.expand(
                          child: _buildPopularThumbnail(thumbnail, size: 160),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      title,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    Text(
                      artist,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.58),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // THUMBNAILS
  // ---------------------------------------------------------------------------

  Widget _buildPopularThumbnail(String url, {double size = 48}) {
    final colorScheme = Theme.of(context).colorScheme;

    final placeholderColor = colorScheme.surfaceContainerHighest;

    final iconColor = colorScheme.onSurface.withValues(alpha: 0.55);

    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: placeholderColor,
        child: Icon(Icons.music_note, color: iconColor, size: 24),
      );
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) {
          return Container(
            width: size,
            height: size,
            color: placeholderColor,
            child: Icon(Icons.music_note, color: iconColor, size: 24),
          );
        },
        errorWidget: (context, url, error) {
          return Container(
            width: size,
            height: size,
            color: placeholderColor,
            child: Icon(Icons.broken_image, color: iconColor, size: 24),
          );
        },
      );
    }

    try {
      final file = url.startsWith('file://')
          ? File.fromUri(Uri.parse(url))
          : File(url);

      if (file.existsSync()) {
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: size,
              height: size,
              color: placeholderColor,
              child: Icon(Icons.music_note, color: iconColor, size: 24),
            );
          },
        );
      }
    } catch (_) {}

    return Container(
      width: size,
      height: size,
      color: placeholderColor,
      child: Icon(Icons.music_note, color: iconColor, size: 24),
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
            SliverToBoxAdapter(child: _buildPopularTracks(context)),

            SliverToBoxAdapter(child: _buildForYouCarousel(context)),

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

import 'dart:math';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../widgets/stat_section.dart';
import '../widgets/favorite_artists_section.dart';
import '../widgets/home_sections.dart';
import '../widgets/last_played_section.dart';
import '../widgets/liked_songs_section.dart';
import '../widgets/recent_playlists_section.dart';
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
import '../../../search/presentation/screens/search_screen.dart';

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
  int _trendingSubIndex = 0;

  void _showCountrySelectionDialog(BuildContext context) {
    final trendingProvider = Provider.of<TrendingProvider>(
      context,
      listen: false,
    );
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final accentColor = settingsProvider.accentColor;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    int selectedIndex = -1;
    if (trendingProvider.selectedCountry != null) {
      selectedIndex = trendingProvider.countries.indexWhere(
        (country) => country.name == trendingProvider.selectedCountry!.name,
      );
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        final ScrollController scrollController = ScrollController();

        if (selectedIndex != -1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              const double itemHeight = AppDimens.shimmerListTile;
              final double targetPosition = selectedIndex * itemHeight;
              final double maxScrollExtent =
                  scrollController.position.maxScrollExtent;
              final double viewportHeight =
                  scrollController.position.viewportDimension;

              double scrollToPosition =
                  targetPosition - (viewportHeight / 2) + (itemHeight / 2);

              scrollToPosition = scrollToPosition.clamp(0.0, maxScrollExtent);

              scrollController.animateTo(
                scrollToPosition,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final maxDialogWidth = min(
              AppDimens.breakpointWideScreen,
              screenWidth * 0.85,
            );
            final maxDialogHeight = screenHeight * 0.7;

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxDialogWidth,
                  maxHeight: maxDialogHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppDimens.paddingXl),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppDimens.radiusXxl),
                            topRight: Radius.circular(AppDimens.radiusXxl),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.public,
                              color: accentColor,
                              size: AppDimens.iconLg,
                            ),
                            const SizedBox(width: AppDimens.spacingMd),
                            Expanded(
                              child: Text(
                                'Select Country'.tr(),
                                style: AppTextStyles.titleSm(
                                  isDarkMode: isDarkMode,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                padding: const EdgeInsets.all(
                                  AppDimens.paddingXs,
                                ),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusSm,
                                  ),
                                ),
                                child: Icon(
                                  Icons.close,
                                  color: isDarkMode
                                      ? Colors.white70
                                      : Colors.black54,
                                  size: AppDimens.iconMd,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SizedBox(
                          height: maxDialogHeight - 80,
                          child: ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppDimens.spacingSm,
                            ),
                            itemCount: trendingProvider.countries.length,
                            itemBuilder: (BuildContext context, int index) {
                              final country = trendingProvider.countries[index];
                              final isSelected =
                                  trendingProvider.selectedCountry?.name ==
                                  country.name;

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: AppDimens.paddingMd,
                                  vertical: AppDimens.spacingXxs,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentColor.withValues(alpha: 0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusLg,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppDimens.paddingLg,
                                    vertical: AppDimens.paddingXs,
                                  ),
                                  leading: Container(
                                    width: AppDimens.thumbnailMini,
                                    height: AppDimens.thumbnailMini,
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? Colors.grey[800]
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(
                                        AppDimens.radiusMd,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        country.flag,
                                        style: const TextStyle(
                                          fontSize: AppTextStyles.fontSizeBody,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    country.name,
                                    style:
                                        AppTextStyles.subtitle(
                                          isDarkMode: isDarkMode,
                                          color: isSelected
                                              ? accentColor
                                              : isDarkMode
                                              ? Colors.white
                                              : Colors.black,
                                        ).copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: accentColor,
                                          size: AppDimens.iconLg,
                                        )
                                      : null,
                                  onTap: () {
                                    trendingProvider.setSelectedCountry(
                                      country,
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimens.spacingSm),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final accentColor = context.select((SettingsProvider p) => p.accentColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.paddingSm,
        AppDimens.paddingLg,
        AppDimens.paddingXs,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(
              'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100',
            ),
          ),
          const SizedBox(width: AppDimens.spacingMd),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Good Morning',
                style: AppTextStyles.caption(
                  isDarkMode: isDarkMode,
                ).copyWith(color: Colors.white.withValues(alpha: 0.6)),
              ),
              Text(
                'Armstrong',
                style: AppTextStyles.titleSm(
                  isDarkMode: isDarkMode,
                  color: Colors.white,
                ),
              ),
            ],
          ),
const Spacer(),
        ],
      ),
    );
  }

  Widget _buildCircleIconBtn(
    IconData icon,
    Color accentColor,
    bool isDarkMode,
  ) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: () {},
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
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

            if (_trendingSubIndex == 0) {
              if (trendingProvider.selectedCountry != null) {
                final pid = trendingProvider.selectedCountry!.playlistId;
                if (trendingProvider.getTrendingSongs(pid).isEmpty) {
                  trendingProvider.loadTrendingSongs(pid);
                }
              } else {
                if (trendingProvider
                    .getTrendingSongs(TrendingProvider.top100GlobalPlaylistId)
                    .isEmpty) {
                  trendingProvider.loadTrendingSongs(
                    TrendingProvider.top100GlobalPlaylistId,
                  );
                }
              }
            } else {
              if (trendingProvider
                  .getTrendingSongs(TrendingProvider.top100GlobalPlaylistId)
                  .isEmpty) {
                trendingProvider.loadTrendingSongs(
                  TrendingProvider.top100GlobalPlaylistId,
                );
              }
            }
          }

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
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            border: Border.all(
              color: selected
                  ? accentColor
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white,
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

  // --- FOR YOU CAROUSEL (uses real data from TrendingProvider) ---
  Widget _buildForYouCarousel(BuildContext context) {
    final trendingProvider = context.watch<TrendingProvider>();
    final songs = trendingProvider.getTrendingSongs(
      TrendingProvider.top100GlobalPlaylistId,
    );

    // If no trending data loaded yet, trigger loading
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

    final displaySongs = songs.take(10).toList();

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
          child: Text(
            'For You',
            style: AppTextStyles.titleSm(
              isDarkMode: true,
              color: Colors.white,
            ).copyWith(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: AppDimens.paddingLg),
            itemCount: displaySongs.length,
            itemBuilder: (context, index) {
              final song = displaySongs[index];
              return _ForYouCard(song: song);
            },
          ),
        ),
      ],
    );
  }

  // --- POPULAR TRACKS (uses real data from PlayerProvider / FavoriteSongProvider) ---
  Widget _buildPopularTracks(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final songs = playerProvider.lastPlayedSongs;

    if (songs.isEmpty) {
      return const SizedBox.shrink();
    }

    final displaySongs = songs.take(5).toList();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Popular Tracks',
                style: AppTextStyles.titleSm(
                  isDarkMode: true,
                  color: Colors.white,
                ).copyWith(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                'See All',
                style: AppTextStyles.caption(
                  isDarkMode: true,
                ).copyWith(color: const Color(0xFFC042FF)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
          child: Column(
            children: displaySongs.map((songMap) {
              final title = songMap['title'] ?? 'Unknown';
              final artist =
                  (songMap['artists'] != null &&
                      (songMap['artists'] as List).isNotEmpty)
                  ? ((songMap['artists'] as List).first is Map
                        ? (songMap['artists'] as List).first['name'] ?? ''
                        : (songMap['artists'] as List).first.toString())
                  : (songMap['artist'] ?? 'Unknown Artist');
              final thumbnail = songMap['thumbnail'] ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildPopularThumbnail(thumbnail),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            artist,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPopularThumbnail(String url) {
    if (url.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        color: Colors.grey[800],
        child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
      );
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 48,
          height: 48,
          color: Colors.grey[800],
          child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
        ),
        errorWidget: (context, url, error) => Container(
          width: 48,
          height: 48,
          color: Colors.grey[800],
          child: const Icon(
            Icons.broken_image,
            color: Colors.white54,
            size: 24,
          ),
        ),
      );
    }
    try {
      final file = url.startsWith('file://')
          ? File.fromUri(Uri.parse(url))
          : File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 48,
            height: 48,
            color: Colors.grey[800],
            child: const Icon(
              Icons.music_note,
              color: Colors.white54,
              size: 24,
            ),
          ),
        );
      }
    } catch (_) {}
    return Container(
      width: 48,
      height: 48,
      color: Colors.grey[800],
      child: const Icon(Icons.music_note, color: Colors.white54, size: 24),
    );
  }

  List<Widget> _buildTrendingSlivers(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final accentColor = context.select((SettingsProvider p) => p.accentColor);
    final trendingProvider = Provider.of<TrendingProvider>(context);

    Widget subTab(String title, int index, {VoidCallback? onLongPress}) {
      final selected = _trendingSubIndex == index;
      return GestureDetector(
        onTap: () {
          setState(() => _trendingSubIndex = index);

          if (index == 0) {
            if (trendingProvider.selectedCountry == null ||
                (selected && index == 0)) {
              _showCountrySelectionDialog(context);
            } else {
              if (trendingProvider
                  .getTrendingSongs(
                    trendingProvider.selectedCountry!.playlistId,
                  )
                  .isEmpty) {
                trendingProvider.loadTrendingSongs(
                  trendingProvider.selectedCountry!.playlistId,
                );
              }
            }
          } else if (index == 1) {
            if (trendingProvider
                .getTrendingSongs(TrendingProvider.top100GlobalPlaylistId)
                .isEmpty) {
              trendingProvider.loadTrendingSongs(
                TrendingProvider.top100GlobalPlaylistId,
              );
            }
          }
        },
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingMd,
            vertical: AppDimens.paddingXs,
          ),
          margin: const EdgeInsets.only(right: AppDimens.spacingSm),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: 0.25)
                  : (isDarkMode ? Colors.white10 : Colors.black12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style:
                    AppTextStyles.bodyMd(
                      isDarkMode: isDarkMode,
                      color: selected ? accentColor : null,
                    ).copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
              if (index == 0) ...[
                const SizedBox(width: AppDimens.spacingXs),
                Icon(
                  Icons.arrow_drop_down,
                  color: selected
                      ? accentColor
                      : (isDarkMode ? Colors.white70 : Colors.black54),
                  size: 16,
                ),
              ],
            ],
          ),
        ),
      );
    }

    String countryTitle = 'Country';
    if (trendingProvider.selectedCountry != null) {
      countryTitle =
          '${trendingProvider.selectedCountry!.flag} ${trendingProvider.selectedCountry!.name}';
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.paddingSm,
          ),
          child: Row(children: [subTab(countryTitle, 0), subTab('Global', 1)]),
        ),
      ),
      _buildTrendingSliverList(context),
    ];
  }

  Widget _buildTrendingSliverList(BuildContext context) {
    final trendingProvider = Provider.of<TrendingProvider>(context);

    String playlistId;
    if (_trendingSubIndex == 0) {
      if (trendingProvider.selectedCountry == null) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingLg),
            child: Center(
              child: Column(
                children: [
                  Text('No country selected.'),
                  TextButton(
                    onPressed: () => _showCountrySelectionDialog(context),
                    child: Text('Select Country'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      playlistId = trendingProvider.selectedCountry!.playlistId;
    } else {
      playlistId = TrendingProvider.top100GlobalPlaylistId;
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
          child: Center(child: Text('No trending songs found.')),
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
                  final playlistName = _trendingSubIndex == 0
                      ? (trendingProvider.selectedCountry != null
                            ? '${trendingProvider.selectedCountry!.name} Trending'
                            : 'Country Trending')
                      : 'Global Trending';

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

  Widget _buildMapSliverList(
    BuildContext context,
    List<Map<String, dynamic>> list,
    String playlistType,
  ) {
    if (list.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingLg),
          child: Center(child: Text('no_songs_found'.tr())),
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
                  } catch (e) {
                    print('Error playing song: $e');
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
          // Top Header with avatar, greeting, icons
          SliverToBoxAdapter(child: _buildTopHeader(context)),
          // Tab pills
          SliverToBoxAdapter(child: _buildTabs(context)),
          if (_selectedIndex == 0) ...[
            // "For You" carousel at top
            SliverToBoxAdapter(child: _buildForYouCarousel(context)),
            // "Popular Tracks" section
            SliverToBoxAdapter(child: _buildPopularTracks(context)),
            // Existing sections
            SliverToBoxAdapter(child: RecentPlaylistsSection()),
            SliverToBoxAdapter(child: StatsSection()),
            SliverToBoxAdapter(child: LastPlayedSection()),
            SliverToBoxAdapter(child: LikedSongsSection()),
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
          SliverToBoxAdapter(child: SizedBox(height: AppDimens.paddingXl)),
        ],
      ),
    );
  }
}

// --- FOR YOU CARD (standalone widget for carousel) ---
class _ForYouCard extends StatelessWidget {
  final SongInfo song;

  const _ForYouCard({required this.song});

  @override
  Widget build(BuildContext context) {
    final thumbnail = song.thumbnails.isNotEmpty
        ? song.thumbnails.last.url
        : '';
    final artistName = song.artists.isNotEmpty
        ? song.artists.map((a) => a.name).join(', ')
        : 'Unknown Artist';

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onTap: () {
          // Play this song
          context.read<TrendingProvider>().playSong(
            song,
            context,
            TrendingProvider.top100GlobalPlaylistId,
            playlistName: 'For You',
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: thumbnail.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: thumbnail,
                      width: 140,
                      height: 130,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 140,
                        height: 130,
                        color: Colors.grey[850],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 140,
                        height: 130,
                        color: Colors.grey[850],
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white54,
                        ),
                      ),
                    )
                  : Container(
                      width: 140,
                      height: 130,
                      color: Colors.grey[850],
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              song.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              artistName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

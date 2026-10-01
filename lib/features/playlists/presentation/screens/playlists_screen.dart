import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/models/song_model.dart';
import '../../../../core/services/content_details_service.dart';

import '../../data/providers/playlist_album_library_provider.dart';

import '../../../library/presentation/widgets/library_dense_row.dart';
import '../../../playlist_album_content/presentation/screens/playlist_album_content_screen.dart';
import '../widgets/create_playlist_bottomsheet.dart';
import 'playlists_detail_screen.dart';

import '../../../../shared/components/app_empty_state.dart';
import '../../../../shared/components/app_snackbar.dart';

/// One row in the merged, dense playlist list.
class _PlaylistDenseItem {
  final String title;
  final String subtitle;
  final String thumbnail;
  final bool isCreated;
  final Map<String, dynamic> source;

  const _PlaylistDenseItem({
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.isCreated,
    required this.source,
  });
}

class PlaylistScreen extends StatefulWidget {
  /// Renders created playlists, saved playlists and saved albums as a single
  /// flat list instead of the nested Created/Saved tabs.
  final bool dense;

  const PlaylistScreen({super.key, this.dense = false});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  String _savedContentFilter = 'Playlists';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
      }
    });
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    if (!mounted) return;

    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );

    try {
      await provider.loadAll();

      if (!mounted) return;

      await provider.loadCreatedPlaylistsWithThumbnails();
    } catch (e) {
      debugPrint('Error loading playlist data: $e');
    }
  }

  // ============================================================
  // CREATE PLAYLIST
  // ============================================================

  Future<void> _createNewPlaylist() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const CreatePlaylistBottomSheet();
      },
    );

    if (!mounted) return;

    if (result == true) {
      final provider = Provider.of<PlaylistAlbumLibraryProvider>(
        context,
        listen: false,
      );

      await provider.loadCreatedPlaylistsWithThumbnails();
    }
  }

  // ============================================================
  // DELETE PLAYLIST
  // ============================================================

  Future<void> _deletePlaylist(Map<String, dynamic> playlist) async {
    final name = playlist['name']?.toString();

    if (name == null || name.isEmpty) {
      return;
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Delete playlist?'),
          content: Text('Are you sure you want to delete "$name"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );

    try {
      await provider.deleteCreatedPlaylist(name);

      if (!mounted) return;

      await provider.loadCreatedPlaylistsWithThumbnails();

      if (!mounted) return;

      AppSnackBar.showSuccess(context, 'Playlist deleted');
    } catch (e) {
      debugPrint('Error deleting playlist: $e');

      if (!mounted) return;

      AppSnackBar.showError(context, 'Error deleting playlist');
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final settingsProvider = Provider.of<SettingsProvider>(context);

    final accentColor = settingsProvider.accentColor;

    final screenWidth = MediaQuery.of(context).size.width;

    final isDesktopLayout = screenWidth >= 900;

    // IMPORTANT:
    //
    // DefaultTabController is only needed by the mobile layout.
    // The desktop layout uses two independent panels and does not
    // contain a TabBar/TabBarView.
    //
    // Keeping the controller out of the desktop tree also avoids
    // unnecessary ticker/controller lifecycle work when this screen
    // is hosted inside PersistentTabView.

    return Scaffold(
      backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
      body: SafeArea(
        bottom: false,
        child: isDesktopLayout
            ? _buildDesktopLayout(isDarkMode, accentColor, settingsProvider)
            : DefaultTabController(
                length: 2,
                child: _buildMobileLayout(
                  isDarkMode,
                  accentColor,
                  settingsProvider,
                ),
              ),
      ),
    );
  }

  // ============================================================
  // MOBILE
  // ============================================================

  Widget _buildMobileLayout(
    bool isDarkMode,
    Color accentColor,
    SettingsProvider settingsProvider,
  ) {
    if (widget.dense) {
      return _buildDenseMergedList(isDarkMode, accentColor);
    }

    return Column(
      children: [
        const SizedBox(height: 8),

        _buildFriendlyTabBar(isDarkMode, accentColor),

        Expanded(
          child: TabBarView(
            physics: const BouncingScrollPhysics(),
            children: [
              _buildCreatedTab(isDarkMode, accentColor, settingsProvider),
              _buildSavedTab(isDarkMode, accentColor, settingsProvider),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MOBILE TABS
  // ============================================================

  Widget _buildFriendlyTabBar(bool isDarkMode, Color accentColor) {
    final backgroundColor = MainScreenColors.getSurfaceColor(isDarkMode);

    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: textColor.withValues(alpha: 0.05)),
      ),
      child: TabBar(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: Colors.black,
        unselectedLabelColor: textColor.withValues(alpha: 0.65),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(
            height: 48,
            icon: Icon(Icons.queue_music_rounded, size: 19),
            text: 'Playlists',
          ),
          Tab(
            height: 48,
            icon: Icon(Icons.bookmark_rounded, size: 19),
            text: 'Saved',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DESKTOP
  // ============================================================

  Widget _buildDesktopLayout(
    bool isDarkMode,
    Color accentColor,
    SettingsProvider settingsProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildDesktopPanel(
              title: 'Playlists',
              subtitle: 'Your created playlists',
              icon: Icons.queue_music_rounded,
              isDarkMode: isDarkMode,
              accentColor: accentColor,
              child: _buildCreatedTab(
                isDarkMode,
                accentColor,
                settingsProvider,
              ),
            ),
          ),

          const SizedBox(width: 18),

          Expanded(
            child: _buildDesktopPanel(
              title: 'Saved',
              subtitle: 'Saved playlists and albums',
              icon: Icons.bookmark_rounded,
              isDarkMode: isDarkMode,
              accentColor: accentColor,
              child: _buildSavedTab(isDarkMode, accentColor, settingsProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDarkMode,
    required Color accentColor,
    required Widget child,
  }) {
    final surfaceColor = MainScreenColors.getSurfaceColor(isDarkMode);

    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accentColor, size: 21),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        subtitle,
                        style: AppTextStyles.caption(
                          isDarkMode: isDarkMode,
                          color: textColor.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: textColor.withValues(alpha: 0.06)),

          Expanded(child: child),
        ],
      ),
    );
  }

  // ============================================================
  // CREATED TAB
  // ============================================================

  Widget _buildCreatedTab(
    bool isDarkMode,
    Color accentColor,
    SettingsProvider settingsProvider,
  ) {
    return Consumer<PlaylistAlbumLibraryProvider>(
      builder: (context, provider, child) {
        final playlists = provider.createdPlaylists
            .map(
              (playlist) => {...playlist, 'thumbnail': playlist['thumbnail']},
            )
            .toList();

        if (playlists.isEmpty) {
          return _buildCreatedEmptyState(isDarkMode, accentColor);
        }

        return RefreshIndicator(
          color: accentColor,
          backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
          onRefresh: () async {
            await provider.loadCreatedPlaylistsWithThumbnails();
          },
          child: settingsProvider.isGridView
              ? _buildCreatedGrid(playlists, isDarkMode, accentColor)
              : _buildCreatedList(playlists, isDarkMode, accentColor),
        );
      },
    );
  }

  // ============================================================
  // CREATED EMPTY
  // ============================================================

  Widget _buildCreatedEmptyState(bool isDarkMode, Color accentColor) {
    return RefreshIndicator(
      color: accentColor,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.58,
            child: AppEmptyState(
              icon: Icons.queue_music_rounded,
              title: 'no_playlists_yet'.tr(),
              message: 'no_playlists_yet_desc'.tr(),
              actionLabel: 'create_playlist'.tr(),
              onAction: _createNewPlaylist,
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CREATED GRID
  // ============================================================

  Widget _buildCreatedGrid(
    List<Map<String, dynamic>> playlists,
    bool isDarkMode,
    Color accentColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int crossAxisCount;

        if (width >= 1400) {
          crossAxisCount = 5;
        } else if (width >= 1100) {
          crossAxisCount = 4;
        } else if (width >= 700) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 2;
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.76,
          ),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            return _buildCreatedPlaylistCard(
              playlists[index],
              isDarkMode,
              accentColor,
            );
          },
        );
      },
    );
  }

  // ============================================================
  // CREATED CARD
  // ============================================================

  Widget _buildCreatedPlaylistCard(
    Map<String, dynamic> playlist,
    bool isDarkMode,
    Color accentColor,
  ) {
    final name = playlist['name']?.toString() ?? 'Playlist';

    final thumbnail = playlist['thumbnail']?.toString() ?? '';

    return FutureBuilder<int>(
      future: _getSongCountForPlaylist(name),
      builder: (context, snapshot) {
        final songCount = snapshot.data ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showPlaylistDetails(playlist),
            child: Container(
              decoration: BoxDecoration(
                color: MainScreenColors.getSurfaceColor(isDarkMode),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildThumbnail(
                          thumbnail,
                          accentColor,
                          isDarkMode,
                          showGradient: true,
                        ),

                        Positioned(
                          top: 10,
                          left: 10,
                          child: _buildMoreButton(
                            isDarkMode: isDarkMode,
                            onDelete: () => _deletePlaylist(playlist),
                          ),
                        ),

                        Positioned(
                          top: 10,
                          right: 10,
                          child: _buildSongCountBadge(songCount),
                        ),

                        if (songCount > 0)
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: _buildPlayButton(
                              accentColor,
                              () => _playPlaylist(playlist),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 12, 13, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          songCount == 1 ? '1 song' : '$songCount songs',
                          style: AppTextStyles.caption(
                            isDarkMode: isDarkMode,
                            color: MainScreenColors.getTextColor(
                              isDarkMode,
                            ).withValues(alpha: 0.58),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // MORE BUTTON
  // ============================================================

  Widget _buildMoreButton({
    required bool isDarkMode,
    required VoidCallback onDelete,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.52),
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        tooltip: 'Playlist options',
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_horiz_rounded,
          color: Colors.white,
          size: 21,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (value) {
          if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (context) {
          return const [
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text('Delete playlist'),
                ],
              ),
            ),
          ];
        },
      ),
    );
  }

  // ============================================================
  // CREATED LIST
  // ============================================================

  Widget _buildCreatedList(
    List<Map<String, dynamic>> playlists,
    bool isDarkMode,
    Color accentColor,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];

        final name = playlist['name']?.toString() ?? 'Playlist';

        final thumbnail = playlist['thumbnail']?.toString() ?? '';

        return FutureBuilder<int>(
          future: _getSongCountForPlaylist(name),
          builder: (context, snapshot) {
            final songCount = snapshot.data ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: MainScreenColors.getSurfaceColor(isDarkMode),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showPlaylistDetails(playlist),
                  child: SizedBox(
                    height: 108,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 108,
                          height: 108,
                          child: _buildThumbnail(
                            thumbnail,
                            accentColor,
                            isDarkMode,
                            showGradient: true,
                          ),
                        ),

                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.titleSm(
                                    isDarkMode: isDarkMode,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                Text(
                                  songCount == 1
                                      ? '1 song'
                                      : '$songCount songs',
                                  style: AppTextStyles.caption(
                                    isDarkMode: isDarkMode,
                                    color: MainScreenColors.getTextColor(
                                      isDarkMode,
                                    ).withValues(alpha: 0.58),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (songCount > 0)
                          _buildSmallPlayButton(
                            accentColor,
                            () => _playPlaylist(playlist),
                          ),

                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'delete') {
                              _deletePlaylist(playlist);
                            }
                          },
                          itemBuilder: (context) {
                            return const [
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete playlist'),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DENSE MERGED LIST
  // ============================================================

  /// Flattens created playlists, saved playlists and saved albums into one
  /// list so the Library page can show a single collection per filter chip.
  Widget _buildDenseMergedList(bool isDarkMode, Color accentColor) {
    return Consumer<PlaylistAlbumLibraryProvider>(
      builder: (context, provider, child) {
        final items = <_PlaylistDenseItem>[
          for (final playlist in provider.createdPlaylists)
            _PlaylistDenseItem(
              title: playlist['name']?.toString() ?? 'Playlist',
              subtitle: 'Playlist',
              thumbnail: playlist['thumbnail']?.toString() ?? '',
              isCreated: true,
              source: playlist,
            ),
          for (final saved in provider.savedPlaylists)
            _PlaylistDenseItem(
              title:
                  saved['name']?.toString() ??
                  saved['title']?.toString() ??
                  'Playlist',
              subtitle: 'Saved playlist',
              thumbnail: saved['thumbnail']?.toString() ?? '',
              isCreated: false,
              source: saved,
            ),
          for (final album in provider.savedAlbums)
            _PlaylistDenseItem(
              title:
                  album['name']?.toString() ??
                  album['title']?.toString() ??
                  'Album',
              subtitle:
                  'Album • ${album['artist']?.toString() ?? 'Unknown artist'}',
              thumbnail: album['thumbnail']?.toString() ?? '',
              isCreated: false,
              source: album,
            ),
        ];

        if (items.isEmpty) {
          return _buildCreatedEmptyState(isDarkMode, accentColor);
        }

        return RefreshIndicator(
          color: accentColor,
          backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
          onRefresh: () async {
            await provider.loadAll();
            await provider.loadCreatedPlaylistsWithThumbnails();
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              return LibraryDenseRow(
                title: item.title,
                subtitle: item.subtitle,
                artworkUrl: item.thumbnail,
                placeholderIcon: item.isCreated
                    ? Icons.queue_music_rounded
                    : Icons.bookmark_rounded,
                isDarkMode: isDarkMode,
                accentColor: accentColor,
                onTap: () => item.isCreated
                    ? _showPlaylistDetails(item.source)
                    : _openContentDetail(_normalizeContent(item.source)),
                actions: item.isCreated
                    ? _buildDenseMoreAction(item.source, isDarkMode)
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDenseMoreAction(Map<String, dynamic> playlist, bool isDarkMode) {
    return IconButton(
      tooltip: 'Playlist options',
      onPressed: () => _deletePlaylist(playlist),
      icon: Icon(
        Icons.more_vert,
        size: AppDimens.iconMd,
        color: MainScreenColors.getTextColor(
          isDarkMode,
        ).withValues(alpha: AppDimens.opacityMuted),
      ),
    );
  }

  // ============================================================
  // SAVED TAB
  // ============================================================

  Widget _buildSavedTab(
    bool isDarkMode,
    Color accentColor,
    SettingsProvider settingsProvider,
  ) {
    return Consumer<PlaylistAlbumLibraryProvider>(
      builder: (context, provider, child) {
        final savedPlaylists = provider.savedPlaylists;

        final savedAlbums = provider.savedAlbums;

        final contents = _savedContentFilter == 'Playlists'
            ? savedPlaylists
            : savedAlbums;

        return Column(
          children: [
            _buildSavedFilter(isDarkMode, accentColor),

            Expanded(
              child: RefreshIndicator(
                color: accentColor,
                backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
                onRefresh: () async {
                  await provider.loadAll();
                },
                child: contents.isEmpty
                    ? _buildSavedEmptyState(isDarkMode, accentColor)
                    : settingsProvider.isGridView
                    ? _buildSavedGrid(contents, isDarkMode, accentColor)
                    : _buildSavedList(contents, isDarkMode, accentColor),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SAVED FILTER
  // ============================================================

  Widget _buildSavedFilter(bool isDarkMode, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterButton(
              icon: Icons.queue_music_rounded,
              label: 'Playlists',
              selected: _savedContentFilter == 'Playlists',
              isDarkMode: isDarkMode,
              accentColor: accentColor,
              onPressed: () {
                setState(() {
                  _savedContentFilter = 'Playlists';
                });
              },
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: _buildFilterButton(
              icon: Icons.album_rounded,
              label: 'Albums',
              selected: _savedContentFilter == 'Albums',
              isDarkMode: isDarkMode,
              accentColor: accentColor,
              onPressed: () {
                setState(() {
                  _savedContentFilter = 'Albums';
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String label,
    required bool selected,
    required bool isDarkMode,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? accentColor
                : MainScreenColors.getSurfaceColor(isDarkMode),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? Colors.black
                    : textColor.withValues(alpha: 0.7),
              ),

              const SizedBox(width: 7),

              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SAVED EMPTY
  // ============================================================

  Widget _buildSavedEmptyState(bool isDarkMode, Color accentColor) {
    final isPlaylist = _savedContentFilter == 'Playlists';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.52,
          child: AppEmptyState(
            icon: isPlaylist
                ? Icons.bookmark_outline_rounded
                : Icons.album_outlined,
            title: isPlaylist
                ? 'no_saved_playlists'.tr()
                : 'no_saved_albums'.tr(),
            message: isPlaylist
                ? 'no_saved_playlists_desc'.tr()
                : 'no_saved_albums_desc'.tr(),
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SAVED GRID
  // ============================================================

  Widget _buildSavedGrid(
    List<Map<String, dynamic>> contents,
    bool isDarkMode,
    Color accentColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int crossAxisCount;

        if (width >= 1400) {
          crossAxisCount = 5;
        } else if (width >= 1100) {
          crossAxisCount = 4;
        } else if (width >= 700) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 2;
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.76,
          ),
          itemCount: contents.length,
          itemBuilder: (context, index) {
            return _buildSavedCard(contents[index], isDarkMode, accentColor);
          },
        );
      },
    );
  }

  // ============================================================
  // SAVED CARD
  // ============================================================

  Widget _buildSavedCard(
    Map<String, dynamic> content,
    bool isDarkMode,
    Color accentColor,
  ) {
    final normalized = _normalizeContent(content);

    final title =
        normalized['name']?.toString() ?? normalized['title']?.toString() ?? '';

    final thumbnail = normalized['thumbnail']?.toString() ?? '';

    final isAlbum = normalized['contentType'] == 'Album';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openContentDetail(normalized),
        child: Container(
          decoration: BoxDecoration(
            color: MainScreenColors.getSurfaceColor(isDarkMode),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(
                      thumbnail,
                      accentColor,
                      isDarkMode,
                      showGradient: true,
                    ),

                    Positioned(
                      left: 10,
                      top: 10,
                      child: _buildTypeBadge(isAlbum ? 'Album' : 'Playlist'),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      isAlbum
                          ? normalized['artist']?.toString() ?? 'Album'
                          : 'Saved playlist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        isDarkMode: isDarkMode,
                        color: MainScreenColors.getTextColor(
                          isDarkMode,
                        ).withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TYPE BADGE
  // ============================================================

  Widget _buildTypeBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ============================================================
  // SAVED LIST
  // ============================================================

  Widget _buildSavedList(
    List<Map<String, dynamic>> contents,
    bool isDarkMode,
    Color accentColor,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: contents.length,
      itemBuilder: (context, index) {
        final content = _normalizeContent(contents[index]);

        final title =
            content['name']?.toString() ?? content['title']?.toString() ?? '';

        final thumbnail = content['thumbnail']?.toString() ?? '';

        final isAlbum = content['contentType'] == 'Album';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: MainScreenColors.getSurfaceColor(isDarkMode),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openContentDetail(content),
              child: SizedBox(
                height: 94,
                child: Row(
                  children: [
                    SizedBox(
                      width: 94,
                      height: 94,
                      child: _buildThumbnail(
                        thumbnail,
                        accentColor,
                        isDarkMode,
                        showGradient: false,
                      ),
                    ),

                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleSm(
                                isDarkMode: isDarkMode,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Text(
                              isAlbum
                                  ? 'Album by ${content['artist'] ?? 'Unknown'}'
                                  : 'Saved playlist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption(
                                isDarkMode: isDarkMode,
                                color: MainScreenColors.getTextColor(
                                  isDarkMode,
                                ).withValues(alpha: 0.58),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Icon(
                      Icons.chevron_right_rounded,
                      color: MainScreenColors.getTextColor(
                        isDarkMode,
                      ).withValues(alpha: 0.45),
                    ),

                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // THUMBNAIL
  // ============================================================

  Widget _buildThumbnail(
    String url,
    Color accentColor,
    bool isDarkMode, {
    bool showGradient = false,
  }) {
    Widget image;

    if (url.isEmpty) {
      image = Container(
        color: MainScreenColors.getSurfaceColor(isDarkMode),
        child: Center(
          child: Icon(
            Icons.library_music_rounded,
            color: accentColor,
            size: 42,
          ),
        ),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) {
          return Container(
            color: MainScreenColors.getSurfaceColor(isDarkMode),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accentColor,
                ),
              ),
            ),
          );
        },
        errorWidget: (context, url, error) {
          return Container(
            color: MainScreenColors.getSurfaceColor(isDarkMode),
            child: Center(
              child: Icon(
                Icons.library_music_rounded,
                color: accentColor,
                size: 42,
              ),
            ),
          );
        },
      );
    }

    if (!showGradient) {
      return image;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        image,

        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.38),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SONG COUNT BADGE
  // ============================================================

  Widget _buildSongCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note_rounded, size: 13, color: Colors.white),

          const SizedBox(width: 3),

          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PLAY BUTTON
  // ============================================================

  Widget _buildPlayButton(Color accentColor, VoidCallback onPressed) {
    return Material(
      color: accentColor,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 25),
        ),
      ),
    );
  }

  Widget _buildSmallPlayButton(Color accentColor, VoidCallback onPressed) {
    return Material(
      color: accentColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(9),
          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
        ),
      ),
    );
  }

  // ============================================================
  // NORMALIZE SAVED CONTENT
  // ============================================================

  Map<String, dynamic> _normalizeContent(Map<String, dynamic> content) {
    return {
      ...content,
      'playlistId':
          content['playlistId'] ?? content['albumId'] ?? content['id'] ?? '',
    };
  }

  // ============================================================
  // OPEN SAVED CONTENT
  // ============================================================

  void _openContentDetail(Map<String, dynamic> content) {
    final contentType = content['contentType']?.toString() ?? 'Playlist';

    final id = content['playlistId']?.toString() ?? '';

    final name =
        content['name']?.toString() ?? content['title']?.toString() ?? '';

    final thumbnail = content['thumbnail']?.toString() ?? '';

    final artist = content['artist']?.toString() ?? '';

    final formattedContent = contentType == 'Album'
        ? AlbumDetailed(
            playlistId: id,
            name: name,
            artist: ArtistBasic(name: artist),
            thumbnails: [
              ThumbnailFull(url: thumbnail, width: 1280, height: 720),
            ],
            type: 'Album',
            albumId: id,
          )
        : PlaylistDetailed(
            playlistId: id,
            name: name,
            artist: ArtistBasic(name: ''),
            thumbnails: [
              ThumbnailFull(url: thumbnail, width: 1280, height: 720),
            ],
            type: 'Playlist',
          );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaylistAlbumContent(content: formattedContent),
      ),
    );
  }

  // ============================================================
  // SONG COUNT
  // ============================================================

  Future<int> _getSongCountForPlaylist(String playlistName) async {
    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );

    return provider.getSongCountForPlaylist(playlistName);
  }

  // ============================================================
  // PLAY PLAYLIST
  // ============================================================

  Future<void> _playPlaylist(Map<String, dynamic> playlist) async {
    try {
      final name = playlist['name']?.toString();

      if (name == null || name.isEmpty) {
        return;
      }

      final provider = Provider.of<PlaylistAlbumLibraryProvider>(
        context,
        listen: false,
      );

      final songs = await provider.getPlaylistSongs(name);

      if (songs.isEmpty) {
        if (!mounted) return;

        AppSnackBar.showWarning(context, 'No songs in this playlist');

        return;
      }

      final songInfoList = songs.map<SongInfo>((song) {
        final artists = song['artists'];

        List<Artist> artistList;

        if (artists is List && artists.isNotEmpty) {
          artistList = artists.map<Artist>((artist) {
            return Artist(
              name: artist['name']?.toString() ?? '',
              id: artist['id']?.toString() ?? '',
            );
          }).toList();
        } else {
          artistList = [
            Artist(
              name: song['artist']?.toString() ?? '',
              id: song['artistId']?.toString() ?? '',
            ),
          ];
        }

        final durationValue = song['duration'];

        int durationSeconds = 0;

        if (durationValue is int) {
          durationSeconds = durationValue;
        } else if (durationValue is double) {
          durationSeconds = durationValue.toInt();
        } else {
          durationSeconds = int.tryParse(durationValue?.toString() ?? '') ?? 0;
        }

        return SongInfo(
          videoId: song['id']?.toString() ?? '',
          name: song['title']?.toString() ?? '',
          artists: artistList,
          thumbnails: [
            Thumbnail(
              url: song['thumbnail']?.toString() ?? '',
              width: 1280,
              height: 720,
            ),
          ],
          duration: Duration(seconds: durationSeconds),
        );
      }).toList();

      if (songInfoList.isEmpty) {
        return;
      }

      if (!mounted) return;

      final playerProvider = Provider.of<PlayerProvider>(
        context,
        listen: false,
      );

      final queueProvider = Provider.of<QueueProvider>(context, listen: false);

      final contentDetailsService = ContentDetailsService();

      await contentDetailsService.playSong(
        songInfoList.first,
        playerProvider,
        queueProvider,
        songInfoList,
        playlistId: name,
      );
    } catch (e) {
      debugPrint('Error playing playlist: $e');

      if (!mounted) return;

      AppSnackBar.showError(context, 'Error playing playlist');
    }
  }

  // ============================================================
  // PLAYLIST DETAILS
  // ============================================================

  Future<void> _showPlaylistDetails(Map<String, dynamic> playlist) async {
    try {
      final name = playlist['name']?.toString();

      if (name == null || name.isEmpty) {
        return;
      }

      final provider = Provider.of<PlaylistAlbumLibraryProvider>(
        context,
        listen: false,
      );

      final songs = await provider.getPlaylistSongs(name);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              PlaylistDetailsScreen(playlist: playlist, songs: songs),
        ),
      );
    } catch (e) {
      debugPrint('Error opening playlist: $e');

      if (!mounted) return;

      AppSnackBar.showError(context, 'Error opening playlist');
    }
  }
}

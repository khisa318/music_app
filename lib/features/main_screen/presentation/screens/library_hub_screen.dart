import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../library/data/providers/library_provider.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../library/presentation/widgets/library_filter_chips.dart';
import '../../../library/presentation/widgets/library_song_search_delegate.dart';
import '../../../playlists/presentation/screens/playlists_screen.dart';
import '../../../playlists/presentation/widgets/create_playlist_bottomsheet.dart';

/// The single Library destination.
///
/// Follows the reference design: a large page title with actions on the
/// right, the collection filters, and a single flat list of dense rows (text on
/// the left, square artwork on the right).
///
/// The filters are the library's collections: All songs, Playlists, Recently
/// played, Downloads, Favourites, Local music. Each one is its own tab, so the
/// previous "Songs" chip that swapped collections through the filter sheet is
/// gone; what remains in the sheet is the favourites songs/artists switch, sort
/// order and appearance. All six are shown at once rather than in a scrolling
/// row, because a filter that has to be scrolled to is a filter that gets
/// missed.
class LibraryHubScreen extends StatefulWidget {
  const LibraryHubScreen({super.key});

  @override
  State<LibraryHubScreen> createState() => _LibraryHubScreenState();
}

class _LibraryHubScreenState extends State<LibraryHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _filterController;

  /// Which of the collection chips is active.
  int _filterIndex = 0;

  /// Whether the Favourites collection shows songs or artists.
  LibraryFavoritesView _favoritesView = LibraryFavoritesView.songs;

  String _sortBy = 'title';
  bool _sortAscending = true;

  // Positions within the chip and tab lists in build(). Only the destinations
  // something can jump to are named; the rest are reached by tapping a chip.
  static const int _playlistsFilter = 1;
  static const int _favoritesFilter = 4;

  /// One chip per collection, in the same order as the chips themselves.
  static const int _filterCount = 6;

  @override
  void initState() {
    super.initState();
    _filterController = TabController(length: _filterCount, vsync: this)
      ..addListener(() {
        if (!_filterController.indexIsChanging) {
          setState(() => _filterIndex = _filterController.index);
        }
      });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _selectFilter(int index) {
    _filterController.animateTo(index);
    setState(() => _filterIndex = index);
  }

  Future<void> _createPlaylist() async {
    final created = await showModalBottomSheet<bool?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreatePlaylistBottomSheet(),
    );

    if (created == true && mounted) {
      _selectFilter(_playlistsFilter);
    }
  }

  void _openSongSearch() {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );

    showSearch(
      context: context,
      delegate: LibrarySongSearchDelegate(
        libraryProvider.likedSongs,
        libraryProvider.downloadedSongs,
        libraryProvider.lastPlayed,
        libraryProvider.localSongs,
        Provider.of<SettingsProvider>(context, listen: false).accentColor,
      ),
    );
  }

  void _openFilterSheet(bool isDarkMode, Color accentColor) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _LibraryFilterSheet(
        isDarkMode: isDarkMode,
        accentColor: accentColor,
        favoritesView: _favoritesView,
        sortBy: _sortBy,
        sortAscending: _sortAscending,
        isDarkTheme: isDarkMode,
        onFavoritesViewChanged: (view) {
          setState(() => _favoritesView = view);
          _selectFilter(_favoritesFilter);
        },
        onSortByChanged: (value) => setState(() => _sortBy = value),
        onSortAscendingChanged: (value) =>
            setState(() => _sortAscending = value),
        onThemeChanged: () {
          Provider.of<SettingsProvider>(context, listen: false).toggleTheme();
        },
      ),
    );
  }

  /// One song collection as a tab of its own.
  ///
  /// The key is derived from the scope rather than being a constant so each
  /// collection keeps its own scroll position and pagination state across chip
  /// changes.
  Widget _buildSongTab(
    LibrarySongScope scope, {
    LibraryFavoritesView? favoritesView,
  }) {
    return LibraryScreen(
      key: ValueKey(
        favoritesView == null
            ? 'songs-${scope.tabKey}'
            : 'favorites-${favoritesView.name}',
      ),
      scope: scope,
      favoritesView: favoritesView,
      sortBy: _sortBy,
      sortAscending: _sortAscending,
      denseArtwork: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;

    return Scaffold(
      backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LibraryHeader(
              isDarkMode: isDarkMode,
              showCreateAction: _filterIndex == _playlistsFilter,
              onSearchTap: _openSongSearch,
              onFilterTap: () => _openFilterSheet(isDarkMode, accentColor),
              onCreateTap: _createPlaylist,
            ),

            LibraryFilterChips(
              labels: [
                'songs'.tr(),
                'playlists'.tr(),
                'recently_played'.tr(),
                'downloads'.tr(),
                'favorites'.tr(),
                'local_music'.tr(),
              ],
              selectedIndex: _filterIndex,
              onSelected: _selectFilter,
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            ),

            Expanded(
              child: TabBarView(
                controller: _filterController,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildSongTab(LibrarySongScope.all),
                  const PlaylistScreen(dense: true),
                  _buildSongTab(LibrarySongScope.recentlyPlayed),
                  _buildSongTab(LibrarySongScope.downloads),
                  _buildSongTab(
                    LibrarySongScope.favorites,
                    favoritesView: _favoritesView,
                  ),
                  _buildSongTab(LibrarySongScope.localMusic),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _LibraryHeader extends StatelessWidget {
  final bool isDarkMode;
  final bool showCreateAction;
  final VoidCallback onSearchTap;
  final VoidCallback onFilterTap;
  final VoidCallback onCreateTap;

  const _LibraryHeader({
    required this.isDarkMode,
    required this.showCreateAction,
    required this.onSearchTap,
    required this.onFilterTap,
    required this.onCreateTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingMd,
        AppDimens.paddingLg,
        AppDimens.spacingXs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'your_library'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLg(
                isDarkMode: isDarkMode,
              ).copyWith(fontWeight: AppTextStyles.weightBold),
            ),
          ),

          if (showCreateAction) ...[
            _HeaderIconButton(
              icon: Icons.add_rounded,
              color: textColor,
              tooltip: 'create_playlist'.tr(),
              onPressed: onCreateTap,
            ),
            const SizedBox(width: AppDimens.spacingXs),
          ],

          _HeaderIconButton(
            icon: Icons.search_rounded,
            color: textColor,
            tooltip: 'search'.tr(),
            onPressed: onSearchTap,
          ),

          const SizedBox(width: AppDimens.spacingXs),

          _HeaderIconButton(
            icon: Icons.tune_rounded,
            color: textColor,
            tooltip: 'library_filters'.tr(),
            onPressed: onFilterTap,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: AppDimens.iconLg, color: color),
    );
  }
}

// =============================================================================
// FILTER SHEET
// =============================================================================

/// Hosts the options that no longer fit on the page itself: how favourites are
/// presented, sort order and appearance.
///
/// The song collections are not here any more; each is a chip on the page.
class _LibraryFilterSheet extends StatelessWidget {
  final bool isDarkMode;
  final Color accentColor;
  final LibraryFavoritesView favoritesView;
  final String sortBy;
  final bool sortAscending;
  final bool isDarkTheme;
  final ValueChanged<LibraryFavoritesView> onFavoritesViewChanged;
  final ValueChanged<String> onSortByChanged;
  final ValueChanged<bool> onSortAscendingChanged;
  final VoidCallback onThemeChanged;

  const _LibraryFilterSheet({
    required this.isDarkMode,
    required this.accentColor,
    required this.favoritesView,
    required this.sortBy,
    required this.sortAscending,
    required this.isDarkTheme,
    required this.onFavoritesViewChanged,
    required this.onSortByChanged,
    required this.onSortAscendingChanged,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: MainScreenColors.getSurfaceColor(isDarkMode),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusXxxl),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingXl,
            AppDimens.paddingLg,
            AppDimens.paddingXl,
            AppDimens.paddingXl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: AppDimens.opacityMedium),
                    borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                  ),
                ),
              ),

              const SizedBox(height: AppDimens.paddingLg),

              Text(
                'library_filters'.tr(),
                style: AppTextStyles.titleSm(
                  isDarkMode: isDarkMode,
                ).copyWith(fontWeight: AppTextStyles.weightBold),
              ),

              const SizedBox(height: AppDimens.paddingLg),

              _SheetSection(
                isDarkMode: isDarkMode,
                title: 'favourites_show'.tr(),
                child: Wrap(
                  spacing: AppDimens.spacingSm,
                  runSpacing: AppDimens.spacingSm,
                  children: [
                    _SheetOption(
                      label: 'songs'.tr(),
                      isSelected: favoritesView == LibraryFavoritesView.songs,
                      isDarkMode: isDarkMode,
                      accentColor: accentColor,
                      onTap: () =>
                          onFavoritesViewChanged(LibraryFavoritesView.songs),
                    ),
                    _SheetOption(
                      label: 'artists'.tr(),
                      isSelected: favoritesView == LibraryFavoritesView.artists,
                      isDarkMode: isDarkMode,
                      accentColor: accentColor,
                      onTap: () =>
                          onFavoritesViewChanged(LibraryFavoritesView.artists),
                    ),
                  ],
                ),
              ),

              _SheetSection(
                isDarkMode: isDarkMode,
                title: 'sort_by'.tr(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppDimens.spacingSm,
                      runSpacing: AppDimens.spacingSm,
                      children: [
                        _SheetOption(
                          label: 'sort_by_title'.tr(),
                          isSelected: sortBy == 'title',
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                          onTap: () => onSortByChanged('title'),
                        ),
                        _SheetOption(
                          label: 'sort_by_artist'.tr(),
                          isSelected: sortBy == 'artist',
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                          onTap: () => onSortByChanged('artist'),
                        ),
                        _SheetOption(
                          label: 'sort_by_duration'.tr(),
                          isSelected: sortBy == 'duration',
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                          onTap: () => onSortByChanged('duration'),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppDimens.spacingMd),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'sort_order'.tr(),
                            style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                          ),
                        ),

                        Text(
                          sortAscending
                              ? 'sort_order_ascending'.tr()
                              : 'sort_order_descending'.tr(),
                          style: AppTextStyles.body2(
                            isDarkMode: isDarkMode,
                            color: accentColor,
                          ),
                        ),

                        const SizedBox(width: AppDimens.spacingSm),

                        Switch(
                          value: sortAscending,
                          onChanged: onSortAscendingChanged,
                          activeThumbColor: Colors.black,
                          activeTrackColor: accentColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              _SheetSection(
                isDarkMode: isDarkMode,
                title: 'appearance'.tr(),
                isLast: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isDarkTheme ? 'dark_mode'.tr() : 'light_mode'.tr(),
                        style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                      ),
                    ),

                    Switch(
                      value: isDarkTheme,
                      onChanged: (_) => onThemeChanged(),
                      activeThumbColor: Colors.black,
                      activeTrackColor: accentColor,
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
}

class _SheetSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDarkMode;
  final bool isLast;

  const _SheetSection({
    required this.title,
    required this.child,
    required this.isDarkMode,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppDimens.paddingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                AppTextStyles.caption(
                  isDarkMode: isDarkMode,
                  color: textColor.withValues(alpha: AppDimens.opacityMuted),
                ).copyWith(
                  fontWeight: AppTextStyles.weightBold,
                  letterSpacing: 0.4,
                ),
          ),

          const SizedBox(height: AppDimens.spacingMd),

          child,
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final Color accentColor;
  final VoidCallback onTap;

  const _SheetOption({
    required this.label,
    required this.isSelected,
    required this.isDarkMode,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: isSelected ? accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : textColor.withValues(alpha: AppDimens.opacityLight),
            ),
          ),
          child: Text(
            label,
            style:
                AppTextStyles.body2(
                  isDarkMode: isDarkMode,
                  color: isSelected ? Colors.black : textColor,
                ).copyWith(
                  fontWeight: isSelected
                      ? AppTextStyles.weightBold
                      : AppTextStyles.weightSemiBold,
                ),
          ),
        ),
      ),
    );
  }
}

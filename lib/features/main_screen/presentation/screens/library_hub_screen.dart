import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../library/data/providers/library_provider.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../library/presentation/widgets/library_song_search_delegate.dart';
import '../../../playlists/presentation/screens/playlists_screen.dart';
import '../../../playlists/presentation/widgets/create_playlist_bottomsheet.dart';

/// Single destination that merges Playlists and Library songs behind a
/// two-way segment switch.
///
/// The inner screens keep their own sub-tabs (Created/Saved for playlists,
/// All/Downloads/Recent/Favourites/Local for songs) so nothing is lost when
/// the two former bottom-nav tabs are folded into one.
class LibraryHubScreen extends StatefulWidget {
  const LibraryHubScreen({super.key});

  @override
  State<LibraryHubScreen> createState() => _LibraryHubScreenState();
}

class _LibraryHubScreenState extends State<LibraryHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _segmentController;
  int _segment = 0;

  @override
  void initState() {
    super.initState();
    _segmentController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_segmentController.indexIsChanging) {
          setState(() => _segment = _segmentController.index);
        }
      });
  }

  @override
  void dispose() {
    _segmentController.dispose();
    super.dispose();
  }

  Future<void> _createPlaylist() async {
    await showModalBottomSheet<bool?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreatePlaylistBottomSheet(),
    );
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

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;

    return Scaffold(
      backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
      appBar: _LibraryHubAppBar(
        isDarkMode: isDarkMode,
        accentColor: accentColor,
        showSongActions: _segment == 1,
        onSearchTap: _openSongSearch,
        onThemeToggle: settingsProvider.toggleTheme,
      ),
      body: Column(
        children: [
          _SegmentSwitch(
            controller: _segmentController,
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),

          if (_segment == 0) _PlaylistActions(onCreatePlaylist: _createPlaylist),

          Expanded(
            child: TabBarView(
              controller: _segmentController,
              physics: const BouncingScrollPhysics(),
              children: const [PlaylistScreen(), LibraryScreen()],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SEGMENT SWITCH
// =============================================================================

class _SegmentSwitch extends StatelessWidget {
  final TabController controller;
  final bool isDarkMode;
  final Color accentColor;

  const _SegmentSwitch({
    required this.controller,
    required this.isDarkMode,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingSm,
        AppDimens.paddingLg,
        AppDimens.spacingMd,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MainScreenColors.getSurfaceColor(isDarkMode),
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(
          color: textColor.withValues(alpha: AppDimens.opacitySubtle),
        ),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
        labelColor: Colors.black,
        unselectedLabelColor: textColor.withValues(
          alpha: AppDimens.opacityMuted,
        ),
        labelStyle: AppTextStyles.bodyMd(
          isDarkMode: isDarkMode,
        ).copyWith(
          color: Colors.black,
          fontWeight: AppTextStyles.weightBold,
        ),
        unselectedLabelStyle: AppTextStyles.bodyMd(isDarkMode: isDarkMode)
            .copyWith(fontWeight: AppTextStyles.weightSemiBold),
        tabs: [
          Tab(
            height: 44,
            icon: const Icon(Icons.queue_music_rounded, size: 19),
            text: 'playlists'.tr(),
          ),
          Tab(
            height: 44,
            icon: const Icon(Icons.library_music_rounded, size: 19),
            text: 'songs'.tr(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PLAYLIST ACTIONS
// =============================================================================

class _PlaylistActions extends StatelessWidget {
  final VoidCallback onCreatePlaylist;

  const _PlaylistActions({required this.onCreatePlaylist});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        0,
        AppDimens.paddingLg,
        AppDimens.spacingSm,
      ),
      child: Row(
        children: [
          Text(
            'playlists'.tr(),
            style: AppTextStyles.caption(
              isDarkMode: isDarkMode,
            ).copyWith(
              color: textColor.withValues(alpha: AppDimens.opacityMuted),
            ),
          ),
          const Spacer(),
          _SmallAction(
            isDarkMode: isDarkMode,
            icon: settingsProvider.isGridView
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded,
            tooltip: 'playlists'.tr(),
            onPressed: () {
              settingsProvider.isGridView = !settingsProvider.isGridView;
            },
          ),
          const SizedBox(width: AppDimens.spacingSm),
          _SmallAction(
            isDarkMode: isDarkMode,
            icon: Icons.add_rounded,
            tooltip: 'create_playlist'.tr(),
            filled: true,
            onPressed: onCreatePlaylist,
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final bool isDarkMode;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  const _SmallAction({
    required this.isDarkMode,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = context.watch<SettingsProvider>().accentColor;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled
            ? accentColor
            : MainScreenColors.getTextColor(
                isDarkMode,
              ).withValues(alpha: isDarkMode ? 0.08 : 0.06),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: AppDimens.iconMd,
              color: filled
                  ? Colors.black
                  : MainScreenColors.getTextColor(isDarkMode),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// APP BAR
// =============================================================================

class _LibraryHubAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDarkMode;
  final Color accentColor;
  final bool showSongActions;
  final VoidCallback onSearchTap;
  final VoidCallback onThemeToggle;

  const _LibraryHubAppBar({
    required this.isDarkMode,
    required this.accentColor,
    required this.showSongActions,
    required this.onSearchTap,
    required this.onThemeToggle,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.of(context).textScaler.scale(1.0);
    final iconScale = textScale > 1.0
        ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
        : 1.0;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(
          left: AppDimens.paddingLg,
          right: AppDimens.paddingSm,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                showSongActions
                    ? Icons.library_music_rounded
                    : Icons.queue_music_rounded,
                color: accentColor,
                size: 23 * iconScale,
              ),
            ),

            const SizedBox(width: AppDimens.spacingMd),

            Expanded(
              child: Text(
                'your_library'.tr(),
                style: AppTextStyles.titleLg(
                  isDarkMode: isDarkMode,
                ).copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            _CircleIconButton(
              isDarkMode: isDarkMode,
              icon: Icons.search_rounded,
              iconScale: iconScale,
              tooltip: 'search'.tr(),
              onPressed: onSearchTap,
            ),

            const SizedBox(width: AppDimens.spacingSm),

            _CircleIconButton(
              isDarkMode: isDarkMode,
              icon: Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              iconScale: iconScale,
              tooltip: 'toggle_theme'.tr(),
              onPressed: onThemeToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final bool isDarkMode;
  final IconData icon;
  final double iconScale;
  final String tooltip;
  final VoidCallback onPressed;

  const _CircleIconButton({
    required this.isDarkMode,
    required this.icon,
    required this.iconScale,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: MainScreenColors.getTextColor(
          isDarkMode,
        ).withValues(alpha: isDarkMode ? 0.08 : 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: MainScreenColors.getTextColor(
            isDarkMode,
          ).withValues(alpha: isDarkMode ? 0.12 : 0.10),
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 21 * iconScale),
      ),
    );
  }
}

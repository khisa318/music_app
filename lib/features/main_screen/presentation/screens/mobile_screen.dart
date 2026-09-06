import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/ota_model.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/theme/app_theme.dart';

import '../../../home/presentation/screens/home_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../ota/data/providers/ota_provider.dart';
import '../../../ota/presentation/widgets/ota_bottomsheet.dart';
import '../../../player/presentation/screens/player_ui.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../library/data/providers/library_provider.dart';
import '../../../library/presentation/widgets/library_song_search_delegate.dart';
import '../../../playlists/presentation/screens/playlists_screen.dart';
import '../../../playlists/presentation/widgets/create_playlist_bottomsheet.dart';
import '../../../search/presentation/screens/search_screen.dart';

import 'full_player_screen.dart';

class MobileMainScreen extends StatefulWidget {
  const MobileMainScreen({super.key});

  @override
  State<MobileMainScreen> createState() => _MobileMainScreenState();
}

class _MobileMainScreenState extends State<MobileMainScreen> {
  final PersistentTabController _controller = PersistentTabController(
    initialIndex: 0,
  );

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsProvider = Provider.of<SettingsProvider>(
        context,
        listen: false,
      );

      if (settingsProvider.updateCheckEnabled) {
        Provider.of<OTAProvider>(context, listen: false).checkForUpdates();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // CREATE PLAYLIST
  // ---------------------------------------------------------------------------

  Future<void> _createPlaylist() async {
    await showModalBottomSheet<bool?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const CreatePlaylistBottomSheet();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<OTAProvider>(
      builder: (context, otaProvider, child) {
        if (otaProvider.hasUpdate &&
            otaProvider.updateInfo != null &&
            !otaProvider.isUpdateUIShown &&
            !otaProvider.isOTAScreenActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            otaProvider.setUpdateUIShown(true);

            _showOTABottomSheet(context, otaProvider.updateInfo!);
          });
        }

        return Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            final accentColor = settingsProvider.accentColor;

            final theme = settingsProvider.themeMode == ThemeMode.dark
                ? AppTheme.darkTheme
                : AppTheme.lightTheme;

            final mq = MediaQuery.of(context);

            final textScale = mq.textScaler.scale(1.0);

            final double navIconScale = textScale > 1.0
                ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
                : 1.0;

            final double navTextCap = textScale > 1.0 ? 1.0 : textScale;

            final double navIconSize = AppDimens.iconXl * navIconScale;

            return Theme(
              data: theme,
              child: SafeArea(
                top: false,
                child: PersistentTabView(
                  backgroundColor: theme.scaffoldBackgroundColor,

                  controller: _controller,

                  tabs: [
                    // ----------------------------------------------------------------
                    // HOME
                    // ----------------------------------------------------------------
                    PersistentTabConfig(
                      screen: const _TabWrapper(
                        key: ValueKey('home_tab'),
                        titleKey: 'home',
                        isHome: true,
                        child: HomeScreen(),
                      ),
                      item: ItemConfig(
                        icon: Icon(Icons.home_rounded, size: navIconSize),
                        title: 'home'.tr(),
                        activeForegroundColor: accentColor,
                        inactiveForegroundColor:
                            theme.textTheme.bodyLarge?.color?.withValues(
                              alpha: 0.6,
                            ) ??
                            Colors.grey,
                      ),
                    ),

                    // ----------------------------------------------------------------
                    // SEARCH
                    // ----------------------------------------------------------------
                    PersistentTabConfig(
                      screen: const _TabWrapper(
                        key: ValueKey('search_tab'),
                        titleKey: 'search',
                        isHome: false,
                        showAppBar: false,
                        child: SearchScreen(),
                      ),
                      item: ItemConfig(
                        icon: Icon(Icons.search_rounded, size: navIconSize),
                        title: 'search'.tr(),
                        activeForegroundColor: accentColor,
                        inactiveForegroundColor:
                            theme.textTheme.bodyLarge?.color?.withValues(
                              alpha: 0.6,
                            ) ??
                            Colors.grey,
                      ),
                    ),

                    // ----------------------------------------------------------------
                    // PLAYLISTS
                    // ----------------------------------------------------------------
                    PersistentTabConfig(
                      screen: _TabWrapper(
                        key: const ValueKey('playlists_tab'),
                        titleKey: 'playlists',
                        isHome: false,
                        child: const PlaylistScreen(),
                        onCreatePlaylist: _createPlaylist,
                      ),
                      item: ItemConfig(
                        icon: Icon(
                          Icons.playlist_play_rounded,
                          size: navIconSize,
                        ),
                        title: 'playlists'.tr(),
                        activeForegroundColor: accentColor,
                        inactiveForegroundColor:
                            theme.textTheme.bodyLarge?.color?.withValues(
                              alpha: 0.6,
                            ) ??
                            Colors.grey,
                      ),
                    ),

                    // ----------------------------------------------------------------
                    // LIBRARY
                    // ----------------------------------------------------------------
                    PersistentTabConfig(
                      screen: const _TabWrapper(
                        key: ValueKey('library_tab'),
                        titleKey: 'library',
                        isHome: false,
                        child: LibraryScreen(),
                      ),
                      item: ItemConfig(
                        icon: Icon(
                          Icons.library_music_rounded,
                          size: navIconSize,
                        ),
                        title: 'library'.tr(),
                        activeForegroundColor: accentColor,
                        inactiveForegroundColor:
                            theme.textTheme.bodyLarge?.color?.withValues(
                              alpha: 0.6,
                            ) ??
                            Colors.grey,
                      ),
                    ),
                  ],

                  // ----------------------------------------------------------------
                  // NAVIGATION BAR + MINI PLAYER
                  // ----------------------------------------------------------------
                  navBarBuilder: (navBarConfig) => Consumer<PlayerProvider>(
                    builder: (context, playerProvider, child) {
                      final hasPlayer =
                          playerProvider.currentSong != null ||
                          playerProvider.lastPlayedSong != null ||
                          playerProvider.currentLocalSong != null;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasPlayer)
                            Container(
                              decoration: BoxDecoration(
                                color: theme.appBarTheme.backgroundColor,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(AppDimens.radiusMd),
                                ),
                              ),
                              child: SizedBox(
                                height:
                                    AppDimens.miniPlayerHeight * navIconScale,
                                child: PlayerUI(
                                  showFullScreen: false,
                                  isEmbedded: true,
                                  onMinimize: () {},
                                  onExpand: () =>
                                      _showFullPlayerBottomSheet(context),
                                ),
                              ),
                            ),

                          MediaQuery(
                            data: mq.copyWith(
                              textScaler: TextScaler.linear(navTextCap),
                            ),
                            child: MediaQuery.removePadding(
                              context: context,
                              removeBottom: true,
                              child: Style2BottomNavBar(
                                navBarConfig: navBarConfig,
                                navBarDecoration: NavBarDecoration(
                                  color: theme.appBarTheme.backgroundColor,
                                  borderRadius: BorderRadius.zero,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppDimens.spacingSmMd,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, -2),
                                    ),
                                  ],
                                ),
                                itemAnimationProperties: const ItemAnimation(
                                  duration: Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // OTA
  // ---------------------------------------------------------------------------

  void _showOTABottomSheet(BuildContext context, OTAUpdateInfo updateInfo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return OTABottomSheet(updateInfo: updateInfo);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FULL PLAYER
  // ---------------------------------------------------------------------------

  void _showFullPlayerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) {
        return _MobileFullPlayerResponsiveWrapper(
          child: const FullPlayerScreen(),
          onSwitchToDesktop: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (MediaQuery.of(context).size.width >= 600) {
                Navigator.of(context, rootNavigator: true).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) {
                      return const FullPlayerScreen();
                    },
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0, 1),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          );
                        },
                    transitionDuration: const Duration(milliseconds: 350),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 300,
                    ),
                  ),
                );
              }
            });
          },
        );
      },
    );
  }
}

// =============================================================================
// PLAYLIST APP BAR
// =============================================================================

class PlaylistMainAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final VoidCallback onCreatePlaylist;

  const PlaylistMainAppBar({super.key, required this.onCreatePlaylist});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final accentColor = settingsProvider.accentColor;

        final isDarkMode = theme.brightness == Brightness.dark;

        final textScale = MediaQuery.of(context).textScaler.scale(1.0);

        final double iconScale = textScale > 1.0
            ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
            : 1.0;

        return AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 0,

          title: Padding(
            padding: const EdgeInsets.only(
              left: AppDimens.paddingLg,
              right: AppDimens.paddingSm,
            ),
            child: Row(
              children: [
                // --------------------------------------------------------------
                // PLAYLIST ICON
                // --------------------------------------------------------------
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.playlist_play_rounded,
                    color: accentColor,
                    size: 23 * iconScale,
                  ),
                ),

                const SizedBox(width: AppDimens.spacingMd),

                // --------------------------------------------------------------
                // TITLE
                // --------------------------------------------------------------
                Expanded(
                  child: Text(
                    'Playlists',
                    style:
                        AppTextStyles.titleLg(
                          isDarkMode: isDarkMode,
                          color: colorScheme.onSurface,
                        ).copyWith(
                          // Match the other page headers.
                          fontSize: AppTextStyles.fontSizeTitleLg,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // --------------------------------------------------------------
                // GRID / LIST TOGGLE
                // --------------------------------------------------------------
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(
                      alpha: isDarkMode ? 0.08 : 0.06,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.onSurface.withValues(
                        alpha: isDarkMode ? 0.12 : 0.10,
                      ),
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      settingsProvider.isGridView =
                          !settingsProvider.isGridView;
                    },
                    icon: Icon(
                      settingsProvider.isGridView
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                      color: colorScheme.onSurface,
                      size: 21 * iconScale,
                    ),
                  ),
                ),

                const SizedBox(width: AppDimens.spacingSm),

                // --------------------------------------------------------------
                // ADD PLAYLIST
                // --------------------------------------------------------------
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: onCreatePlaylist,
                    icon: Icon(
                      Icons.add_rounded,
                      color: Colors.black,
                      size: 24 * iconScale,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// TAB WRAPPER
// =============================================================================

class _TabWrapper extends StatelessWidget {
  final Widget child;
  final String titleKey;
  final bool isHome;
  final bool showAppBar;
  final VoidCallback? onSearchTap;
  final VoidCallback? onCreatePlaylist;

  const _TabWrapper({
    super.key,
    required this.child,
    required this.titleKey,
    required this.isHome,
    this.showAppBar = true,
    this.onCreatePlaylist,
  }) : onSearchTap = null;

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  void _openSearch(BuildContext context) {
    if (titleKey == 'library') {
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

      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SearchScreen()));
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    final accentColor = settingsProvider.accentColor;

    final mq = MediaQuery.of(context);

    final textScale = mq.textScaler.scale(1.0);

    final double appBarIconScale = textScale > 1.0
        ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
        : 1.0;

    final bool isPlaylist = titleKey == 'playlists';

    // -------------------------------------------------------------------------
    // PLAYLIST
    // -------------------------------------------------------------------------

    if (isPlaylist) {
      return Scaffold(
        appBar: PlaylistMainAppBar(onCreatePlaylist: onCreatePlaylist ?? () {}),
        body: child,
      );
    }

    // -------------------------------------------------------------------------
    // NORMAL TABS
    // -------------------------------------------------------------------------

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              elevation: 0,
              titleSpacing: 0,

              title: Row(
                children: [
                  // ------------------------------------------------------------
                  // HOME PROFILE ICON
                  // ------------------------------------------------------------
                  if (isHome) ...[
                    SizedBox(width: AppDimens.spacingSm * appBarIconScale),

                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ProfileScreen(),
                          ),
                        );
                      },
                      child: CircleAvatar(
                        radius: 17 * appBarIconScale,
                        backgroundColor: accentColor.withValues(alpha: 0.22),
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 18 * appBarIconScale,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(width: AppDimens.spacingSm),
                  ],

                  // ------------------------------------------------------------
                  // TITLE
                  // ------------------------------------------------------------
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        left: isHome
                            ? 0
                            : AppDimens.spacingSm * appBarIconScale,
                      ),
                      child: Text(
                        isHome
                            ? 'Musix'
                            : titleKey == 'library'
                            ? 'Your library'
                            : titleKey.tr(),
                        style:
                            AppTextStyles.titleLg(
                              isDarkMode:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
                            ).copyWith(
                              fontSize: isHome
                                  ? AppTextStyles.fontSizeTitleLg + 2
                                  : titleKey == 'library'
                                  ? AppTextStyles.fontSizeTitleLg + 2
                                  : null,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),

                  // ------------------------------------------------------------
                  // HOME ACTIONS
                  // ------------------------------------------------------------
                  if (isHome) ...[
                    IconButton(
                      icon: Icon(
                        settingsProvider.themeMode == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        size: AppDimens.iconLg * appBarIconScale,
                      ),
                      onPressed: settingsProvider.toggleTheme,
                      tooltip: 'Toggle Theme',
                    ),

                    IconButton(
                      icon: Icon(
                        Icons.search_rounded,
                        size: AppDimens.iconLg * appBarIconScale,
                      ),
                      onPressed: () => _openSearch(context),
                      tooltip: 'Search',
                    ),
                  ],

                  // ------------------------------------------------------------
                  // LIBRARY ACTIONS
                  // ------------------------------------------------------------
                  if (titleKey == 'library') ...[
                    IconButton(
                      icon: Icon(
                        Icons.search_rounded,
                        size: AppDimens.iconLg * appBarIconScale,
                      ),
                      onPressed: () => _openSearch(context),
                      tooltip: 'Search',
                    ),

                    IconButton(
                      icon: Icon(
                        settingsProvider.themeMode == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        size: AppDimens.iconLg * appBarIconScale,
                      ),
                      onPressed: settingsProvider.toggleTheme,
                      tooltip: 'Toggle Theme',
                    ),
                  ],
                ],
              ),
            )
          : null,

      body: child,
    );
  }
}

// =============================================================================
// FULL PLAYER RESPONSIVE WRAPPER
// =============================================================================

class _MobileFullPlayerResponsiveWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwitchToDesktop;

  const _MobileFullPlayerResponsiveWrapper({
    required this.child,
    required this.onSwitchToDesktop,
  });

  @override
  State<_MobileFullPlayerResponsiveWrapper> createState() =>
      _MobileFullPlayerResponsiveWrapperState();
}

class _MobileFullPlayerResponsiveWrapperState
    extends State<_MobileFullPlayerResponsiveWrapper>
    with WidgetsBindingObserver {
  bool _hasSwitched = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted) return;

    final width = MediaQuery.of(context).size.width;

    if (!_hasSwitched && width >= 600) {
      _hasSwitched = true;

      widget.onSwitchToDesktop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

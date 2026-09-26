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
import '../../../ota/data/providers/ota_provider.dart';
import '../../../ota/presentation/widgets/ota_bottomsheet.dart';
import '../../../player/presentation/screens/player_ui.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';

import 'full_player_screen.dart';
import 'library_hub_screen.dart';

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
  // NAVIGATION
  // ---------------------------------------------------------------------------

  static const int _profileTabIndex = 3;

  void _goToProfile() {
    if (_controller.index != _profileTabIndex) {
      _controller.jumpToTab(_profileTabIndex);
    }
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
                      screen: _TabWrapper(
                        key: const ValueKey('home_tab'),
                        titleKey: 'home',
                        isHome: true,
                        onProfileTap: _goToProfile,
                        child: const HomeScreen(),
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
                    // LIBRARY (playlists + songs)
                    // ----------------------------------------------------------------
                    PersistentTabConfig(
                      screen: const _TabWrapper(
                        key: ValueKey('library_tab'),
                        titleKey: 'library',
                        isHome: false,
                        showAppBar: false,
                        child: LibraryHubScreen(),
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

                    // ----------------------------------------------------------------
                    // PROFILE
                    // ----------------------------------------------------------------
                    PersistentTabConfig(
                      screen: const _TabWrapper(
                        key: ValueKey('profile_tab'),
                        titleKey: 'profile',
                        isHome: false,
                        showAppBar: false,
                        child: ProfileScreen(),
                      ),
                      item: ItemConfig(
                        icon: Icon(Icons.person_rounded, size: navIconSize),
                        title: 'profile'.tr(),
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
// TAB WRAPPER
// =============================================================================

/// Gives a tab a [Scaffold] plus the standard app bar (avatar, title and
/// actions). Tabs that own their own header pass `showAppBar: false`.
class _TabWrapper extends StatelessWidget {
  final Widget child;
  final String titleKey;
  final bool isHome;
  final bool showAppBar;
  final VoidCallback? onProfileTap;

  const _TabWrapper({
    super.key,
    required this.child,
    required this.titleKey,
    required this.isHome,
    this.showAppBar = true,
    this.onProfileTap,
  });

  void _openSearch(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SearchScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    final accentColor = settingsProvider.accentColor;

    final mq = MediaQuery.of(context);

    final textScale = mq.textScaler.scale(1.0);

    final double appBarIconScale = textScale > 1.0
        ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
        : 1.0;

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
                      onTap: onProfileTap,
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
                        isHome ? 'Musix' : titleKey.tr(),
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
                      tooltip: 'toggle_theme'.tr(),
                    ),

                    IconButton(
                      icon: Icon(
                        Icons.search_rounded,
                        size: AppDimens.iconLg * appBarIconScale,
                      ),
                      onPressed: () => _openSearch(context),
                      tooltip: 'search'.tr(),
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

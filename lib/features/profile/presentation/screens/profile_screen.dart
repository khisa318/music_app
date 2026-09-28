import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../downloads/presentation/screens/downloads_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../settings/presentation/widgets/premium_card.dart';
import '../../../stats/presentation/screens/stats_screen.dart';

/// The Profile tab.
///
/// Built from the same primitives as the About page ([PremiumActionCard],
/// [PremiumGradientCard], [PremiumSocialButton], [PremiumSectionLabel]) so the
/// two read as one product: a soft accent header that fades into the page, a
/// glowing logo, and a version badge, over cards on the flat background
/// rather than bars of bare [Divider].
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Resolved once rather than per build, so the version badge does not kick
  /// off a fresh platform channel call every time the header rebuilds.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;
    final backgroundColor = MainScreenColors.getBackgroundColor(isDarkMode);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isDesktop = screenWidth >= AppDimens.breakpointDesktop;
        final isTablet =
            screenWidth >= AppDimens.breakpointTabletShort &&
            screenWidth < AppDimens.breakpointDesktop;
        final isMobile = !isDesktop && !isTablet;

        final horizontalPadding = isDesktop
            ? AppDimens.spacing4Xl
            : isTablet
            ? AppDimens.spacingXxl
            : AppDimens.paddingXl;
        final maxContentWidth = isDesktop
            ? AppDimens.maxContentWidth
            : double.infinity;
        final logoSize = isDesktop
            ? 120.0
            : isTablet
            ? 110.0
            : 100.0;
        final expandedHeight = isDesktop
            ? 330.0
            : isTablet
            ? 310.0
            : 320.0;

        return SafeArea(
          top: false,
          child: Scaffold(
            backgroundColor: backgroundColor,
            body: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildHeader(
                  context: context,
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                  backgroundColor: backgroundColor,
                  logoSize: logoSize,
                  expandedHeight: expandedHeight,
                  isMobile: isMobile,
                ),

                SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      padding: EdgeInsets.all(horizontalPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PremiumSectionLabel(
                            title: 'app_settings'.tr(),
                            isDarkMode: isDarkMode,
                          ),

                          PremiumActionCard(
                            icon: Icons.tune_rounded,
                            title: 'settings'.tr(),
                            subtitle: 'settings_subtitle'.tr(),
                            onTap: () =>
                                _navigateTo(context, const SettingsScreen()),
                            isDarkMode: isDarkMode,
                            accentColor: accentColor,
                          ),

                          const SizedBox(height: AppDimens.spacingMd),

                          PremiumActionCard(
                            icon: Icons.download_done_rounded,
                            title: 'downloads'.tr(),
                            subtitle: 'downloads_subtitle'.tr(),
                            onTap: () =>
                                _navigateTo(context, const DownloadsScreen()),
                            isDarkMode: isDarkMode,
                            accentColor: accentColor,
                          ),

                          const SizedBox(height: AppDimens.spacingMd),

                          PremiumActionCard(
                            icon: Icons.show_chart_rounded,
                            title: 'stats'.tr(),
                            subtitle: 'stats_subtitle'.tr(),
                            onTap: () =>
                                _navigateTo(context, const StatsScreen()),
                            isDarkMode: isDarkMode,
                            accentColor: accentColor,
                          ),

                          PremiumSectionLabel(
                            title: 'connect_with_us'.tr(),
                            isDarkMode: isDarkMode,
                          ),

                          PremiumGradientCard(
                            isDarkMode: isDarkMode,
                            accentColor: accentColor,
                            child: Padding(
                              padding: EdgeInsets.all(
                                isDesktop
                                    ? AppDimens.paddingXxl
                                    : AppDimens.paddingXl,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'connect_with_us_description'.tr(),
                                    textAlign: TextAlign.center,
                                    style:
                                        AppTextStyles.bodyMd(
                                          isDarkMode: isDarkMode,
                                        ).copyWith(
                                          color:
                                              MainScreenColors.getTextColor(
                                                isDarkMode,
                                              ).withValues(
                                                alpha: AppDimens.opacityMuted,
                                              ),
                                          height: AppTextStyles.lineHeightBody,
                                        ),
                                  ),

                                  const SizedBox(height: AppDimens.spacingXxl),

                                  Row(
                                    children: [
                                      PremiumSocialButton(
                                        icon: Icons.telegram,
                                        label: 'Telegram',
                                        onTap: () => _launchUrl(
                                          'https://t.me/NoizeUpdates',
                                        ),
                                        accentColor: accentColor,
                                        isDarkMode: isDarkMode,
                                      ),
                                      const SizedBox(
                                        width: AppDimens.spacingMd,
                                      ),
                                      PremiumSocialButton(
                                        icon: Icons.code_rounded,
                                        label: 'GitHub',
                                        onTap: () => _launchUrl(
                                          'https://github.com/anandssm/noize',
                                        ),
                                        accentColor: accentColor,
                                        isDarkMode: isDarkMode,
                                      ),
                                      const SizedBox(
                                        width: AppDimens.spacingMd,
                                      ),
                                      PremiumSocialButton(
                                        icon: Icons.language_rounded,
                                        label: 'Website',
                                        onTap: () => _launchUrl(
                                          'https://noizeapp.netlify.app/',
                                        ),
                                        accentColor: accentColor,
                                        isDarkMode: isDarkMode,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          PremiumSectionLabel(
                            title: 'share'.tr(),
                            isDarkMode: isDarkMode,
                          ),

                          PremiumActionCard(
                            icon: Icons.ios_share_rounded,
                            title: 'share_app'.tr(),
                            subtitle: 'share_subtitle'.tr(),
                            onTap: _shareApp,
                            isDarkMode: isDarkMode,
                            accentColor: accentColor,
                          ),

                          const SizedBox(height: AppDimens.paddingXl),
                        ],
                      ),
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

  /// The logo hero: a soft accent spotlight that fades into the page.
  Widget _buildHeader({
    required BuildContext context,
    required bool isDarkMode,
    required Color accentColor,
    required Color backgroundColor,
    required double logoSize,
    required double expandedHeight,
    required bool isMobile,
  }) {
    return SliverAppBar(
      expandedHeight: expandedHeight,
      floating: false,
      pinned: true,
      backgroundColor: backgroundColor,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accentColor.withValues(alpha: AppDimens.opacityMedium),
                backgroundColor,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: AppDimens.spacing4Xl),

                Container(
                  padding: const EdgeInsets.all(AppDimens.paddingXs),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor,
                        accentColor.withValues(alpha: AppDimens.opacityMid),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppDimens.radiusAvatar),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.4),
                        blurRadius: AppDimens.paddingXl,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusXxxl),
                    child: Image.asset(
                      'assets/default_artwork.png',
                      width: logoSize,
                      height: logoSize,
                    ),
                  ),
                ),

                const SizedBox(height: AppDimens.paddingXl),

                Text(
                  'app_name_noize'.tr(),
                  style: AppTextStyles.displayLg(
                    isDarkMode: isDarkMode,
                  ).copyWith(letterSpacing: -0.5),
                ),

                const SizedBox(height: AppDimens.spacingSm),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.paddingXl,
                  ),
                  child: Text(
                    'welcome'.tr(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLg(isDarkMode: isDarkMode)
                        .copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: AppDimens.opacityMuted),
                        ),
                  ),
                ),

                const SizedBox(height: AppDimens.spacingLg),

                _buildVersionBadge(accentColor, isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The accent version pill under the greeting.
  Widget _buildVersionBadge(Color accentColor, bool isMobile) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        final buildNumber = snapshot.data?.buildNumber ?? '';

        return Container(
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? AppDimens.paddingXs : AppDimens.paddingSm,
            horizontal: AppDimens.paddingXl,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accentColor, accentColor.withValues(alpha: 0.8)],
            ),
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: AppDimens.opacityOverlay),
                blurRadius: AppDimens.spacingSm,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            'v$version${buildNumber.isNotEmpty ? ' (${'build'.tr()} $buildNumber)' : ''}',
            style: (isMobile ? AppTextStyles.caption() : AppTextStyles.body2())
                .copyWith(
                  color: Colors.white,
                  fontWeight: AppTextStyles.weightSemiBold,
                ),
          ),
        );
      },
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (context) => screen));
  }

  Future<void> _shareApp() async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Check out MusiX - Your personal music companion!\nhttps://noizeapp.netlify.app/',
        subject: 'MusiX App',
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}

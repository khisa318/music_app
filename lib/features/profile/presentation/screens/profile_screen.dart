import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../settings/presentation/widgets/settings_item.dart';
import '../../../downloads/presentation/screens/downloads_screen.dart';
import '../../../stats/presentation/screens/stats_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;
    
    return Scaffold(
      backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor.withValues(alpha: 0.8), accentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: AppDimens.elevationMedium,
                            offset: const Offset(0, AppDimens.spacingS),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                        child: Image.asset(
                          'assets/default_artwork.png',
                          width: AppDimens.thumbnailLarge * 1.2,
                          height: AppDimens.thumbnailLarge * 1.2,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingMd),
                    Text(
                      'MusiX',
                      style: AppTextStyles.titleLg(isDarkMode: isDarkMode).copyWith(
                        color: Colors.white,
                        fontWeight: AppTextStyles.weightBold,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingXs),
                    Text(
                      'welcome'.tr(),
                      style: AppTextStyles.body2(
                        isDarkMode: isDarkMode,
                      ).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: AppDimens.spacingSm),
              _buildMainMenuSection(context, isDarkMode, accentColor),
              const Divider(height: AppDimens.spacingXxl),
              _buildSocialLinksSection(context, isDarkMode, accentColor),
              const Divider(height: AppDimens.spacingXxl),
              _buildShareSection(context, isDarkMode, accentColor),
              const SizedBox(height: AppDimens.paddingXl * 2),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildMainMenuSection(
    BuildContext context,
    bool isDarkMode,
    Color accentColor,
  ) {
    return SettingsGroup(
      title: 'app_settings'.tr(),
      icon: Icons.settings_rounded,
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      children: [
        SettingsItem(
          icon: Icons.tune_rounded,
          title: 'settings'.tr(),
          onTap: () => _navigateTo(context, const SettingsScreen()),
          isDarkMode: isDarkMode,
          accentColor: accentColor,
        ),
        SettingsItem(
          icon: Icons.download_done_rounded,
          title: 'downloads'.tr(),
          onTap: () => _navigateTo(context, const DownloadsScreen()),
          isDarkMode: isDarkMode,
          accentColor: accentColor,
        ),
        SettingsItem(
          icon: Icons.show_chart_rounded,
          title: 'stats'.tr(),
          onTap: () => _navigateTo(context, const StatsScreen()),
          isDarkMode: isDarkMode,
          accentColor: accentColor,
        ),
      ],
    );
  }

  Widget _buildSocialLinksSection(BuildContext context, bool isDarkMode, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.paddingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppDimens.paddingLg,
              bottom: AppDimens.spacingSm,
            ),
            child: Text(
              'connect_with_us'.tr(),
              style: AppTextStyles.bodyMd(isDarkMode: isDarkMode).copyWith(
                color: MainScreenColors.getTextColor(isDarkMode).withValues(alpha: 0.7),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialButton(
                context,
                icon: Icons.language,
                label: 'Website',
                url: 'https://noizeapp.netlify.app/',
                color: accentColor,
                isDarkMode: isDarkMode,
              ),
              _buildSocialButton(
                context,
                icon: Icons.telegram,
                label: 'Telegram',
                url: 'https://t.me/NoizeUpdates',
                color: accentColor,
                isDarkMode: isDarkMode,
              ),
              _buildSocialButton(
                context,
                icon: Icons.code,
                label: 'GitHub',
                url: 'https://github.com/anandssm/noize',
                color: accentColor,
                isDarkMode: isDarkMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareSection(
    BuildContext context,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.paddingLg),
      child: SettingsGroup(
        title: 'connect_with_us'.tr(),
        icon: Icons.ios_share_rounded,
        isDarkMode: isDarkMode,
        accentColor: accentColor,
        children: [
          SettingsItem(
            icon: Icons.share_rounded,
            title: 'share_app'.tr(),
            onTap: _shareApp,
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String url,
    required Color color,
    required bool isDarkMode,
  }) {
    return InkWell(
      onTap: () => _launchUrl(url),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppDimens.paddingMd),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: AppDimens.iconMd),
          ),
          const SizedBox(height: AppDimens.spacingXs),
          Text(label, style: AppTextStyles.caption(isDarkMode: isDarkMode)),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (context) => screen)
    );
  }

  Future<void> _shareApp() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Check out MusiX - Your personal music companion!\nhttps://noizeapp.netlify.app/',
        subject: 'MusiX App',
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    if (await launchUrl(Uri.parse(url))) {
      // success
    }
  }
}

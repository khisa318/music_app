import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/ota_model.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../main_screen/presentation/screens/full_player_screen.dart';
import '../../../ota/data/providers/ota_provider.dart';
import '../../../player/presentation/screens/player_ui.dart';
import '../widgets/appearance_settings_section.dart';
import '../widgets/audio_settings_section.dart';
import '../widgets/general_settings_section.dart';
import '../widgets/settings_item.dart';
import '../widgets/settings_surface.dart';
import 'about_screen.dart';
import 'export_import_settings.dart';
import '../../../ota/presentation/screens/ota_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsProvider = Provider.of<SettingsProvider>(
        context,
        listen: false,
      );
      if (settingsProvider.updateCheckEnabled) {
        final otaProvider = Provider.of<OTAProvider>(context, listen: false);
        if (otaProvider.status == OTAStatus.idle &&
            otaProvider.updateInfo == null) {
          otaProvider.checkForUpdates();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
      SettingsProvider,
      ({bool isDarkMode, Color accentColor, String language})
    >(
      selector: (context, settingsProvider) => (
        isDarkMode: settingsProvider.themeMode == ThemeMode.dark,
        accentColor: settingsProvider.accentColor,
        language: settingsProvider.language,
      ),
      builder: (context, themeData, child) {
        final isDarkMode = themeData.isDarkMode;
        final accentColor = themeData.accentColor;

        return Scaffold(
          backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
          appBar: SettingsAppBar(
            title: 'settings'.tr(),
            subtitle: 'app_tagline'.tr(),
            icon: Icons.tune_rounded,
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            showBackButton: Navigator.of(context).canPop(),
          ),
          body: Consumer<PlayerProvider>(
            builder: (context, playerProvider, child) {
              final hasPlayer =
                  playerProvider.currentSong != null ||
                  playerProvider.lastPlayedSong != null ||
                  playerProvider.currentLocalSong != null;

              final mq = MediaQuery.of(context);
              final textScale = mq.textScaler.scale(1.0);
              final double navIconScale =
                  textScale > 1.0
                  ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
                  : 1.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimens.paddingLg,
                        AppDimens.spacingXs,
                        AppDimens.paddingLg,
                        AppDimens.spacingXxl,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final int columns = AppDimens.settingsColumns(
                            width,
                          );
                          final spacing = AppDimens.spacingLg;
                          final columnWidth = columns == 1
                              ? double.infinity
                              : (width - (columns - 1) * spacing) / columns;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Consumer<OTAProvider>(
                                builder: (context, otaProvider, child) {
                                  if (!otaProvider.hasUpdate ||
                                      otaProvider.updateInfo == null) {
                                    return const SizedBox.shrink();
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppDimens.spacingXs,
                                    ),
                                    child: _buildUpdateBanner(
                                      context,
                                      otaProvider,
                                      isDarkMode,
                                      accentColor,
                                    ),
                                  );
                                },
                              ),

                              Wrap(
                                spacing: spacing,
                                runSpacing: AppDimens.spacingSm,
                                children: [
                                  SizedBox(
                                    width: columnWidth,
                                    child: const GeneralSettingsSection(),
                                  ),

                                  SizedBox(
                                    width: columnWidth,
                                    child: const AppearanceSettingsSection(),
                                  ),

                                  SizedBox(
                                    width: columnWidth,
                                    child: const AudioSettingsSection(),
                                  ),

                                  SizedBox(
                                    width: columnWidth,
                                    child: _buildAppUpdatesGroup(
                                      isDarkMode,
                                      accentColor,
                                    ),
                                  ),

                                  SizedBox(
                                    width: columnWidth,
                                    child: SettingsGroup(
                                      title: 'data_and_about'.tr(),
                                      icon: Icons.info_rounded,
                                      isDarkMode: isDarkMode,
                                      accentColor: accentColor,
                                      children: [
                                        SettingsItem(
                                          icon: Icons.swap_horiz_rounded,
                                          title:
                                              'export_import_settings_title'
                                                  .tr(),
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const ExportImportSettingsScreen(),
                                              ),
                                            );
                                          },
                                          isDarkMode: isDarkMode,
                                          accentColor: accentColor,
                                        ),
                                        SettingsItem(
                                          icon: Icons.info_rounded,
                                          title:
                                              'about_noize_card_title'.tr(),
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const AboutSettingsScreen(),
                                              ),
                                            );
                                          },
                                          isDarkMode: isDarkMode,
                                          accentColor: accentColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  if (AppDimens.isMobile(context) && hasPlayer)
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).appBarTheme.backgroundColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppDimens.radiusMd),
                        ),
                      ),
                      child: SizedBox(
                        height: AppDimens.miniPlayerHeight * navIconScale,
                        child: PlayerUI(
                          showFullScreen: false,
                          isEmbedded: true,
                          onMinimize: () {},
                          onExpand: () =>
                              _showFullPlayerBottomSheet(context),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showFullPlayerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => const FullPlayerScreen(),
    );
  }

  Widget _buildUpdateBanner(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    final updateInfo = otaProvider.updateInfo!;

    return SettingsSurface(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      padding: const EdgeInsets.all(AppDimens.paddingLg),
      color: accentColor.withValues(alpha: isDarkMode ? 0.10 : 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppDimens.paddingSm),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  color: accentColor,
                  size: AppDimens.iconMd,
                ),
              ),
              const SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ota_update_available'.tr(),
                      style: AppTextStyles.subtitle(
                        isDarkMode: isDarkMode,
                      ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
                    ),
                    Text(
                      'ota_version_and_size'.tr(
                        args: [updateInfo.latestVersion, updateInfo.size],
                      ),
                      style: AppTextStyles.caption(isDarkMode: isDarkMode)
                          .copyWith(
                            color: MainScreenColors.getTextColor(
                              isDarkMode,
                            ).withValues(alpha: AppDimens.opacityMuted),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.spacingSm),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OTAScreen()),
                  );
                },
                child: Text(
                  'view_button'.tr(),
                  style: AppTextStyles.bodyMd(
                    isDarkMode: isDarkMode,
                    color: accentColor,
                  ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
                ),
              ),
            ],
          ),
          if (updateInfo.updateLog.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingMd),
            Text(
              updateInfo.updateLog.first,
              style: AppTextStyles.body2(isDarkMode: isDarkMode).copyWith(
                color: MainScreenColors.getTextColor(
                  isDarkMode,
                ).withValues(alpha: AppDimens.opacityFaded),
                height: AppTextStyles.lineHeightBody,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppUpdatesGroup(bool isDarkMode, Color accentColor) {
    return SettingsGroup(
      title: 'app_updates'.tr(),
      icon: Icons.system_update_rounded,
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      children: [
        Consumer<OTAProvider>(
          builder: (context, otaProvider, child) {
            final isChecking = otaProvider.status == OTAStatus.checking;

            return SettingsItem(
              icon: isChecking
                  ? Icons.sync_rounded
                  : Icons.system_update_alt_rounded,
              title: otaProvider.status == OTAStatus.updateAvailable
                  ? 'update_available_item_title'.tr(
                      args: [otaProvider.updateInfo?.latestVersion ?? ''],
                    )
                  : 'ota_check_for_updates'.tr(),
              showChevron: !isChecking,
              trailing: isChecking
                  ? SizedBox(
                      width: AppDimens.iconMd,
                      height: AppDimens.iconMd,
                      child: CircularProgressIndicator(
                        strokeWidth: AppDimens.progressStroke,
                        color: accentColor,
                      ),
                    )
                  : null,
              onTap: isChecking
                  ? null
                  : () {
                      // The row is labelled "Check for updates", so it has to
                      // check. Pushing the screen on its own rendered whatever
                      // the last startup check happened to decide, so a user
                      // who had skipped a version was told "you are on the
                      // latest version" seconds after the app itself had
                      // advertised an update - the app contradicting itself.
                      // The check runs before the push so the screen opens on
                      // a spinner and lands on the real answer.
                      context.read<OTAProvider>().checkForUpdates(
                        showNoUpdateMessage: true,
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const OTAScreen(),
                        ),
                      );
                    },
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            );
          },
        ),
      ],
    );
  }
}

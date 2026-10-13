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
import '../widgets/custom_dropdown.dart';
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
          backgroundColor: Colors.transparent,
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
                                              'about_musix_card_title'.tr(),
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

  /// The single home for everything update-related.
  ///
  /// This used to be split: a floating banner above the grid and this group
  /// both announced the same version, and the automatic-check toggle plus the
  /// channel picker lived over in General Settings. Everything now sits in one
  /// themed card and the update story is told exactly once.
  Widget _buildAppUpdatesGroup(bool isDarkMode, Color accentColor) {
    return SettingsGroup(
      title: 'app_updates'.tr(),
      icon: Icons.system_update_rounded,
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      children: [
        Consumer<OTAProvider>(
          builder: (context, otaProvider, child) {
            final info = otaProvider.updateInfo;
            if (!otaProvider.hasUpdate || info == null) {
              return const SizedBox.shrink();
            }
            return _buildUpdateHeroTile(info, isDarkMode, accentColor);
          },
        ),
        Consumer<OTAProvider>(
          builder: (context, otaProvider, child) {
            final isChecking = otaProvider.status == OTAStatus.checking;

            return SettingsItem(
              icon: isChecking
                  ? Icons.sync_rounded
                  : Icons.system_update_alt_rounded,
              title: 'ota_check_for_updates'.tr(),
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
              onTap: isChecking ? null : _openUpdateScreen,
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            );
          },
        ),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsToggleItem(
              icon: Icons.schedule_rounded,
              title: 'automatic_update_checks'.tr(),
              value: settingsProvider.updateCheckEnabled,
              onChanged: (value) {
                settingsProvider.updateCheckEnabled = value;
              },
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            );
          },
        ),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem(
              icon: Icons.alt_route_rounded,
              title: 'update_channel'.tr(),
              showChevron: false,
              trailing: CustomDropdown<String>(
                value: settingsProvider.updateChannel,
                items: const ['stable', 'beta'],
                onChanged: (value) {
                  if (value == null) return;
                  settingsProvider.updateChannel = value;
                  final otaProvider = context.read<OTAProvider>();
                  otaProvider.setUpdateChannel(value);
                  if (settingsProvider.updateCheckEnabled) {
                    otaProvider.checkForUpdates();
                  }
                },
                isDarkMode: isDarkMode,
                accentColor: accentColor,
              ),
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            );
          },
        ),
      ],
    );
  }

  Widget _buildUpdateHeroTile(
    OTAUpdateInfo info,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openUpdateScreen,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        splashColor: accentColor.withValues(alpha: 0.08),
        highlightColor: accentColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLg,
            vertical: AppDimens.paddingMd,
          ),
          child: Row(
            children: [
              Container(
                width: AppDimens.buttonSizeLg,
                height: AppDimens.buttonSizeLg,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: Colors.white,
                  size: AppDimens.iconMd,
                ),
              ),
              const SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'update_available_item_title'.tr(
                        args: [info.latestVersion],
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLg(
                        isDarkMode: isDarkMode,
                      ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
                    ),
                    const SizedBox(height: AppDimens.spacingXxs),
                    Text(
                      'ota_update_size'.tr(args: [info.size]),
                      style: AppTextStyles.caption(
                        isDarkMode: isDarkMode,
                      ).copyWith(
                        color: MainScreenColors.getTextColor(
                          isDarkMode,
                        ).withValues(alpha: AppDimens.opacityMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.spacingSm),
              SettingsChevron(
                isDarkMode: isDarkMode,
                accentColor: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Runs an explicit check, then opens the update screen so it lands on the
  /// real answer rather than whatever the last startup check decided.
  void _openUpdateScreen() {
    context.read<OTAProvider>().checkForUpdates(showNoUpdateMessage: true);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OTAScreen()),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_dimens.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/glass_modal.dart';
import '../../../settings/presentation/widgets/custom_dropdown.dart';
import '../../../settings/presentation/widgets/settings_item.dart';

/// Bottom-sheet wrapper around the download-related [SettingsGroup] rows, so
/// the Downloads screen can offer the same controls as Settings without a
/// detour through the settings tab.
class DownloadSettingsSheet extends StatelessWidget {
  const DownloadSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const DownloadSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDarkMode = settings.theme == 'Dark';
    final accentColor = settings.accentColor;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: GlassSheet(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXxl),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.paddingLg,
              AppDimens.paddingMd,
              AppDimens.paddingLg,
              AppDimens.paddingLg,
            ),
            child: SettingsGroup(
              title: 'download_settings'.tr(),
              icon: Icons.download_rounded,
              isDarkMode: isDarkMode,
              accentColor: accentColor,
              children: [
                SettingsItem(
                  icon: Icons.high_quality_rounded,
                  title: 'downloading_quality_card_title'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settings.downloadingQuality,
                    items: const ['Low', 'Medium', 'High'],
                    onChanged: (value) {
                      if (value != null) {
                        settings.downloadingQuality = value;
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                    subtitle: 'select_downloading_quality'.tr(),
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                ),
                SettingsToggleItem(
                  icon: Icons.wifi_rounded,
                  title: 'wifi_only_downloads'.tr(),
                  value: settings.wifiOnlyDownloads,
                  onChanged: (value) {
                    settings.wifiOnlyDownloads = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                ),
                SettingsItem(
                  icon: Icons.download_for_offline_rounded,
                  title: 'concurrent_downloads'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settings.maxConcurrentDownloads.toString(),
                    items: const ['1', '2', '3', '4'],
                    onChanged: (value) {
                      if (value != null) {
                        settings.maxConcurrentDownloads = int.parse(value);
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                    subtitle: 'select_max_concurrent_downloads'.tr(),
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                ),
                SettingsToggleItem(
                  icon: Icons.notifications_rounded,
                  title: 'notifications_card_title'.tr(),
                  value: settings.notificationsEnabled,
                  onChanged: (value) {
                    settings.notificationsEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

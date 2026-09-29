
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../../equalizer/presentation/screens/equalizer_screen.dart';
import '../screens/ai_api_config_screen.dart';
import 'custom_dropdown.dart';
import 'settings_item.dart';

class AudioSettingsSection extends StatelessWidget {
  const AudioSettingsSection({super.key});

  static bool get _isEqualizerSupported => true;

  @override
  Widget build(BuildContext context) {
    return Selector<
      SettingsProvider,
      ({bool isDarkMode, Color accentColor, String lyricsProvider})
    >(
      selector: (context, settingsProvider) => (
        isDarkMode: settingsProvider.themeMode == ThemeMode.dark,
        accentColor: settingsProvider.accentColor,
        lyricsProvider: settingsProvider.lyricsProvider,
      ),
      builder: (context, themeData, child) {
        final isDarkMode = themeData.isDarkMode;
        final accentColor = themeData.accentColor;

        return SettingsGroup(
          title: 'audio_settings'.tr(),
          icon: Icons.graphic_eq_rounded,
          isDarkMode: isDarkMode,
          accentColor: accentColor,
          children: [
            if (_isEqualizerSupported)
              SettingsItem(
                icon: Icons.equalizer_rounded,
                title: 'equalizer_card_title'.tr(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EqualizerScreen(),
                    ),
                  );
                },
                isDarkMode: isDarkMode,
                accentColor: accentColor,
              ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.stream_rounded,
                  title: 'streaming_quality_card_title'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settingsProvider.streamingQuality,
                    items: ['Low', 'Medium', 'High'],
                    onChanged: (value) {
                      if (value != null) {
                        settingsProvider.streamingQuality = value;
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                    subtitle: 'select_streaming_quality'.tr(),
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.sd_storage_rounded,
                  title: 'audio_cache_enabled'.tr(),
                  value: settingsProvider.audioCacheEnabled,
                  onChanged: (value) {
                    settingsProvider.audioCacheEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.download_rounded,
                  title: 'downloading_quality_card_title'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settingsProvider.downloadingQuality,
                    items: ['Low', 'Medium', 'High'],
                    onChanged: (value) {
                      if (value != null) {
                        settingsProvider.downloadingQuality = value;
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                    subtitle: 'select_downloading_quality'.tr(),
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.wifi_rounded,
                  title: 'wifi_only_downloads'.tr(),
                  value: settingsProvider.wifiOnlyDownloads,
                  onChanged: (value) {
                    settingsProvider.wifiOnlyDownloads = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.download_for_offline_rounded,
                  title: 'concurrent_downloads'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settingsProvider.maxConcurrentDownloads
                        .toString(),
                    items: ['1', '2', '3', '4'],
                    onChanged: (value) {
                      if (value != null) {
                        settingsProvider.maxConcurrentDownloads = int.parse(
                          value,
                        );
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                    subtitle: 'select_max_concurrent_downloads'.tr(),
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.high_quality_rounded,
                  title: 'jio_saavn_card_title'.tr(),
                  value: settingsProvider.jioSaavnEnabled,
                  onChanged: (value) {
                    settingsProvider.jioSaavnEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.queue_music_rounded,
                  title: 'gapless_playback'.tr(),
                  value: settingsProvider.gaplessPlaybackEnabled,
                  onChanged: (value) {
                    settingsProvider.gaplessPlaybackEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.music_note_rounded,
                  title: 'lyrics_provider_card_title'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settingsProvider.lyricsProvider,
                    items: ['LRCLib', 'YT Music', 'AI'],
                    onChanged: (value) {
                      if (value != null) {
                        settingsProvider.lyricsProvider = value;
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                    subtitle: 'select_lyrics_provider'.tr(),
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            if (themeData.lyricsProvider == 'AI')
              SettingsItem(
                icon: Icons.vpn_key_rounded,
                title: 'ai_api_config_card_title'.tr(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AiApiConfigScreen(),
                    ),
                  );
                },
                isDarkMode: isDarkMode,
                accentColor: accentColor,
              ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.history_rounded,
                  title: 'playback_history_card_title'.tr(),
                  value: settingsProvider.playbackHistoryEnabled,
                  onChanged: (value) {
                    settingsProvider.playbackHistoryEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.manage_search_rounded,
                  title: 'search_history_card_title'.tr(),
                  value: settingsProvider.searchHistoryEnabled,
                  onChanged: (value) {
                    settingsProvider.searchHistoryEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

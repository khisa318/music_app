import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';
import 'library_screen.dart';
import '../../../playlists/presentation/screens/playlists_screen.dart';

class CombinedLibraryScreen extends StatelessWidget {
  const CombinedLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: MainScreenColors.getBackgroundColor(isDarkMode),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            color: MainScreenColors.getBackgroundColor(isDarkMode),
            child: TabBar(
              indicatorColor: accentColor,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: accentColor,
              unselectedLabelColor: isDarkMode ? Colors.white70 : Colors.black54,
              labelStyle: AppTextStyles.subtitle(isDarkMode: isDarkMode)
                  .copyWith(fontWeight: FontWeight.bold),
              unselectedLabelStyle: AppTextStyles.subtitle(isDarkMode: isDarkMode),
              tabs: [
                Tab(text: 'playlists'.tr()),
                Tab(text: 'library'.tr()),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            PlaylistScreen(),
            LibraryScreen(),
          ],
        ),
      ),
    );
  }
}

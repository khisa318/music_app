import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/models/ota_model.dart';
import '../../data/providers/ota_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../screens/ota_screen.dart';
import 'update_method_dialog.dart';
import 'update_summary.dart';

/// The update prompt shown over the app when a new release is found.
///
/// A plain [AlertDialog] rather than a bottom sheet: the sheet could slide up
/// behind the mini player and the navigation bar on small screens, leaving the
/// buttons half-covered. A centred dialog is always fully reachable.
class OTADialog extends StatelessWidget {
  final OTAUpdateInfo updateInfo;

  const OTADialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, OTAUpdateInfo updateInfo) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OTADialog(updateInfo: updateInfo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;
    final otaProvider = Provider.of<OTAProvider>(context);
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return AlertDialog(
      backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingXxl,
        vertical: AppDimens.paddingXxl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
      ),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(
        AppDimens.paddingXxl,
        0,
        AppDimens.paddingXxl,
        AppDimens.paddingXxl,
      ),
      title: Container(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.paddingXxl,
          AppDimens.paddingLg,
          AppDimens.paddingMd,
          AppDimens.paddingLg,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withValues(alpha: isDarkMode ? 0.22 : 0.14),
              accentColor.withValues(alpha: isDarkMode ? 0.08 : 0.04),
            ],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppDimens.radiusXxl),
            topRight: Radius.circular(AppDimens.radiusXxl),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.system_update_alt_rounded,
              color: accentColor,
              size: AppDimens.iconXl,
            ),
            const SizedBox(width: AppDimens.spacingMd),
            Expanded(
              child: Text(
                'new_update_available'.tr(),
                style: AppTextStyles.titleLg(isDarkMode: isDarkMode),
              ),
            ),
            IconButton(
              tooltip: 'ota_update_later'.tr(),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                color: textColor.withValues(alpha: AppDimens.opacityMuted),
                size: AppDimens.iconLg,
              ),
              onPressed: () {
                Navigator.pop(context);
                otaProvider.setUpdateUIShown(true);
              },
            ),
          ],
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppDimens.spacingXl),
          UpdateVersionRow(
            updateInfo: updateInfo,
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
          const SizedBox(height: AppDimens.spacingLg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: UpdateNoteList(
                updateInfo: updateInfo,
                isDarkMode: isDarkMode,
                maxItems: 6,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.spacingXxl),
          SizedBox(
            width: double.infinity,
            height: AppDimens.buttonHeightLarge,
            child: ElevatedButton(
              onPressed: () async {
                // Capture the navigator before awaiting the method dialog.
                // This dialog is dismissed below, so its own context is
                // disposed by the time the user picks an option - resolving
                // `Navigator.of(context)` afterwards would find nothing and
                // the choice would silently do nothing.
                final navigator = Navigator.of(context);
                final choice = await UpdateMethodDialog.show(
                  context,
                  updateInfo,
                );
                if (!context.mounted) return;

                // Dismiss the prompt now that a choice has been made.
                navigator.pop();

                switch (choice) {
                  case UpdateChoice.downloadInApp:
                    otaProvider.setOTAScreenActive(true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      navigator
                          .push(
                            MaterialPageRoute(
                              builder: (context) => const OTAScreen(),
                            ),
                          )
                          .then((_) {
                            otaProvider.setOTAScreenActive(false);
                            otaProvider.setUpdateUIShown(false);
                          });
                    });
                  case UpdateChoice.openWebsite:
                    await otaProvider.openReleasePage();
                  case null:
                    break;
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
              ),
              child: Text(
                'update_now'.tr(),
                style: AppTextStyles.subtitle(
                  isDarkMode: isDarkMode,
                ).copyWith(fontWeight: AppTextStyles.weightBold),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.spacingXs),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                otaProvider.skipVersion();
                Navigator.pop(context);
                otaProvider.setUpdateUIShown(false);
              },
              style: TextButton.styleFrom(
                foregroundColor: textColor.withValues(
                  alpha: AppDimens.opacityMuted,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
              ),
              child: Text(
                'skip_this_version'.tr(),
                style: AppTextStyles.bodyMd(
                  isDarkMode: isDarkMode,
                ).copyWith(fontWeight: AppTextStyles.weightMedium),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

class OTADialog extends StatelessWidget {
  final OTAUpdateInfo updateInfo;

  const OTADialog({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;
    final otaProvider = Provider.of<OTAProvider>(context);

    return PopScope(
      canPop: true,
      child: AlertDialog(
        backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
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
          padding: const EdgeInsets.symmetric(
            vertical: AppDimens.paddingXl,
            horizontal: AppDimens.paddingXxl,
          ),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppDimens.radiusXxl),
              topRight: Radius.circular(AppDimens.radiusXxl),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt,
                color: accentColor,
                size: AppDimens.iconXxl,
              ),
              const SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Text(
                  'new_update_available'.tr(),
                  style: AppTextStyles.titleLg(
                    isDarkMode: isDarkMode,
                  ).copyWith(color: accentColor),
                ),
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
                  Navigator.pop(context);
                  final choice = await UpdateMethodDialog.show(
                    context,
                    updateInfo,
                  );
                  if (!context.mounted) return;

                  switch (choice) {
                    case UpdateChoice.downloadInApp:
                      otaProvider.setOTAScreenActive(true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const OTAScreen(),
                          ),
                        ).then((_) {
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
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.spacingSm),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    otaProvider.skipVersion();
                    Navigator.pop(context);
                    otaProvider.setUpdateUIShown(false);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: MainScreenColors.getTextColor(
                      isDarkMode,
                    ).withValues(alpha: 0.7),
                  ),
                  child: Text(
                    'skip_this_version',
                    style: AppTextStyles.bodyMd(
                      isDarkMode: isDarkMode,
                    ).copyWith(fontWeight: AppTextStyles.weightMedium),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

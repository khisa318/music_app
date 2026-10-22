import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/glass_modal.dart';
import '../../data/providers/ota_provider.dart';

/// Prompt shown once an in-app update download finishes on its own, handing the
/// user straight to Android's installer.
///
/// Deliberately a small dialog rather than a full screen: the download already
/// happened in the background, so all that is left is the user's "yes".
class OTAInstallDialog extends StatelessWidget {
  const OTAInstallDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showGlassDialog<void>(
      context: context,
      builder: (_) => const OTAInstallDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDarkMode = settings.themeMode == ThemeMode.dark;
    final accentColor = settings.accentColor;
    final otaProvider = Provider.of<OTAProvider>(context, listen: false);
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return AlertDialog(
      backgroundColor: glassDialogColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
      ),
      icon: Icon(
        Icons.system_update_alt_rounded,
        color: accentColor,
        size: AppDimens.iconXl,
      ),
      title: Text(
        'ota_download_complete'.tr(),
        textAlign: TextAlign.center,
        style: AppTextStyles.titleLg(isDarkMode: isDarkMode),
      ),
      content: Text(
        'ota_ready_to_install_message'.tr(),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMd(
          isDarkMode: isDarkMode,
        ).copyWith(color: textColor.withValues(alpha: AppDimens.opacityMuted)),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: textColor.withValues(
              alpha: AppDimens.opacityMuted,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            ),
          ),
          child: Text(
            'ota_update_later'.tr(),
            style: AppTextStyles.bodyMd(
              isDarkMode: isDarkMode,
            ).copyWith(fontWeight: AppTextStyles.weightMedium),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            otaProvider.installUpdate();
          },
          icon: const Icon(
            Icons.install_mobile_rounded,
            size: AppDimens.iconSm,
          ),
          label: Text('ota_install_update'.tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            ),
          ),
        ),
      ],
    );
  }
}

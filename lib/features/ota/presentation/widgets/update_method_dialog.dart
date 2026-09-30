import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/ota_model.dart';
import '../../../../core/providers/settings_provider.dart';

/// What the user chose after tapping "Update now".
enum UpdateChoice {
  /// Download the APK inside MusiX and hand it to Android's installer.
  downloadInApp,

  /// Open the GitHub release page in the device browser.
  openWebsite,
}

/// Asked right after the user taps "Update now".
///
/// Kept as a separate dialog rather than a straight jump to the download so
/// the choice is explicit: some users prefer their browser and their
/// download manager, and both paths end at the same APK.
class UpdateMethodDialog extends StatelessWidget {
  const UpdateMethodDialog({super.key, required this.updateInfo});

  final OTAUpdateInfo updateInfo;

  /// Shows the dialog and resolves to the user's choice, or `null` if they
  /// backed out without picking.
  static Future<UpdateChoice?> show(
    BuildContext context,
    OTAUpdateInfo updateInfo,
  ) {
    return showDialog<UpdateChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateMethodDialog(updateInfo: updateInfo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return AlertDialog(
      backgroundColor: MainScreenColors.getSurfaceColor(isDarkMode),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppDimens.paddingXxl,
        AppDimens.paddingXxl,
        AppDimens.paddingXxl,
        0,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppDimens.paddingXxl,
        AppDimens.paddingXl,
        AppDimens.paddingXxl,
        AppDimens.paddingXxl,
      ),
      title: Row(
        children: [
          Icon(
            Icons.help_outline_rounded,
            color: accentColor,
            size: AppDimens.iconXxl,
          ),
          const SizedBox(width: AppDimens.spacingMd),
          Expanded(
            child: Text(
              'ota_choose_update_method'.tr(),
              style: AppTextStyles.titleLg(
                isDarkMode: isDarkMode,
              ).copyWith(color: accentColor),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ota_choose_update_method_message'.tr(
              args: [updateInfo.latestVersion],
            ),
            style: AppTextStyles.bodyMd(
              isDarkMode: isDarkMode,
            ).copyWith(color: textColor.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: AppDimens.spacingXl),
          _ChoiceTile(
            icon: Icons.download_rounded,
            title: 'ota_update_in_app'.tr(),
            subtitle: 'ota_update_in_app_subtitle'.tr(args: [updateInfo.size]),
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            onTap: () => Navigator.of(context).pop(UpdateChoice.downloadInApp),
          ),
          const SizedBox(height: AppDimens.spacingMd),
          _ChoiceTile(
            icon: Icons.open_in_browser_rounded,
            title: 'ota_update_open_website'.tr(),
            subtitle: 'ota_update_open_website_subtitle'.tr(),
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            onTap: () => Navigator.of(context).pop(UpdateChoice.openWebsite),
          ),
          const SizedBox(height: AppDimens.spacingLg),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: textColor.withValues(alpha: 0.7),
            ),
            child: Text(
              'ota_update_later'.tr(),
              style: AppTextStyles.bodyMd(
                isDarkMode: isDarkMode,
              ).copyWith(fontWeight: AppTextStyles.weightMedium),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDarkMode,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDarkMode;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accentColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.paddingLg),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppDimens.paddingSm),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: Icon(icon, color: accentColor, size: AppDimens.iconMd),
              ),
              const SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.subtitle(
                        isDarkMode: isDarkMode,
                      ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
              Icon(
                Icons.chevron_right_rounded,
                color: accentColor,
                size: AppDimens.iconMd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

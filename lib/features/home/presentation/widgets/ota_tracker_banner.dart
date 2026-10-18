import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/ota_model.dart';
import '../../../ota/data/providers/ota_provider.dart';
import '../../../ota/presentation/screens/ota_screen.dart';

/// A compact strip pinned at the very top of Home that narrates an in-app
/// update: the download as it happens, and the install once it is ready.
///
/// It sits directly above [DownloadTrackerBanner] and renders nothing unless an
/// update is actually in flight (available, downloading, paused, downloaded or
/// failed), so anyone on the latest version never sees it.
class OtaTrackerBanner extends StatelessWidget {
  const OtaTrackerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OTAProvider>(
      builder: (context, ota, _) {
        final info = ota.updateInfo;
        final status = ota.status;

        final visible =
            info != null &&
            (status == OTAStatus.updateAvailable ||
                status == OTAStatus.downloading ||
                status == OTAStatus.paused ||
                status == OTAStatus.downloaded ||
                status == OTAStatus.error);

        if (!visible) return const SizedBox.shrink();

        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final accentColor = Theme.of(context).colorScheme.primary;
        final textColor = MainScreenColors.getTextColor(isDarkMode);

        final progress = ota.downloadProgress;
        final isDownloading = status == OTAStatus.downloading;
        final isPaused = status == OTAStatus.paused;
        final showProgress = isDownloading || isPaused;
        final double value = progress != null
            ? (progress.percentage / 100).clamp(0.0, 1.0)
            : 0.0;
        final int percent = (value * 100).round();

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.spacingSm,
            AppDimens.paddingLg,
            AppDimens.spacingXs,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openOtaScreen(context, ota),
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              child: Container(
                padding: const EdgeInsets.all(AppDimens.paddingMd),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: isDarkMode ? 0.16 : 0.09),
                      accentColor.withValues(alpha: isDarkMode ? 0.06 : 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.28),
                    width: AppDimens.borderWidthThin,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.06),
                      blurRadius: AppDimens.paddingSm,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _iconFor(status),
                          size: AppDimens.iconSm,
                          color: accentColor,
                        ),
                        const SizedBox(width: AppDimens.spacingSm),
                        Expanded(
                          child: Text(
                            _titleFor(status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption(isDarkMode: isDarkMode)
                                .copyWith(
                                  color: accentColor,
                                  fontWeight: AppTextStyles.weightSemiBold,
                                ),
                          ),
                        ),
                        Text(
                          showProgress
                              ? '$percent%'
                              : (status == OTAStatus.error
                                    ? ''
                                    : 'v${info.latestVersion}'),
                          style: AppTextStyles.caption(
                            isDarkMode: isDarkMode,
                          ).copyWith(
                            color: textColor.withValues(
                              alpha: AppDimens.opacityMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimens.spacingXs),
                    Text(
                      _subtitleFor(ota, status),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(isDarkMode: isDarkMode)
                          .copyWith(
                            color: textColor.withValues(
                              alpha: AppDimens.opacityMuted,
                            ),
                          ),
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: AppDimens.spacingSm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppDimens.radiusXxs),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: accentColor.withValues(alpha: 0.18),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppDimens.spacingSm),
                    _buildActions(
                      context,
                      ota,
                      status,
                      accentColor,
                      isDarkMode,
                      textColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildActions(
    BuildContext context,
    OTAProvider ota,
    OTAStatus status,
    Color accentColor,
    bool isDarkMode,
    Color textColor,
  ) {
    final actions = <Widget>[];

    switch (status) {
      case OTAStatus.updateAvailable:
        actions.add(
          _BannerButton(
            icon: Icons.download_rounded,
            label: 'ota_download_update'.tr(),
            color: accentColor,
            onPressed: () => ota.downloadUpdate(),
          ),
        );
      case OTAStatus.downloading:
        actions.add(
          _BannerButton(
            icon: Icons.pause_rounded,
            label: 'ota_pause_download'.tr(),
            color: textColor,
            onPressed: () => ota.pauseDownload(),
          ),
        );
        actions.add(
          _BannerButton(
            icon: Icons.delete_outline_rounded,
            label: 'ota_cancel_download'.tr(),
            color: textColor,
            onPressed: () => ota.cancelDownload(),
          ),
        );
      case OTAStatus.paused:
        actions.add(
          _BannerButton(
            icon: Icons.play_arrow_rounded,
            label: 'ota_resume_download'.tr(),
            color: accentColor,
            onPressed: () => ota.resumeDownload(),
          ),
        );
        actions.add(
          _BannerButton(
            icon: Icons.delete_outline_rounded,
            label: 'ota_discard_download'.tr(),
            color: textColor,
            onPressed: () => ota.cancelDownload(),
          ),
        );
      case OTAStatus.downloaded:
        actions.add(
          _BannerButton(
            icon: Icons.install_mobile_rounded,
            label: 'ota_install_update'.tr(),
            color: accentColor,
            onPressed: () => ota.installUpdate(),
          ),
        );
      case OTAStatus.error:
        actions.add(
          _BannerButton(
            icon: Icons.refresh_rounded,
            label: 'ota_try_again'.tr(),
            color: accentColor,
            onPressed: () => ota.downloadUpdate(),
          ),
        );
      default:
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: actions
          .map(
            (action) => Padding(
              padding: const EdgeInsets.only(left: AppDimens.spacingSm),
              child: action,
            ),
          )
          .toList(growable: false),
    );
  }

  // ---------------------------------------------------------------------------
  // TEXT
  // ---------------------------------------------------------------------------

  static String _titleFor(OTAStatus status) {
    switch (status) {
      case OTAStatus.updateAvailable:
        return 'ota_update_available'.tr();
      case OTAStatus.downloading:
        return 'ota_downloading_update'.tr();
      case OTAStatus.paused:
        return 'ota_download_paused'.tr();
      case OTAStatus.downloaded:
        return 'ota_download_complete'.tr();
      case OTAStatus.error:
        return 'ota_update_failed'.tr();
      default:
        return 'new_update_available'.tr();
    }
  }

  static String _subtitleFor(OTAProvider ota, OTAStatus status) {
    switch (status) {
      case OTAStatus.updateAvailable:
        return 'wifi_only_downloads'.tr();
      case OTAStatus.downloading:
      case OTAStatus.paused:
        final progress = ota.downloadProgress;
        if (progress == null) return 'ota_downloading_update'.tr();
        if (progress.formattedTotal.isEmpty) {
          return progress.formattedDownloaded;
        }
        return '${progress.formattedDownloaded} / ${progress.formattedTotal}';
      case OTAStatus.downloaded:
        return 'ota_ready_to_install_message'.tr();
      case OTAStatus.error:
        return ota.errorMessage ?? 'ota_update_failed_message'.tr();
      default:
        return '';
    }
  }

  static IconData _iconFor(OTAStatus status) {
    switch (status) {
      case OTAStatus.downloaded:
        return Icons.check_circle_rounded;
      case OTAStatus.paused:
        return Icons.pause_circle_filled_rounded;
      case OTAStatus.error:
        return Icons.error_rounded;
      default:
        return Icons.system_update_alt_rounded;
    }
  }

  void _openOtaScreen(BuildContext context, OTAProvider ota) {
    ota.setOTAScreenActive(true);
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const OTAScreen()))
        .then((_) => ota.setOTAScreenActive(false));
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: AppDimens.iconSm),
      label: Text(
        label,
        style: AppTextStyles.caption(
          isDarkMode: isDarkMode,
        ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
      ),
      style: TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingSm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
      ),
    );
  }
}

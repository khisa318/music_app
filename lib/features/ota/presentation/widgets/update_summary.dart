import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/ota_model.dart';

/// `1.1.0  ->  1.2.0`, with the release date and download size underneath.
///
/// Used by the update bottom sheet, the dialog and the update screen so the
/// version story reads identically wherever the prompt appears.
class UpdateVersionRow extends StatelessWidget {
  const UpdateVersionRow({
    super.key,
    required this.updateInfo,
    required this.isDarkMode,
    required this.accentColor,
  });

  final OTAUpdateInfo updateInfo;
  final bool isDarkMode;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final muted = MainScreenColors.getTextColor(
      isDarkMode,
    ).withValues(alpha: AppDimens.opacityMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              updateInfo.installedVersion,
              style: AppTextStyles.subtitle(isDarkMode: isDarkMode).copyWith(
                color: muted,
                fontWeight: AppTextStyles.weightSemiBold,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.spacingSm,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: AppDimens.iconMd,
                color: accentColor,
              ),
            ),
            Text(
              updateInfo.latestVersion,
              style: AppTextStyles.titleSm(isDarkMode: isDarkMode).copyWith(
                color: accentColor,
                fontWeight: AppTextStyles.weightBold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.spacingXs),
        Text(
          'ota_update_meta'.tr(
            args: [updateInfo.size, _formatDate(updateInfo.releaseDate)],
          ),
          style: AppTextStyles.caption(
            isDarkMode: isDarkMode,
          ).copyWith(color: muted),
        ),
        if (updateInfo.isPrerelease) ...[
          const SizedBox(height: AppDimens.spacingXs),
          _Badge(label: 'ota_prerelease'.tr(), color: accentColor),
        ],
      ],
    );
  }

  static String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    return DateFormat('d MMM yyyy').format(date);
  }
}

/// The release's own changelog, rendered as a bullet list.
///
/// Content comes from the GitHub release body - nothing is hard-coded in the
/// app - so the dialog can never claim a change that is not in the release.
class UpdateNoteList extends StatelessWidget {
  const UpdateNoteList({
    super.key,
    required this.updateInfo,
    required this.isDarkMode,
    this.maxItems,
  });

  final OTAUpdateInfo updateInfo;
  final bool isDarkMode;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    final items = maxItems == null
        ? updateInfo.updateLog
        : updateInfo.updateLog.take(maxItems!).toList();

    if (items.isEmpty) {
      // No structured notes. Show the raw body rather than nothing at all.
      if (updateInfo.releaseNotes.isEmpty) {
        return Text(
          'ota_no_release_notes'.tr(),
          style: AppTextStyles.bodyMd(isDarkMode: isDarkMode).copyWith(
            color: MainScreenColors.getTextColor(
              isDarkMode,
            ).withValues(alpha: AppDimens.opacityMuted),
            fontStyle: FontStyle.italic,
          ),
        );
      }

      return Text(
        updateInfo.releaseNotes,
        style: AppTextStyles.bodyMd(
          isDarkMode: isDarkMode,
        ).copyWith(height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.spacingSm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppDimens.spacingS,
                  height: AppDimens.spacingS,
                  margin: const EdgeInsets.only(
                    top: AppDimens.spacingSm,
                    right: AppDimens.spacingMd,
                  ),
                  decoration: BoxDecoration(
                    color: accentFor(context),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: AppTextStyles.bodyMd(
                      isDarkMode: isDarkMode,
                    ).copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color accentFor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(
          isDarkMode: true,
        ).copyWith(color: color, fontWeight: AppTextStyles.weightSemiBold),
      ),
    );
  }
}

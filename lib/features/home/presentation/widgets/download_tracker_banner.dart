import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/ota_model.dart';
import '../../../../core/providers/download_provider.dart';
import '../../../downloads/presentation/screens/downloads_screen.dart';
import '../../../ota/data/providers/ota_provider.dart';
import 'ota_tracker_banner.dart';

/// The single home banner slot. An app update in flight always wins the slot
/// (it needs install/pause/cancel controls); otherwise the song download queue
/// takes it. Exactly one card is ever shown, so Home never stacks two banners.
class HomeDownloadBanner extends StatelessWidget {
  const HomeDownloadBanner({super.key});

  static const Set<OTAStatus> _otaActiveStatuses = {
    OTAStatus.updateAvailable,
    OTAStatus.downloading,
    OTAStatus.paused,
    OTAStatus.downloaded,
    OTAStatus.error,
  };

  @override
  Widget build(BuildContext context) {
    return Consumer<OTAProvider>(
      builder: (context, ota, _) {
        if (_otaActiveStatuses.contains(ota.status) &&
            ota.updateInfo != null) {
          return const OtaTrackerBanner();
        }
        return const DownloadTrackerBanner();
      },
    );
  }
}

/// A compact strip pinned under the home app bar that tracks the song download
/// queue in place, with pause/resume and cancel right there.
///
/// It renders nothing at all when the queue is empty, so Home is untouched for
/// anyone not downloading. The whole card opens the full Downloads screen. App
/// updates are narrated by [OtaTrackerBanner], which shares this same slot.
class DownloadTrackerBanner extends StatelessWidget {
  const DownloadTrackerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, provider, _) {
        final queue = provider.downloadQueue
            .where((item) => item['status'] != 'completed')
            .toList(growable: false);

        if (queue.isEmpty && provider.activeDownloads.isEmpty) {
          return const SizedBox.shrink();
        }

        final tracked = _resolveTracked(queue, provider.activeDownloads);
        if (tracked == null) return const SizedBox.shrink();

        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final accentColor = Theme.of(context).colorScheme.primary;
        final progress = provider.progressMap[tracked['id']];
        final isPaused = provider.isPaused || tracked['status'] == 'paused';
        final textColor = MainScreenColors.getTextColor(isDarkMode);

        final double value = progress?.progress ?? 0;
        final int percent = (value * 100).clamp(0, 100).toInt();

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
              onTap: () => _openDownloads(context),
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              child: Container(
                padding: const EdgeInsets.all(AppDimens.paddingMd),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: isDarkMode ? 0.14 : 0.08),
                      accentColor.withValues(alpha: isDarkMode ? 0.05 : 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.25),
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
                          Icons.download_rounded,
                          size: AppDimens.iconSm,
                          color: accentColor,
                        ),
                        const SizedBox(width: AppDimens.spacingSm),
                        Expanded(
                          child: Text(
                            isPaused
                                ? 'paused_downloads'.tr()
                                : 'download_in_progress'.tr(),
                            style: AppTextStyles.caption(isDarkMode: isDarkMode)
                                .copyWith(
                                  color: accentColor,
                                  fontWeight: AppTextStyles.weightSemiBold,
                                ),
                          ),
                        ),
                        Text(
                          '${queue.length}',
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
                    const SizedBox(height: AppDimens.spacingSm),
                    Row(
                      children: [
                        _Thumbnail(url: tracked['thumbnail']?.toString()),
                        const SizedBox(width: AppDimens.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tracked['title']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.queueItem(
                                  isDarkMode: isDarkMode,
                                ),
                              ),
                              const SizedBox(height: AppDimens.spacingXxs),
                              Text(
                                tracked['artist']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption(
                                  isDarkMode: isDarkMode,
                                ).copyWith(
                                  color: textColor.withValues(
                                    alpha: AppDimens.opacityMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppDimens.spacingSm),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppDimens.radiusXxs,
                                ),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 6,
                                  backgroundColor: accentColor.withValues(
                                    alpha: 0.18,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppDimens.spacingXs),
                              Text(
                                isPaused ? 'ota_download_paused'.tr() : '$percent%',
                                style: AppTextStyles.caption(
                                  isDarkMode: isDarkMode,
                                ).copyWith(color: accentColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppDimens.spacingXs),
                        _RoundIconButton(
                          icon: isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          tooltip: isPaused
                              ? 'resume_downloads'.tr()
                              : 'pause_downloads'.tr(),
                          color: accentColor,
                          onPressed: () {
                            if (isPaused) {
                              provider.resumeAllDownloads();
                            } else {
                              provider.pauseAllDownloads();
                            }
                          },
                        ),
                        _RoundIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'remove_from_library'.tr(),
                          color: textColor.withValues(
                            alpha: AppDimens.opacityMuted,
                          ),
                          onPressed: () => provider.removeDownload(tracked),
                        ),
                      ],
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

  /// Prefers whatever is actually moving right now, then a paused item, then a
  /// queued one, so the strip always narrates the download the user cares about.
  static Map<String, dynamic>? _resolveTracked(
    List<Map<String, dynamic>> queue,
    Set<String> active,
  ) {
    if (queue.isEmpty) return null;

    for (final item in queue) {
      if (active.contains(item['id'])) return item;
    }
    for (final item in queue) {
      if (item['status'] == 'downloading') return item;
    }
    for (final item in queue) {
      if (item['status'] == 'paused') return item;
    }
    return queue.first;
  }

  void _openDownloads(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen()));
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    const size = AppDimens.thumbnailMini;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      child: (url == null || url!.isEmpty)
          ? _fallback(isDarkMode, size)
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallback(isDarkMode, size),
              errorWidget: (_, _, _) => _fallback(isDarkMode, size),
            ),
    );
  }

  Widget _fallback(bool isDarkMode, double size) {
    return Container(
      width: size,
      height: size,
      color: isDarkMode ? Colors.grey[850] : Colors.grey[300],
      child: Icon(
        Icons.music_note_rounded,
        size: AppDimens.iconSm,
        color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: AppDimens.iconLg,
      color: color,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/models/ota_model.dart';
import '../../data/providers/ota_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/theme/app_theme.dart';

class OTAScreen extends StatefulWidget {
  const OTAScreen({super.key});

  @override
  State<OTAScreen> createState() => _OTAScreenState();
}

class _OTAScreenState extends State<OTAScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  /// Which release in the history the user is reading. `0` is the newest, and
  /// the picker only ever changes what is displayed - never what gets
  /// downloaded, so browsing old notes can never stage a downgrade.
  int _selectedReleaseIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppDimens.animSlow,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<OTAProvider>(
        context,
        listen: false,
      ).loadReleaseHistory();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.themeMode == ThemeMode.dark;
    final accentColor = settingsProvider.accentColor;

    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: isDarkMode
              ? Colors.transparent
              : MainScreenColors.getSurfaceColor(false),
          elevation: 0,
          title: Text(
            'ota_app_update_title'.tr(),
            style: AppTextStyles.headingLg(isDarkMode: isDarkMode),
          ),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: MainScreenColors.getTextColor(isDarkMode),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: false,
        ),
        body: Consumer<OTAProvider>(
          builder: (context, otaProvider, child) {
            return RefreshIndicator(
              color: accentColor,
              onRefresh: () async {
                await otaProvider.checkForUpdates(
                  showChecking: false,
                  showNoUpdateMessage: true,
                );
                await otaProvider.loadReleaseHistory(force: true);
              },
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildBody(
                  context,
                  otaProvider,
                  isDarkMode,
                  accentColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    switch (otaProvider.status) {
      case OTAStatus.checking:
        return _buildCheckingUpdate(isDarkMode, accentColor);
      case OTAStatus.updateAvailable:
        return _buildUpdateAvailable(
          context,
          otaProvider,
          isDarkMode,
          accentColor,
        );
      case OTAStatus.downloading:
        return _buildDownloadProgress(
          otaProvider,
          isDarkMode,
          accentColor,
          isPaused: false,
        );
      case OTAStatus.paused:
        return _buildDownloadProgress(
          otaProvider,
          isDarkMode,
          accentColor,
          isPaused: true,
        );
      case OTAStatus.downloaded:
        return _buildReadyToInstall(
          context,
          otaProvider,
          isDarkMode,
          accentColor,
        );
      case OTAStatus.installing:
        return _buildInstalling(isDarkMode, accentColor);
      case OTAStatus.installed:
        return _buildInstalled(isDarkMode, accentColor);
      case OTAStatus.error:
        return _buildError(context, otaProvider, isDarkMode, accentColor);
      case OTAStatus.noUpdate:
        return _buildNoUpdate(otaProvider, isDarkMode, accentColor);
      default:
        return _buildInitial(context, otaProvider, isDarkMode, accentColor);
    }
  }

  // ---------------------------------------------------------------------------
  // RELEASE HISTORY
  // ---------------------------------------------------------------------------

  /// The versions available to read, newest first. Falls back to the single
  /// update the provider already knows about when the history has not loaded
  /// (offline, rate limited, or a repo with one release).
  List<OTAUpdateInfo> _history(OTAProvider otaProvider) {
    final history = otaProvider.releaseHistory;
    if (history.isNotEmpty) return history;
    final info = otaProvider.updateInfo;
    return info == null ? const <OTAUpdateInfo>[] : <OTAUpdateInfo>[info];
  }

  // ---------------------------------------------------------------------------
  // CHECKING / INITIAL
  // ---------------------------------------------------------------------------

  Widget _buildCheckingUpdate(bool isDarkMode, Color accentColor) {
    return _CenteredMessage(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      icon: null,
      showSpinner: true,
      title: 'ota_checking_for_updates'.tr(),
    );
  }

  Widget _buildInitial(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    return _CenteredMessage(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      icon: Icons.system_update_rounded,
      title: 'ota_check_for_updates'.tr(),
      message: 'ota_check_for_updates_message'.tr(),
      action: _PrimaryButton(
        label: 'ota_check_now'.tr(),
        icon: Icons.refresh_rounded,
        onPressed: () =>
            otaProvider.checkForUpdates(showNoUpdateMessage: true),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UPDATE AVAILABLE
  // ---------------------------------------------------------------------------

  Widget _buildUpdateAvailable(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    final latest = otaProvider.updateInfo!;
    final history = _history(otaProvider);
    final index = _selectedReleaseIndex.clamp(0, history.length - 1);
    final selected = history[index];
    final isLatestSelected = selected.latestVersion == latest.latestVersion;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingXl,
        AppDimens.paddingLg,
        AppDimens.paddingXl,
        AppDimens.spacingXxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReleaseHero(selected, isLatestSelected, isDarkMode, accentColor),
          const SizedBox(height: AppDimens.spacingXxl),
          _buildChangelog(selected, isDarkMode, accentColor),
          if (history.length > 1) ...[
            const SizedBox(height: AppDimens.spacingXxl),
            _buildVersionPicker(history, index, isDarkMode, accentColor),
          ],
          const SizedBox(height: AppDimens.spacingXxl),
          if (isLatestSelected)
            _buildActionButtons(context, otaProvider, isDarkMode, accentColor)
          else
            _buildOldVersionActions(
              context,
              otaProvider,
              selected,
              isDarkMode,
              accentColor,
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseHero(
    OTAUpdateInfo info,
    bool isLatestSelected,
    bool isDarkMode,
    Color accentColor,
  ) {
    final muted = MainScreenColors.getTextColor(
      isDarkMode,
    ).withValues(alpha: AppDimens.opacityMuted);

    return _ThemedSurface(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      padding: const EdgeInsets.all(AppDimens.paddingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppDimens.buttonSizeLg,
                height: AppDimens.buttonSizeLg,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: Colors.white,
                  size: AppDimens.iconMd,
                ),
              ),
              const SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'v${info.latestVersion}',
                      style: AppTextStyles.titleLg(isDarkMode: isDarkMode),
                    ),
                    const SizedBox(height: AppDimens.spacingXxs),
                    Text(
                      'ota_update_meta'.tr(
                        args: [
                          info.size,
                          DateFormat('d MMM yyyy').format(info.releaseDate),
                        ],
                      ),
                      style: AppTextStyles.caption(
                        isDarkMode: isDarkMode,
                      ).copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (isLatestSelected && !info.isPrerelease)
                _PillBadge(
                  label: 'ota_latest_label'.tr(),
                  color: accentColor,
                ),
              if (info.isPrerelease)
                _PillBadge(
                  label: 'ota_prerelease'.tr(),
                  color: accentColor,
                ),
            ],
          ),
          if (isLatestSelected) ...[
            const SizedBox(height: AppDimens.spacingLg),
            Row(
              children: [
                Text(
                  info.installedVersion,
                  style: AppTextStyles.subtitle(
                    isDarkMode: isDarkMode,
                  ).copyWith(color: muted),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.spacingSm,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: AppDimens.iconSm,
                    color: accentColor,
                  ),
                ),
                Text(
                  info.latestVersion,
                  style: AppTextStyles.subtitle(
                    isDarkMode: isDarkMode,
                  ).copyWith(
                    color: accentColor,
                    fontWeight: AppTextStyles.weightBold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChangelog(
    OTAUpdateInfo info,
    bool isDarkMode,
    Color accentColor,
  ) {
    final whatsNew = info.whatsNewItems;
    final fixed = info.fixedItems;
    final hasNotes = whatsNew.isNotEmpty || fixed.isNotEmpty;

    if (!hasNotes) {
      return _SectionCard(
        isDarkMode: isDarkMode,
        accentColor: accentColor,
        child: Text(
          'ota_no_release_notes'.tr(),
          style: AppTextStyles.bodyMd(isDarkMode: isDarkMode).copyWith(
            color: MainScreenColors.getTextColor(
              isDarkMode,
            ).withValues(alpha: AppDimens.opacityMuted),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (whatsNew.isNotEmpty)
          _buildChangeSection(
            title: 'ota_whats_new'.tr(),
            icon: Icons.auto_awesome_rounded,
            items: whatsNew,
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
        if (whatsNew.isNotEmpty && fixed.isNotEmpty)
          const SizedBox(height: AppDimens.spacingXl),
        if (fixed.isNotEmpty)
          _buildChangeSection(
            title: 'ota_fixed'.tr(),
            icon: Icons.check_circle_outline_rounded,
            items: fixed,
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
      ],
    );
  }

  Widget _buildChangeSection({
    required String title,
    required IconData icon,
    required List<String> items,
    required bool isDarkMode,
    required Color accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: accentColor, size: AppDimens.iconMd),
            const SizedBox(width: AppDimens.spacingSm),
            Text(
              title,
              style: AppTextStyles.sectionHeader(accentColor: accentColor),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.spacingMd),
        _SectionCard(
          isDarkMode: isDarkMode,
          accentColor: accentColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i != 0) const SizedBox(height: AppDimens.spacingMd),
                _buildChangeLogItem(items[i], isDarkMode, accentColor),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChangeLogItem(
    String item,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Row(
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
            color: accentColor,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            item,
            style: AppTextStyles.bodyMd(
              isDarkMode: isDarkMode,
            ).copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildVersionPicker(
    List<OTAUpdateInfo> history,
    int selectedIndex,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history_rounded,
              color: accentColor,
              size: AppDimens.iconMd,
            ),
            const SizedBox(width: AppDimens.spacingSm),
            Text(
              'ota_previous_versions'.tr(),
              style: AppTextStyles.sectionHeader(accentColor: accentColor),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.spacingMd),
        SizedBox(
          height: AppDimens.buttonSizeLg,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: history.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppDimens.spacingSm),
            itemBuilder: (context, index) {
              final info = history[index];
              final isSelected = index == selectedIndex;
              return FilterChip(
                selected: isSelected,
                label: Text(
                  'v${info.latestVersion}',
                  style: AppTextStyles.caption(
                    isDarkMode: isDarkMode,
                    color: isSelected ? Colors.white : null,
                  ).copyWith(
                    fontWeight: isSelected
                        ? AppTextStyles.weightSemiBold
                        : AppTextStyles.weightRegular,
                  ),
                ),
                selectedColor: accentColor,
                checkmarkColor: Colors.white,
                showCheckmark: false,
                backgroundColor: isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                side: BorderSide(
                  color: isSelected ? accentColor : Colors.transparent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                ),
                onSelected: (_) {
                  if (index != selectedIndex) {
                    setState(() => _selectedReleaseIndex = index);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Column(
      children: [
        _PrimaryButton(
          label: 'ota_download_update'.tr(),
          icon: Icons.download_rounded,
          onPressed: () => otaProvider.downloadUpdate(),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        _SecondaryButton(
          label: 'ota_update_open_website'.tr(),
          icon: Icons.open_in_browser_rounded,
          accentColor: accentColor,
          isDarkMode: isDarkMode,
          onPressed: otaProvider.openReleasePage,
        ),
        const SizedBox(height: AppDimens.spacingSm),
        SizedBox(
          width: double.infinity,
          height: AppDimens.buttonHeightMedium,
          child: TextButton(
            onPressed: () {
              otaProvider.skipVersion();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: MainScreenColors.getTextColor(
                isDarkMode,
              ).withValues(alpha: AppDimens.opacityMuted),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusXl),
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
    );
  }

  Widget _buildOldVersionActions(
    BuildContext context,
    OTAProvider otaProvider,
    OTAUpdateInfo selected,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Column(
      children: [
        _SecondaryButton(
          label: 'ota_view_on_github'.tr(),
          icon: Icons.open_in_new_rounded,
          accentColor: accentColor,
          isDarkMode: isDarkMode,
          onPressed: () => otaProvider.openExternal(selected.releaseUrl),
        ),
        const SizedBox(height: AppDimens.spacingSm),
        SizedBox(
          width: double.infinity,
          height: AppDimens.buttonHeightMedium,
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedReleaseIndex = 0),
            icon: const Icon(Icons.arrow_upward_rounded, size: AppDimens.iconSm),
            label: Text(
              'ota_back_to_latest'.tr(),
              style: AppTextStyles.bodyMd(
                isDarkMode: isDarkMode,
              ).copyWith(fontWeight: AppTextStyles.weightMedium),
            ),
            style: TextButton.styleFrom(
              foregroundColor: accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusXl),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // DOWNLOADING / PAUSED
  // ---------------------------------------------------------------------------

  Widget _buildDownloadProgress(
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor, {
    required bool isPaused,
  }) {
    final progress = otaProvider.downloadProgress;
    final percentage = progress != null ? progress.percentage / 100.0 : 0.0;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.paddingXl),
        child: Column(
          children: [
            const SizedBox(height: AppDimens.spacingXl),
            Text(
              isPaused
                  ? 'ota_download_paused'.tr()
                  : otaProvider.isBackgroundDownload
                  ? 'Downloading update in background…'
                  : 'ota_downloading_update'.tr(),
              style: AppTextStyles.headingLg(isDarkMode: isDarkMode),
            ),
            if (otaProvider.isBackgroundDownload) ...[
              const SizedBox(height: AppDimens.spacingSm),
              Text(
                'You can keep using the app. We will prompt you to install '
                'when it finishes.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd(isDarkMode: isDarkMode).copyWith(
                  color: MainScreenColors.getTextColor(
                    isDarkMode,
                  ).withValues(alpha: AppDimens.opacityMuted),
                ),
              ),
            ],
            const SizedBox(height: AppDimens.spacingXxxl),
            SizedBox(
              width: AppDimens.progressCircleLarge,
              height: AppDimens.progressCircleLarge,
              child: _AnimatedDownloadRing(
                progress: percentage,
                accentColor: accentColor,
                isPaused: isPaused,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      progress != null
                          ? '${progress.percentage.toInt()}%'
                          : '0%',
                      style: AppTextStyles.display(isDarkMode: isDarkMode),
                    ),
                    if (progress != null)
                      Text(
                        '${progress.formattedDownloaded} / ${progress.formattedTotal}',
                        style: AppTextStyles.bodyMd(
                          isDarkMode: isDarkMode,
                        ).copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: AppDimens.opacityMuted),
                        ),
                      ),
                    if (progress != null &&
                        progress.downloadSpeed != '0 KB/s') ...[
                      const SizedBox(height: AppDimens.spacingXxs),
                      Text(
                        '${progress.downloadSpeed} • ${progress.eta}',
                        style: AppTextStyles.caption(
                          isDarkMode: isDarkMode,
                        ).copyWith(
                          color: accentColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimens.spacingXxxl),

            // Pause / Resume and Cancel sit side by side. Cancel stays
            // destructive-looking in both states because it throws the saved
            // bytes away, while Resume is the accent-coloured primary action.
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: isPaused
                        ? _PrimaryButton(
                            label: 'ota_resume_download'.tr(),
                            icon: Icons.play_arrow_rounded,
                            onPressed: () => otaProvider.resumeDownload(),
                          )
                        : _SecondaryButton(
                            label: 'ota_pause_download'.tr(),
                            icon: Icons.pause_rounded,
                            accentColor: accentColor,
                            isDarkMode: isDarkMode,
                            onPressed: () => otaProvider.pauseDownload(),
                          ),
                  ),
                ),
                const SizedBox(width: AppDimens.spacingMd),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: _DestructiveButton(
                      label: isPaused
                          ? 'ota_discard_download'.tr()
                          : 'ota_cancel_download'.tr(),
                      icon: Icons.delete_outline_rounded,
                      onPressed: () => otaProvider.cancelDownload(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // READY TO INSTALL
  // ---------------------------------------------------------------------------

  Widget _buildReadyToInstall(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    return _CenteredMessage(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      icon: Icons.check_circle_rounded,
      title: 'ota_download_complete'.tr(),
      message: 'ota_ready_to_install_message'.tr(),
      action: _PrimaryButton(
        label: 'ota_install_update'.tr(),
        icon: Icons.install_mobile_rounded,
        onPressed: () => otaProvider.installUpdate(),
      ),
    );
  }

  Widget _buildInstalling(bool isDarkMode, Color accentColor) {
    return _CenteredMessage(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      icon: null,
      showSpinner: true,
      title: 'ota_installing_update'.tr(),
      message: 'ota_please_wait_install'.tr(),
    );
  }

  Widget _buildInstalled(bool isDarkMode, Color accentColor) {
    return _CenteredMessage(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      icon: Icons.check_circle_rounded,
      iconColor: Colors.green,
      title: 'ota_update_installed'.tr(),
      message: 'ota_update_installed_message'.tr(),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR / NO UPDATE
  // ---------------------------------------------------------------------------

  Widget _buildError(
    BuildContext context,
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    if (otaProvider.error == OTAError.permissionError) {
      return _buildPermissionError(otaProvider, isDarkMode, accentColor);
    }

    return _CenteredMessage(
      isDarkMode: isDarkMode,
      accentColor: accentColor,
      icon: Icons.error_rounded,
      iconColor: Colors.red,
      title: 'ota_update_failed'.tr(),
      message: otaProvider.errorMessage ?? 'ota_update_failed_message'.tr(),
      action: _PrimaryButton(
        label: 'ota_try_again'.tr(),
        icon: Icons.refresh_rounded,
        onPressed: () {
          otaProvider.reset();
          otaProvider.checkForUpdates(showNoUpdateMessage: true);
        },
      ),
    );
  }

  /// Android (especially Samsung) blocks installing an APK from an app the
  /// user has not explicitly allowed to install unknown apps. The system
  /// permission dialog can be denied permanently, leaving the in-app retry
  /// stuck in a loop, so this shows exactly where to flip the switch and
  /// offers a direct jump to the settings screen.
  Widget _buildPermissionError(
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppDimens.paddingXl),
      child: Column(
        children: [
          const SizedBox(height: AppDimens.spacingXl),
          Container(
            padding: const EdgeInsets.all(AppDimens.paddingXxl),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.gpp_maybe_rounded,
              color: Colors.orange,
              size: AppDimens.iconStatus,
            ),
          ),
          const SizedBox(height: AppDimens.spacingXxl),
          Text(
            'Install blocked by Android',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingLg(isDarkMode: isDarkMode),
          ),
          const SizedBox(height: AppDimens.spacingLg),
          Text(
            otaProvider.errorMessage ?? 'Android blocked the install.',
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle(isDarkMode: isDarkMode).copyWith(
              color: MainScreenColors.getTextColor(
                isDarkMode,
              ).withValues(alpha: AppDimens.opacityMuted),
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppDimens.spacingXxl),
          _ThemedSurface(
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            padding: const EdgeInsets.all(AppDimens.paddingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To allow the update:',
                  style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
                ),
                const SizedBox(height: AppDimens.spacingMd),
                _buildPermissionStep(
                  '1',
                  'Open Settings › Apps › Special access',
                  isDarkMode,
                  accentColor,
                ),
                _buildPermissionStep(
                  '2',
                  'Tap "Install unknown apps" (Samsung: "Install unknown apps" '
                  'under Special access)',
                  isDarkMode,
                  accentColor,
                ),
                _buildPermissionStep(
                  '3',
                  'Select MusiX and turn on "Allow from this source"',
                  isDarkMode,
                  accentColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.spacingXxl),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'Open install settings',
              icon: Icons.settings_rounded,
              onPressed: () => otaProvider.openInstallSettings(),
            ),
          ),
          const SizedBox(height: AppDimens.spacingMd),
          SizedBox(
            width: double.infinity,
            child: _SecondaryButton(
              label: 'ota_try_again'.tr(),
              icon: Icons.refresh_rounded,
              accentColor: accentColor,
              isDarkMode: isDarkMode,
              onPressed: () => otaProvider.installUpdate(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStep(
    String number,
    String text,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: AppTextStyles.caption(
                isDarkMode: isDarkMode,
              ).copyWith(color: accentColor, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppDimens.spacingMd),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMd(isDarkMode: isDarkMode).copyWith(
                color: MainScreenColors.getTextColor(
                  isDarkMode,
                ).withValues(alpha: AppDimens.opacityMuted),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoUpdate(
    OTAProvider otaProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    final history = _history(otaProvider);
    if (history.isEmpty) {
      return _CenteredMessage(
        isDarkMode: isDarkMode,
        accentColor: accentColor,
        icon: Icons.check_circle_rounded,
          title: 'ota_up_to_date'.tr(),
        message: 'ota_up_to_date_message'.tr(),
      );
    }

    final index = _selectedReleaseIndex.clamp(0, history.length - 1);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingXl,
        AppDimens.paddingLg,
        AppDimens.paddingXl,
        AppDimens.spacingXxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ThemedSurface(
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            padding: const EdgeInsets.all(AppDimens.paddingXl),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppDimens.paddingMd),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: accentColor,
                    size: AppDimens.iconXl,
                  ),
                ),
                const SizedBox(width: AppDimens.spacingLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ota_up_to_date'.tr(),
                        style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
                      ),
                      const SizedBox(height: AppDimens.spacingXxs),
                      Text(
                        'ota_up_to_date_message'.tr(),
                        style: AppTextStyles.caption(
                          isDarkMode: isDarkMode,
                        ).copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: AppDimens.opacityMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.spacingXxl),
          _buildVersionPicker(history, index, isDarkMode, accentColor),
          const SizedBox(height: AppDimens.spacingXxl),
          _buildChangelog(history[index], isDarkMode, accentColor),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SHARED PIECES
// -----------------------------------------------------------------------------

/// Soft accent-gradient card used everywhere on this screen so the update flow
/// matches the rest of the app instead of being a flat grey slab.
class _ThemedSurface extends StatelessWidget {
  const _ThemedSurface({
    required this.child,
    required this.isDarkMode,
    required this.accentColor,
    this.padding = const EdgeInsets.all(AppDimens.paddingLg),
  });

  final Widget child;
  final bool isDarkMode;
  final Color accentColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: isDarkMode ? 0.10 : 0.06),
            accentColor.withValues(alpha: isDarkMode ? 0.03 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.20),
          width: AppDimens.borderWidthThin,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: AppDimens.paddingMd,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    required this.isDarkMode,
    required this.accentColor,
  });

  final Widget child;
  final bool isDarkMode;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.paddingLg),
      decoration: BoxDecoration(
        color: isDarkMode
            ? MainScreenColors.darkSurfaceColor.withValues(alpha: 0.55)
            : MainScreenColors.lightSurfaceColor.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(
          color: MainScreenColors.getTextColor(
            isDarkMode,
          ).withValues(alpha: AppDimens.opacitySubtle),
        ),
      ),
      child: child,
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(isDarkMode: true).copyWith(
          color: color,
          fontWeight: AppTextStyles.weightSemiBold,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accentColor = context.accentColor;
    return SizedBox(
      width: double.infinity,
      height: AppDimens.buttonHeightLarge,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppDimens.iconMd),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: AppTextStyles.subtitle(isDarkMode: true),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isDarkMode,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isDarkMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppDimens.buttonHeightMedium,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppDimens.iconSm),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: accentColor,
          textStyle: AppTextStyles.subtitle(isDarkMode: isDarkMode),
          side: BorderSide(
            color: accentColor.withValues(alpha: 0.6),
            width: AppDimens.borderWidthThick,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          ),
        ),
      ),
    );
  }
}

class _DestructiveButton extends StatelessWidget {
  const _DestructiveButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE5484D);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: AppDimens.iconMd),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        textStyle: AppTextStyles.subtitle(isDarkMode: true),
        side: BorderSide(
          color: color.withValues(alpha: 0.6),
          width: AppDimens.borderWidthThick,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        ),
      ),
    );
  }
}

/// Full-height, centred status layout used by every non-scrolling state so the
/// checking, installing and error screens can never drift apart.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.isDarkMode,
    required this.accentColor,
    required this.title,
    this.icon,
    this.iconColor,
    this.message,
    this.action,
    this.showSpinner = false,
  });
  final bool isDarkMode;
  final Color accentColor;
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? message;
  final Widget? action;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? accentColor;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 160,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.paddingXl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showSpinner)
                  CircularProgressIndicator(
                    color: accentColor,
                    strokeWidth: AppDimens.progressStroke,
                  )
                else if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(AppDimens.paddingXxl),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: AppDimens.iconStatus,
                    ),
                  ),
                const SizedBox(height: AppDimens.spacingXxxl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headingLg(isDarkMode: isDarkMode),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppDimens.spacingLg),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle(isDarkMode: isDarkMode)
                        .copyWith(
                          color: MainScreenColors.getTextColor(
                            isDarkMode,
                          ).withValues(alpha: AppDimens.opacityMuted),
                          height: 1.5,
                        ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: AppDimens.spacingXxxl),
                  SizedBox(width: 220, child: action),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A progress ring that keeps a slow sweeping glow and a rotating "downloading"
/// comet while active, and freezes completely when paused so it never claims
/// work that is not happening.
class _AnimatedDownloadRing extends StatefulWidget {
  const _AnimatedDownloadRing({
    required this.progress,
    required this.accentColor,
    required this.isPaused,
    required this.child,
  });

  /// 0..1.
  final double progress;
  final Color accentColor;
  final bool isPaused;
  final Widget child;

  @override
  State<_AnimatedDownloadRing> createState() => _AnimatedDownloadRingState();
}

class _AnimatedDownloadRingState extends State<_AnimatedDownloadRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!widget.isPaused) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _AnimatedDownloadRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.isPaused && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _DownloadRingPainter(
            progress: widget.progress,
            accentColor: widget.accentColor,
            angle: _controller.value * 2 * math.pi,
            pulse: _controller.value,
            isPaused: widget.isPaused,
          ),
          child: Center(child: child),
        );
      },
      child: widget.child,
    );
  }
}

class _DownloadRingPainter extends CustomPainter {
  _DownloadRingPainter({
    required this.progress,
    required this.accentColor,
    required this.angle,
    required this.pulse,
    required this.isPaused,
  });

  final double progress;
  final Color accentColor;
  final double angle;
  final double pulse;
  final bool isPaused;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - AppDimens.progressStrokeLg;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Soft breathing glow behind the ring.
    if (!isPaused) {
      final glowAlpha = 0.08 + (math.sin(pulse * 2 * math.pi) + 1) / 2 * 0.10;
      canvas.drawCircle(
        center,
        radius + AppDimens.progressStrokeLg,
        Paint()
          ..color = accentColor.withValues(alpha: glowAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    // Track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppDimens.progressStrokeLg
        ..color = accentColor.withValues(alpha: 0.14),
    );

    // Progress arc, top to bottom, with a gradient that fades in.
    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppDimens.progressStrokeLg
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          colors: [accentColor.withValues(alpha: 0.5), accentColor],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }

    // Rotating comet that signals active transfer.
    if (!isPaused) {
      final cometPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppDimens.progressStrokeLg
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          colors: [accentColor.withValues(alpha: 0.0), accentColor],
          transform: GradientRotation(angle),
        ).createShader(rect);
      canvas.drawArc(rect, angle, math.pi * 0.35, false, cometPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DownloadRingPainter oldDelegate) => true;
}

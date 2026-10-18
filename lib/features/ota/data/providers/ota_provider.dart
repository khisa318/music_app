import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/ota_model.dart';
import '../../../../core/services/download_notification_service.dart';
import '../models/app_repository.dart';
import '../services/apk_download_service.dart';
import '../services/apk_installer_service.dart';
import '../services/github_release_service.dart';
import '../services/update_checker.dart';

/// Coordinates the in-app update flow.
///
/// Deliberately thin: every decision lives in a service under `data/services`
/// so the logic can be unit tested without a device. This class only holds UI
/// state and sequences the steps.
///
/// Public surface is unchanged from the previous implementation so every call
/// site (`main.dart`, `mobile_screen.dart`, `settings_screen.dart`,
/// `general_settings_section.dart`) compiles without modification.
class OTAProvider extends ChangeNotifier {
  OTAProvider({
    GitHubReleaseService? releaseService,
    ApkDownloadService? downloadService,
    ApkInstallerService? installerService,
    AppRepository? repository,
    UpdateChecker? checker,
  }) : _releaseService = releaseService ?? GitHubReleaseService(),
       _downloadService = downloadService ?? ApkDownloadService(),
       _installerService = installerService ?? const ApkInstallerService(),
       _repository = repository ?? AppRepository.current,
       _checker = checker ?? const UpdateChecker();

  final GitHubReleaseService _releaseService;
  final ApkDownloadService _downloadService;
  final ApkInstallerService _installerService;
  final AppRepository _repository;
  final UpdateChecker _checker;

  /// Remembered so "skip this version" survives a restart. Without this the
  /// prompt reappears on every single launch.
  static const String _skippedVersionKey = 'ota_skipped_version';

  /// Persisted so a finished background download survives app death: the next
  /// launch goes straight to "ready to install" instead of re-downloading.
  static const String _readyApkPathKey = 'ota_ready_apk_path';
  static const String _readyApkVersionKey = 'ota_ready_apk_version';

  /// Persisted while a background download is in flight so the next launch
  /// knows to resume the partial file.
  static const String _inflightVersionKey = 'ota_inflight_version';

  /// Background downloads are deliberately slow so they never compete with
  /// streaming or other network use while the user keeps listening.
  static const int _backgroundDownloadBytesPerSecond = 250 * 1024;

  OTAStatus _status = OTAStatus.idle;
  OTAUpdateInfo? _updateInfo;
  OTADownloadProgress? _downloadProgress;
  OTAError? _error;
  String? _errorMessage;
  String? _downloadedFilePath;
  bool _checksumVerified = false;
  bool _isUpdateUIShown = false;
  bool _isOTAScreenActive = false;
  String _updateChannel = 'stable';
  final List<OTAUpdateInfo> _releaseHistory = <OTAUpdateInfo>[];
  bool _isLoadingHistory = false;
  bool _isBackgroundDownload = false;

  /// True while the update APK is being downloaded automatically in the
  /// background (throttled), rather than from an explicit user action.
  bool get isBackgroundDownload => _isBackgroundDownload;

  OTAStatus get status => _status;
  OTAUpdateInfo? get updateInfo => _updateInfo;
  OTADownloadProgress? get downloadProgress => _downloadProgress;
  OTAError? get error => _error;
  String? get errorMessage => _errorMessage;

  /// Recent installable releases, newest first, for the version picker. Empty
  /// until [loadReleaseHistory] runs.
  List<OTAUpdateInfo> get releaseHistory =>
      List<OTAUpdateInfo>.unmodifiable(_releaseHistory);
  bool get isLoadingHistory => _isLoadingHistory;
  bool get hasUpdate =>
      _status == OTAStatus.updateAvailable ||
      _status == OTAStatus.downloaded ||
      _status == OTAStatus.downloading ||
      _status == OTAStatus.paused;
  bool get isUpdateUIShown => _isUpdateUIShown;
  bool get isOTAScreenActive => _isOTAScreenActive;

  /// True when the downloaded APK matched a published SHA-256.
  bool get isChecksumVerified => _checksumVerified;

  /// Where the "Open website" option sends the user.
  String get releasesUrl => 'https://musix-website.vercel.app/';

  /// Asks GitHub for the newest release and decides whether it is newer than
  /// what is installed.
  ///
  /// Never throws. On any failure - offline, rate limited, GitHub down, a
  /// malformed body - the app keeps working and [status] returns to idle. That
  /// is the contract: an update check must never get in the user's way.
  Future<void> checkForUpdates({
    bool showNoUpdateMessage = false,
    bool showChecking = true,
  }) async {
    if (_status == OTAStatus.checking) return;

    if (showChecking) _setStatus(OTAStatus.checking);
    _error = null;
    _errorMessage = null;

    final installed = await _readInstalledVersion();
    if (installed == null) {
      if (showChecking) _setStatus(OTAStatus.idle);
      return;
    }

    _releaseService.allowPreReleases = _updateChannel == 'beta';

    final releaseResult = await _releaseService.fetchLatestRelease();
    final outcome = _checker.evaluate(
      installed: installed,
      result: releaseResult,
    );

    switch (outcome) {
      case UpdateAvailableResult():
        final info = OTAUpdateInfo.fromRelease(
          release: outcome.release,
          installed: installed,
          fallbackUrl: _repository
              .releasePage(outcome.release.tagName)
              .toString(),
        );

        if (info == null) {
          // No usable APK on the release; treat as nothing to offer.
          _finishNoUpdate(showNoUpdateMessage);
          return;
        }

        // A version the user explicitly skipped stays skipped - but only for
        // the automatic prompt that fires on launch. `showNoUpdateMessage` is
        // set exclusively by an explicit "Check for updates" tap, and the
        // answer to *that* is never "no update available": it is a direct
        // answer to a direct question, and reporting "you are on the latest
        // version" for a release the app just advertised is simply a lie that
        // leaves the user with no way to update from inside the app.
        //
        // The stored skip is left in place, so the launch prompt stays quiet
        // for this version. It is the nagging that was declined, not the
        // knowledge that an update exists.
        if (!showNoUpdateMessage && await _isSkipped(info.latestVersion)) {
          _finishNoUpdate(showNoUpdateMessage);
          return;
        }

        _updateInfo = info;
        _setStatus(OTAStatus.updateAvailable);
        debugPrint('[Update] ${info.versionDelta} available');

        // A previous session may already have this APK on disk (fully or
        // partially). Restore or resume it so the user never re-downloads.
        unawaited(_resumeOrRestoreBackgroundFlow(info));

      case UpToDateResult():
        _updateInfo = null;
        _finishNoUpdate(showNoUpdateMessage);

      case UpdateCheckFailedResult():
        _updateInfo = null;
        // Silent by default. A failure is only worth showing when the user
        // explicitly asked, and even then it must not look like a broken app.
        if (showNoUpdateMessage) {
          _handleError(
            _mapReleaseFailure(outcome.failure),
            _releaseFailureMessage(outcome.failure),
          );
        } else {
          _setStatus(OTAStatus.idle);
        }
        debugPrint(
          '[Update] check failed (${outcome.failure.name}): ${outcome.message}',
        );
    }
  }

  void _finishNoUpdate(bool showNoUpdateMessage) {
    _setStatus(showNoUpdateMessage ? OTAStatus.noUpdate : OTAStatus.idle);
  }

  /// Loads the recent release list so the update screen can offer a version
  /// picker. Silent on failure: browsing history is a convenience, never a
  /// requirement, and the screen still works from [updateInfo] alone.
  Future<void> loadReleaseHistory({bool force = false}) async {
    if (_isLoadingHistory) return;
    if (!force && _releaseHistory.isNotEmpty) return;

    _isLoadingHistory = true;
    notifyListeners();

    try {
      final installed = await _readInstalledVersion();
      if (installed != null) {
        _releaseService.allowPreReleases = _updateChannel == 'beta';
        final releases = await _releaseService.fetchReleases();

        final history = <OTAUpdateInfo>[];
        for (final release in releases) {
          final info = OTAUpdateInfo.fromRelease(
            release: release,
            installed: installed,
            fallbackUrl: _repository.releasePage(release.tagName).toString(),
          );
          if (info != null) history.add(info);
        }

        _releaseHistory
          ..clear()
          ..addAll(history);
      }
    } catch (error) {
      debugPrint('[Update] could not load release history: $error');
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  /// Downloads the APK for the current update, verifies it, and stages it for
  /// the system installer.
  ///
  /// Pass [maxBytesPerSecond] to throttle (used by the background flow) and
  /// [background] to mark this as an automatic download whose completion
  /// re-prompts the user to install.
  Future<void> downloadUpdate({
    int? maxBytesPerSecond,
    bool background = false,
  }) async {
    final info = _updateInfo;
    if (info == null || _status == OTAStatus.downloading) return;

    if (background) _isBackgroundDownload = true;

    _error = null;
    _errorMessage = null;
    _setStatus(OTAStatus.downloading);

    try {
      // Persist the in-flight version so a killed app resumes next launch.
      await _writeInflightVersion(info.latestVersion);

      // Uses the release description the user is already looking at. No second
      // network round trip, so a flaky connection cannot strand them here.
      final result = await _downloadService.download(
        apk: info.apkAsset,
        checksumAsset: info.checksumAsset,
        host: _repository.host,
        maxBytesPerSecond: maxBytesPerSecond,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      if (result.isSuccess) {
        _downloadProgress = null;
        _downloadedFilePath = result.filePath;
        _checksumVerified = result.verified;
        await _persistReadyApk(info.latestVersion, result.filePath!);
        await _clearInflightVersion();
        _setStatus(OTAStatus.downloaded);
        debugPrint(
          '[Update] downloaded ${info.apkAssetName} '
          '(checksum verified: ${result.verified})',
        );

        if (_isBackgroundDownload) {
          // The user is elsewhere in the app; re-show the install prompt and
          // post a notification so the finished download does not go unnoticed.
          _isUpdateUIShown = false;
          notifyListeners();
          unawaited(
            DownloadNotificationService().showUpdateReady(
              version: info.latestVersion,
            ),
          );
        }
        return;
      }

      switch (result.failure) {
        case DownloadFailure.paused:
          // The progress is deliberately left in place: it is how the UI shows
          // where the user stopped and what resuming will pick up from.
          _setStatus(OTAStatus.paused);
        case DownloadFailure.cancelled:
          _downloadProgress = null;
          await _clearInflightVersion();
          _setStatus(OTAStatus.updateAvailable);
        case DownloadFailure.integrity:
          _downloadProgress = null;
          await _clearInflightVersion();
          _handleError(
            OTAError.checksumError,
            'The download did not pass verification and was discarded',
          );
        case DownloadFailure.notEnoughSpace:
          _downloadProgress = null;
          await _clearInflightVersion();
          _handleError(
            OTAError.storageError,
            'Not enough free storage to download the update',
          );
        case DownloadFailure.offline:
        case DownloadFailure.timeout:
        case DownloadFailure.server:
          // Progress is kept so a later Resume still knows how far it got.
          if (_isBackgroundDownload) {
            // A background attempt failing on the network is not worth an
            // error screen: the partial file stays on disk and the next
            // launch resumes it. Quietly return to "update available".
            _setStatus(OTAStatus.updateAvailable);
          } else {
            _handleError(
              OTAError.downloadError,
              'Download failed. Check your connection and try again.',
            );
          }
        case DownloadFailure.unknown:
        case null:
          _downloadProgress = null;
          await _clearInflightVersion();
          if (_isBackgroundDownload) {
            _setStatus(OTAStatus.updateAvailable);
          } else {
            _handleError(OTAError.downloadError, 'Download failed');
          }
      }
    } finally {
      _isBackgroundDownload = false;
    }
  }

  /// Starts the update download automatically, throttled, without requiring
  /// the user to sit on the update screen. On completion the install prompt
  /// is re-shown and a notification is posted.
  Future<void> startBackgroundDownload() async {
    final info = _updateInfo;
    if (info == null) return;
    if (_status == OTAStatus.downloading || _status == OTAStatus.downloaded) {
      return;
    }

    debugPrint('[Update] starting slow background download of '
        '${info.apkAssetName}');

    // Samsung and other OEMs kill background work aggressively; an exempted
    // app is the difference between "downloaded overnight" and "never
    // finished". Best-effort: a declined prompt just means a higher chance
    // the download resumes on the next launch.
    unawaited(_requestBatteryOptimizationExemption());

    await downloadUpdate(
      maxBytesPerSecond: _backgroundDownloadBytesPerSecond,
      background: true,
    );
  }

  /// Restores a finished download from a previous session, or resumes a
  /// partial one, as soon as an update for that same version is confirmed.
  /// A brand-new update starts the slow background download immediately, so
  /// the APK is ready by the time the user gets around to installing.
  Future<void> _resumeOrRestoreBackgroundFlow(OTAUpdateInfo info) async {
    try {
      final readyPath = await _loadReadyApk(info.latestVersion);
      if (readyPath != null) {
        _downloadedFilePath = readyPath;
        _checksumVerified = true;
        _setStatus(OTAStatus.downloaded);
        _isUpdateUIShown = false;
        debugPrint('[Update] restored already-downloaded APK for '
            '${info.latestVersion}');
        return;
      }

      // Fresh update, or a partial left by an interrupted/killed session: the
      // throttled background download picks up from the partial file when one
      // exists. Starting it is left to the UI coordinator, which is where the
      // Wi-Fi / "Wi-Fi only downloads" policy is known, so an automatic update
      // is never begun over a connection the user asked us to avoid.
      final inflight = await _readInflightVersion();
      final hasPartial = await _downloadService.hasPartial(
        info.apkAssetName,
      );
      debugPrint(
        '[Update] update available; UI will start the throttled background '
        'download (inflight match: ${inflight == info.latestVersion}, '
        'partial on disk: $hasPartial)',
      );
    } catch (error) {
      debugPrint('[Update] background restore failed: $error');
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (error) {
      debugPrint('[Update] battery optimization request failed: $error');
    }
  }

  /// Opens the system screen where the user can allow MusiX to install
  /// unknown apps. On Samsung this lives under
  /// Settings > Apps > Special access > Install unknown apps.
  Future<void> openInstallSettings() =>
      _installerService.openInstallPermissionSettings();

  // ---------------------------------------------------------------------------
  // PERSISTED DOWNLOAD STATE
  // ---------------------------------------------------------------------------

  Future<void> _persistReadyApk(String version, String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_readyApkPathKey, path);
      await prefs.setString(_readyApkVersionKey, version);
    } catch (error) {
      debugPrint('[Update] could not persist ready APK: $error');
    }
  }

  Future<String?> _loadReadyApk(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_readyApkVersionKey) != version) return null;
      final path = prefs.getString(_readyApkPathKey);
      if (path == null) return null;
      if (!await File(path).exists()) {
        await _clearReadyApkPersist();
        return null;
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearReadyApkPersist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_readyApkPathKey);
      await prefs.remove(_readyApkVersionKey);
    } catch (_) {}
  }

  Future<void> _writeInflightVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_inflightVersionKey, version);
    } catch (_) {}
  }

  Future<String?> _readInflightVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_inflightVersionKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearInflightVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_inflightVersionKey);
    } catch (_) {}
  }

  /// Stops the download where it is, keeping what has already been received.
  ///
  /// The status only changes to [OTAStatus.paused] once the service has
  /// finished unwinding the socket, which happens inside [downloadUpdate].
  void pauseDownload() {
    if (_status != OTAStatus.downloading) return;
    _downloadService.pause();
  }

  /// Picks up a paused download from the bytes already on disk.
  Future<void> resumeDownload() async {
    if (_status != OTAStatus.paused) return;
    await downloadUpdate();
  }

  /// Whether the download can currently be paused.
  bool get isDownloadPausable => _status == OTAStatus.downloading;

  /// Whether the download can currently be continued.
  bool get isDownloadResumable => _status == OTAStatus.paused;

  /// The furthest point the download reached, kept after a pause so the UI can
  /// report "paused at 42%".
  double get pausedPercentage => _downloadProgress?.percentage ?? 0;

  /// Hands the verified APK to Android's own installer.
  ///
  /// The user confirms on the following system screen; nothing is installed
  /// silently and Android's security model is never bypassed.
  Future<void> installUpdate() async {
    final path = _downloadedFilePath;
    if (path == null || _status != OTAStatus.downloaded) return;

    _setStatus(OTAStatus.installing);

    final result = await _installerService.install(path);

    if (result.isSuccess) {
      _setStatus(OTAStatus.installed);
      // Remove the staged APK. If the user then backs out of the install the
      // next update attempt just downloads it again.
      await _downloadService.deleteDownloadedFile(path);
      await _clearReadyApkPersist();
      _downloadedFilePath = null;
      return;
    }

    switch (result.failure) {
      case InstallFailure.permissionDenied:
        _handleError(
          OTAError.permissionError,
          'Android blocked the install. Allow MusiX to install unknown '
          'apps, then try again.',
        );
      case InstallFailure.notEnoughSpace:
        _handleError(
          OTAError.storageError,
          'Not enough free storage to install the update',
        );
      case InstallFailure.signatureMismatch:
        _handleError(
          OTAError.installError,
          'This build was signed with a different key and cannot replace '
          'your installed copy',
        );
      case InstallFailure.invalidPackage:
        _handleError(
          OTAError.parseError,
          'The downloaded file is not a valid package',
        );
      case InstallFailure.aborted:
        _setStatus(OTAStatus.downloaded);
      case InstallFailure.unknown:
      case null:
        _handleError(OTAError.installError, 'Installation failed');
    }
  }

  void cancelDownload() {
    if (_status == OTAStatus.downloading) {
      _downloadService.cancel();
      _downloadProgress = null;
      unawaited(_clearInflightVersion());
      _setStatus(OTAStatus.updateAvailable);
      return;
    }

    if (_status == OTAStatus.paused) {
      // Nothing is in flight, so cancelling has to actively throw the saved
      // bytes away - otherwise the next attempt would silently resume them and
      // the user would have no way back to a clean download.
      final info = _updateInfo;
      _downloadProgress = null;
      unawaited(_clearInflightVersion());
      _setStatus(OTAStatus.updateAvailable);
      if (info != null) {
        unawaited(_downloadService.discardPartial(info.apkAssetName));
      }
    }
  }

  /// Remembers that the user does not want to hear about this version again.
  Future<void> skipVersion() async {
    final info = _updateInfo;
    if (info == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_skippedVersionKey, info.latestVersion);
    } catch (error) {
      // A failure here only means the prompt shows again next launch.
      debugPrint('[Update] could not persist skipped version: $error');
    }

    // A skipped version should leave nothing behind on disk either: the
    // partial or finished APK would otherwise be resumed silently.
    await _clearInflightVersion();
    final readyPath = await _loadReadyApk(info.latestVersion);
    if (readyPath != null) {
      await _downloadService.deleteDownloadedFile(readyPath);
      await _clearReadyApkPersist();
      _downloadedFilePath = null;
    } else {
      await _downloadService.discardPartial(info.apkAssetName);
    }

    _updateInfo = null;
    _setStatus(OTAStatus.idle);
  }

  /// Opens the app website in the device browser.
  Future<void> openReleasePage() => openExternal(releasesUrl);

  /// Opens an arbitrary verified https link in the device browser. Used for
  /// the per-release "View on GitHub" action.
  Future<void> openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // Try to launch directly rather than gating on `canLaunchUrl`. On Android
    // 11+ `canLaunchUrl` can return false even when a browser exists (package
    // visibility), which would turn this into a silent no-op.
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        debugPrint('[Update] could not open $url');
      }
    } catch (error) {
      debugPrint('[Update] could not open $url: $error');
    }
  }

  void setUpdateUIShown(bool value) {
    _isUpdateUIShown = value;
    notifyListeners();
  }

  void setOTAScreenActive(bool value) {
    _isOTAScreenActive = value;
    notifyListeners();
  }

  void setUpdateChannel(String channel) {
    if (_updateChannel == channel) return;
    _updateChannel = channel;
    _updateInfo = null;
    _setStatus(OTAStatus.idle);
  }

  void reset() {
    _status = OTAStatus.idle;
    _updateInfo = null;
    _downloadProgress = null;
    _error = null;
    _errorMessage = null;
    _downloadedFilePath = null;
    _checksumVerified = false;
    _isUpdateUIShown = false;
    _releaseHistory.clear();
    notifyListeners();
  }

  /// True when the user has already dismissed this exact version.
  Future<bool> _isSkipped(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_skippedVersionKey) == version;
    } catch (_) {
      return false;
    }
  }

  Future<InstalledVersion?> _readInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return InstalledVersion(
        versionName: info.version,
        buildNumber: info.buildNumber,
      );
    } catch (error) {
      debugPrint('[Update] could not read package info: $error');
      return null;
    }
  }

  static OTAError _mapReleaseFailure(ReleaseCheckFailure failure) {
    switch (failure) {
      case ReleaseCheckFailure.offline:
      case ReleaseCheckFailure.timeout:
      case ReleaseCheckFailure.rateLimited:
      case ReleaseCheckFailure.serverError:
        return OTAError.networkError;
      case ReleaseCheckFailure.malformed:
        return OTAError.parseError;
      case ReleaseCheckFailure.unknown:
        return OTAError.unknownError;
    }
  }

  /// Says what went wrong and what to do about it, rather than repeating the
  /// HTTP status or the transport's exception wording at the user.
  static String _releaseFailureMessage(ReleaseCheckFailure failure) {
    switch (failure) {
      case ReleaseCheckFailure.offline:
      case ReleaseCheckFailure.timeout:
        return 'No connection to GitHub. Check your network and try again.';
      case ReleaseCheckFailure.rateLimited:
        return 'Too many update checks right now. Try again in a few minutes.';
      case ReleaseCheckFailure.serverError:
        return 'GitHub is having trouble right now. Try again in a few minutes.';
      case ReleaseCheckFailure.malformed:
        return 'The update information could not be read.';
      case ReleaseCheckFailure.unknown:
        return 'Could not check for updates. Try again in a few minutes.';
    }
  }

  void _setStatus(OTAStatus status) {
    _status = status;
    notifyListeners();
  }

  void _handleError(OTAError error, String message) {
    _error = error;
    _errorMessage = message;
    _setStatus(OTAStatus.error);
  }

  @override
  void dispose() {
    _downloadService.cancel();
    super.dispose();
  }
}

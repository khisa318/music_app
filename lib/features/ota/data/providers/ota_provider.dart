import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/ota_model.dart';
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

  OTAStatus get status => _status;
  OTAUpdateInfo? get updateInfo => _updateInfo;
  OTADownloadProgress? get downloadProgress => _downloadProgress;
  OTAError? get error => _error;
  String? get errorMessage => _errorMessage;
  bool get hasUpdate =>
      _status == OTAStatus.updateAvailable ||
      _status == OTAStatus.downloaded ||
      _status == OTAStatus.downloading;
  bool get isUpdateUIShown => _isUpdateUIShown;
  bool get isOTAScreenActive => _isOTAScreenActive;

  /// True when the downloaded APK matched a published SHA-256.
  bool get isChecksumVerified => _checksumVerified;

  /// Where the "Open website" option sends the user.
  String get releasesUrl => _repository.releasesPage.toString();

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

        // A version the user explicitly skipped stays skipped.
        if (await _isSkipped(info.latestVersion)) {
          _finishNoUpdate(showNoUpdateMessage);
          return;
        }

        _updateInfo = info;
        _setStatus(OTAStatus.updateAvailable);
        debugPrint('[Update] ${info.versionDelta} available');

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
            outcome.message ?? 'Could not reach GitHub',
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

  /// Downloads the APK for the current update, verifies it, and stages it for
  /// the system installer.
  Future<void> downloadUpdate() async {
    final info = _updateInfo;
    if (info == null || _status == OTAStatus.downloading) return;

    _error = null;
    _errorMessage = null;
    _setStatus(OTAStatus.downloading);

    // Uses the release description the user is already looking at. No second
    // network round trip, so a flaky connection cannot strand them here.
    final result = await _downloadService.download(
      apk: info.apkAsset,
      checksumAsset: info.checksumAsset,
      host: _repository.host,
      onProgress: (progress) {
        _downloadProgress = progress;
        notifyListeners();
      },
    );

    _downloadProgress = null;

    if (result.isSuccess) {
      _downloadedFilePath = result.filePath;
      _checksumVerified = result.verified;
      _setStatus(OTAStatus.downloaded);
      debugPrint(
        '[Update] downloaded ${info.apkAssetName} '
        '(checksum verified: ${result.verified})',
      );
      return;
    }

    switch (result.failure) {
      case DownloadFailure.cancelled:
        _setStatus(OTAStatus.updateAvailable);
      case DownloadFailure.integrity:
        _handleError(
          OTAError.checksumError,
          'The download did not pass verification and was discarded',
        );
      case DownloadFailure.notEnoughSpace:
        _handleError(
          OTAError.storageError,
          'Not enough free storage to download the update',
        );
      case DownloadFailure.offline:
      case DownloadFailure.timeout:
      case DownloadFailure.server:
        _handleError(
          OTAError.downloadError,
          'Download failed. Check your connection and try again.',
        );
      case DownloadFailure.unknown:
      case null:
        _handleError(OTAError.downloadError, 'Download failed');
    }
  }

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
      _downloadedFilePath = null;
      return;
    }

    switch (result.failure) {
      case InstallFailure.permissionDenied:
        _handleError(
          OTAError.permissionError,
          'MusiX needs permission to install packages',
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
    if (_status != OTAStatus.downloading) return;
    _downloadService.cancel();
    _downloadProgress = null;
    _setStatus(OTAStatus.updateAvailable);
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

    _updateInfo = null;
    _setStatus(OTAStatus.idle);
  }

  /// Opens the GitHub release page in the device browser.
  Future<void> openReleasePage() async {
    final url = _updateInfo?.releaseUrl ?? releasesUrl;
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      case ReleaseCheckFailure.notFound:
      case ReleaseCheckFailure.unknown:
        return OTAError.unknownError;
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

import 'package:android_package_installer/android_package_installer.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Why the update could not be handed to Android's installer.
enum InstallFailure {
  /// `REQUEST_INSTALL_PACKAGES` is declared but the user has not granted
  /// "install unknown apps" for this app in system settings.
  permissionDenied,

  /// Android refused the package - typically a signature mismatch, meaning the
  /// APK was built with a different key than the installed app.
  signatureMismatch,

  /// Not enough free space to unpack the package.
  notEnoughSpace,

  /// The archive is truncated, corrupt, or not an APK at all.
  invalidPackage,

  /// The user dismissed Android's install confirmation.
  aborted,

  unknown,
}

class InstallResult {
  const InstallResult.success() : failure = null, code = null;

  const InstallResult.failed(this.failure, [this.code]);

  /// Null when Android accepted the package.
  final InstallFailure? failure;

  /// The raw `PackageInstaller` session status code, for diagnostics.
  final int? code;

  bool get isSuccess => failure == null;
}

/// Hands a verified APK to Android's own package installer.
///
/// This uses the `PackageInstaller` session API, which streams the file
/// straight into a session. Consequences that matter:
///
///   * No `file://` URI is exposed. Android has rejected `file://` intents
///     since API 24 (`FileUriExposedException`), and a content URI would
///     require a `FileProvider` grant - the session API needs neither.
///   * No silent install. `session.commit()` always surfaces Android's normal
///     confirmation dialog and the user taps Install.
///   * Android independently verifies the archive signature against the
///     certificate the installed app was signed with, so a foreign-signed APK
///     is rejected even if its checksum matches.
///   * Data is preserved: Android replaces the app in place rather than
///     uninstalling it first.
class ApkInstallerService {
  const ApkInstallerService();

  /// Requests "install unknown apps" if Android has not already granted it.
  ///
  /// On Android 8.0+ this is a special "app install" permission; on anything
  /// older it is granted automatically and the request is a no-op.
  Future<bool> ensurePermission() async {
    try {
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    } catch (error) {
      debugPrint('[Update] install permission request failed: $error');
      return false;
    }
  }

  /// Opens the system installer for [apkPath].
  ///
  /// Returns success once Android has accepted the package; the actual
  /// install is confirmed by the user on the following screen.
  Future<InstallResult> install(String apkPath) async {
    if (!await ensurePermission()) {
      return const InstallResult.failed(InstallFailure.permissionDenied);
    }

    try {
      final code = await AndroidPackageInstaller.installApk(
        apkFilePath: apkPath,
      );

      if (code == null) {
        return const InstallResult.failed(InstallFailure.unknown);
      }

      // 0 == STATUS_SUCCESS: Android took the package and will show the
      // install confirmation.
      if (code == 0) return const InstallResult.success();

      return InstallResult.failed(_classify(code), code);
    } catch (error) {
      debugPrint('[Update] installer threw: $error');
      return const InstallResult.failed(InstallFailure.unknown);
    }
  }

  /// Opens the "install unknown apps" system settings page directly.
  ///
  /// Offered when the permission is denied so the user is not stuck in a
  /// loop of re-requesting a permission the system will not grant in-app.
  Future<void> openInstallPermissionSettings() async {
    try {
      await openAppSettings();
    } catch (error) {
      debugPrint('[Update] could not open app settings: $error');
    }
  }

  /// Maps `PackageInstaller` session status codes onto actionable failures.
  static InstallFailure _classify(int code) => switch (code) {
    // PackageInstaller.PACKAGE_INSTALL_FAILURE_BLOCKED
    2 => InstallFailure.permissionDenied,
    // ..._ABORTED - the user backed out of the confirmation dialog
    3 => InstallFailure.aborted,
    // ..._INVALID - corrupt or truncated archive
    4 => InstallFailure.invalidPackage,
    // ..._CONFLICT - existing package blocks the install
    5 => InstallFailure.signatureMismatch,
    // ..._INSUFFICIENT_STORAGE
    6 => InstallFailure.notEnoughSpace,
    // ..._INCOMPATIBLE
    7 => InstallFailure.invalidPackage,
    _ => InstallFailure.unknown,
  };
}

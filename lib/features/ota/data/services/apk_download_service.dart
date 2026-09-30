import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/models/ota_model.dart';
import '../models/github_release.dart';

/// Why a download did not complete.
enum DownloadFailure {
  cancelled,
  offline,
  timeout,
  notEnoughSpace,

  /// The bytes on disk do not match the published SHA-256, or the file is not
  /// a readable APK. The file is deleted and never handed to the installer.
  integrity,

  /// 404, 5xx, or a truncated response.
  server,

  unknown,
}

class DownloadResult {
  const DownloadResult.success(this.filePath, {required this.verified})
    : failure = null,
      message = null;

  const DownloadResult.failed(this.failure, [this.message])
    : filePath = null,
      verified = false;

  /// Absolute path of a verified APK on internal storage.
  final String? filePath;

  /// True when the file matched a published SHA-256. False when the release
  /// published no checksum and the download was only sanity-checked.
  final bool verified;

  final DownloadFailure? failure;
  final String? message;

  bool get isSuccess => filePath != null;
}

/// Downloads the release APK over HTTPS, verifies it, and hands back a path.
///
/// Integrity: the release workflow publishes `musix-<version>.apk` alongside
/// `musix-<version>.apk.sha256`. The digest is downloaded from the same
/// release and compared against the bytes we received. A mismatch is treated
/// as a hard failure and the file is deleted, so a corrupted or swapped
/// download can never reach the package installer.
///
/// Note this complements rather than replaces Android's own checks: the
/// installer independently verifies the archive signature against our
/// signing certificate, so an attacker cannot install a different app over
/// MusiX even with a matching SHA-256.
class ApkDownloadService {
  ApkDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  CancelToken? _cancelToken;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _cancelToken?.cancel('cancelled by user');
  }

  bool get isCancelled => _cancelled;

  /// Runs [onProgress] with 0..1 plus byte counts while downloading.
  ///
  /// Takes the resolved assets rather than a whole release so a download can
  /// proceed from the description the user is already looking at, without a
  /// second network round trip that could fail and strand them mid-flow.
  Future<DownloadResult> download({
    required ReleaseAsset apk,
    ReleaseAsset? checksumAsset,
    required String host,
    void Function(OTADownloadProgress progress)? onProgress,
  }) async {
    // Only ever download from our own GitHub repository, over HTTPS.
    if (!apk.isTrustedHost(host) || apk.downloadUrl.scheme != 'https') {
      return const DownloadResult.failed(
        DownloadFailure.server,
        'Refusing to download from an untrusted host',
      );
    }

    _cancelled = false;
    _cancelToken = CancelToken();

    File? destination;

    try {
      final directory = await _resolveTargetDirectory();
      destination = File(p.join(directory.path, apk.name));

      // Remove any partial file from a previous attempt before resuming from
      // scratch. A truncated APK is not a valid APK and the installer would
      // reject it with an opaque error.
      if (await destination.exists()) {
        await destination.delete();
      }

      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
      final startedAt = DateTime.now();

      await _dio.download(
        apk.downloadUrl.toString(),
        destination.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          // Throttle to ~10 updates/sec; the UI does not need more and each
          // one crosses a platform channel.
          final now = DateTime.now();
          if (now.difference(lastEmit).inMilliseconds < 100) return;

          final elapsedMs = now.difference(startedAt).inMilliseconds;
          final bytesPerSecond = elapsedMs > 0
              ? (received / elapsedMs) * 1000
              : 0.0;

          lastEmit = now;

          onProgress?.call(
            OTADownloadProgress(
              downloaded: received,
              total: total > 0 ? total : apk.sizeBytes,
              percentage: total > 0 ? (received / total) * 100 : 0,
              downloadSpeed: _formatSpeed(bytesPerSecond),
              eta: _formatEta(
                total > 0 && bytesPerSecond > 0
                    ? ((total - received) / bytesPerSecond).round()
                    : null,
              ),
            ),
          );
        },
      );

      if (_cancelled) {
        return const DownloadResult.failed(DownloadFailure.cancelled);
      }

      if (!await destination.exists() || await destination.length() == 0) {
        return const DownloadResult.failed(
          DownloadFailure.integrity,
          'Downloaded file is empty',
        );
      }

      // A PKZip-based APK always starts with "PK\x03\x04". Cheap guard against
      // an HTML error page being saved as .apk.
      final header = await _readHeader(destination, 4);
      if (header.length < 4 ||
          header[0] != 0x50 ||
          header[1] != 0x4B ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        await _deleteQuietly(destination);
        return const DownloadResult.failed(
          DownloadFailure.integrity,
          'Downloaded file is not a valid APK',
        );
      }

      final expected = await _fetchExpectedDigest(apk, checksumAsset, host);
      if (expected == null) {
        // No checksum published for this release. The APK is still a valid
        // archive and will still be signature-checked by Android, but flag it
        // as unverified so the UI can be honest about it.
        return DownloadResult.success(destination.path, verified: false);
      }

      final actual = await _sha256Of(destination);
      if (actual != expected) {
        await _deleteQuietly(destination);
        debugPrint(
          '[Update] checksum mismatch: expected $expected got $actual',
        );
        return const DownloadResult.failed(
          DownloadFailure.integrity,
          'Checksum verification failed',
        );
      }

      return DownloadResult.success(destination.path, verified: true);
    } on DioException catch (error) {
      if (_cancelled || error.type == DioExceptionType.cancel) {
        await _deleteQuietly(destination);
        return const DownloadResult.failed(DownloadFailure.cancelled);
      }
      await _deleteQuietly(destination);
      return DownloadResult.failed(_classify(error), error.message);
    } on FileSystemException catch (error) {
      // ENOSPC surfaces here as "No space left on device".
      await _deleteQuietly(destination);
      final text = '${error.osError?.message ?? ''} ${error.message}'
          .toLowerCase();
      return DownloadResult.failed(
        text.contains('space')
            ? DownloadFailure.notEnoughSpace
            : DownloadFailure.unknown,
        error.message,
      );
    } catch (error) {
      await _deleteQuietly(destination);
      debugPrint('[Update] download failed: $error');
      return const DownloadResult.failed(DownloadFailure.unknown);
    } finally {
      _cancelToken = null;
    }
  }

  /// Deletes a downloaded APK. Called after a successful install, or when the
  /// user skips an update that was already on disk.
  Future<void> deleteDownloadedFile(String path) => _deleteQuietly(File(path));

  /// Internal storage under the app's own directory.
  ///
  /// Chosen over external storage so the file needs no runtime storage
  /// permission on any API level, is not visible to other apps, and is removed
  /// when the app is uninstalled.
  Future<Directory> _resolveTargetDirectory() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory(p.join(base.path, 'updates'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Reads `<apk>.sha256` from the same release.
  ///
  /// Accepts both a bare digest and the `sha256sum` output format
  /// (`<digest>  <filename>`) that `sha256sum` and the release workflow
  /// produce.
  Future<String?> _fetchExpectedDigest(
    ReleaseAsset apk,
    ReleaseAsset? asset,
    String host,
  ) async {
    if (asset == null) return null;
    if (!asset.isTrustedHost(host) || asset.downloadUrl.scheme != 'https') {
      return null;
    }

    try {
      final response = await _dio.get<String>(
        asset.downloadUrl.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      final body = (response.data ?? '').trim();
      if (body.isEmpty) return null;

      // `<digest>  <filename>`, or just `<digest>`.
      final first = body.split(RegExp(r'\s+')).first.trim().toLowerCase();
      if (first.length != 64) return null;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(first)) return null;
      return first;
    } catch (error) {
      // A missing checksum must not block the update; the APK is still
      // signature-checked by Android at install time.
      debugPrint('[Update] could not read checksum asset: $error');
      return null;
    }
  }

  Future<List<int>> _readHeader(File file, int count) async {
    final handle = await file.open();
    try {
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  /// Streams the file so a 100 MB APK is never held in memory whole.
  Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing useful to do; the OS reclaims the app directory on uninstall.
    }
  }

  static DownloadFailure _classify(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return DownloadFailure.timeout;
      case DioExceptionType.connectionError:
        return DownloadFailure.offline;
      case DioExceptionType.badResponse:
        return DownloadFailure.server;
      case DioExceptionType.cancel:
        return DownloadFailure.cancelled;
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return DownloadFailure.unknown;
    }
  }

  static String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB/s';
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }

  static String _formatEta(int? seconds) {
    if (seconds == null) return 'Estimating…';
    if (seconds < 0) return 'Estimating…';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }
}

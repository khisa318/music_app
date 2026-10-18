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
  /// The user paused. The partial file is kept so the next attempt continues.
  paused,

  /// The user gave up. The partial file is deleted.
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
  bool _paused = false;

  /// Whether the last call to [download] was stopped by [pause].
  bool get isPaused => _paused;

  bool get isCancelled => _cancelled;

  /// Stops the download but keeps the bytes already received.
  ///
  /// Calling [download] again picks up where this left off, because the partial
  /// file is left on disk and the next request asks for the remaining range.
  void pause() {
    _paused = true;
    _cancelToken?.cancel('paused by user');
  }

  /// Gives up on the download entirely and throws the partial file away.
  void cancel() {
    _cancelled = true;
    _cancelToken?.cancel('cancelled by user');
  }

  /// Runs [onProgress] with 0..1 plus byte counts while downloading.
  ///
  /// Takes the resolved assets rather than a whole release so a download can
  /// proceed from the description the user is already looking at, without a
  /// second network round trip that could fail and strand them mid-flow.
  ///
  /// Bytes are streamed into `<name>.apk.part` and only promoted to
  /// `<name>.apk` once every byte has arrived and verified. Keeping the partial
  /// file is what makes [pause] cheap: the next call sends
  /// `Range: bytes=<already on disk>-` and appends, instead of re-fetching the
  /// whole APK over a connection the user just decided was too slow.
  ///
  /// [maxBytesPerSecond] throttles the transfer for background downloads, so
  /// an auto-update never starves music streaming or other network use.
  Future<DownloadResult> download({
    required ReleaseAsset apk,
    ReleaseAsset? checksumAsset,
    required String host,
    void Function(OTADownloadProgress progress)? onProgress,
    int? maxBytesPerSecond,
  }) async {
    // Only ever download from our own GitHub repository, over HTTPS.
    if (!apk.isTrustedHost(host) || apk.downloadUrl.scheme != 'https') {
      return const DownloadResult.failed(
        DownloadFailure.server,
        'Refusing to download from an untrusted host',
      );
    }

    _cancelled = false;
    _paused = false;
    _cancelToken = CancelToken();

    File? partial;
    File? destination;

    try {
      final directory = await _resolveTargetDirectory();
      destination = File(p.join(directory.path, apk.name));
      partial = File('${destination.path}.part');

      // A finished file is stale the moment a download is requested again: the
      // caller either installs it immediately or wants a fresh copy.
      if (await destination.exists()) {
        await destination.delete();
      }

      var alreadyHave = 0;
      if (await partial.exists()) {
        alreadyHave = await partial.length();
        // Zero bytes, or a partial already at or past the published size, is
        // not a valid resume point. Start over rather than corrupt the file.
        if (alreadyHave <= 0 ||
            (apk.sizeBytes > 0 && alreadyHave >= apk.sizeBytes)) {
          await _deleteQuietly(partial);
          alreadyHave = 0;
        }
      }

      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
      final startedAt = DateTime.now();
      var fetchedThisRun = 0;

      void emit(int received, int total) {
        // Throttle to ~10 updates/sec; the UI does not need more and each one
        // crosses a platform channel.
        final now = DateTime.now();
        if (now.difference(lastEmit).inMilliseconds < 100) return;
        lastEmit = now;

        final elapsedMs = now.difference(startedAt).inMilliseconds;
        // Speed is measured over this attempt only. Including bytes fetched by
        // an earlier attempt would inflate it by however long the user spent
        // paused and make the remaining time look far shorter than it is.
        final bytesPerSecond = elapsedMs > 0
            ? (fetchedThisRun / elapsedMs) * 1000
            : 0.0;

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
      }

      // Show the resumed position straight away instead of sitting at 0% while
      // the range request is still in flight.
      if (alreadyHave > 0) {
        emit(alreadyHave, apk.sizeBytes);
      }

      final response = await _dio.get<ResponseBody>(
        apk.downloadUrl.toString(),
        options: Options(
          responseType: ResponseType.stream,
          // Asking for only the remainder is the entire point of pausing.
          headers: alreadyHave > 0 ? {'Range': 'bytes=$alreadyHave-'} : null,
          followRedirects: true,
        ),
        cancelToken: _cancelToken,
      );

      // 206 is the only status that means "here is the rest of the file".
      final partialAccepted = (response.statusCode ?? 0) == 206;

      // A server that ignores Range replies 200 with the whole file again. The
      // bytes already on disk would then be the first half of a duplicate, so
      // they have to go before writing, otherwise the APK silently doubles and
      // the checksum catches it as a mystery integrity failure.
      if (alreadyHave > 0 && !partialAccepted) {
        debugPrint('[Update] server ignored Range; restarting download');
        await _deleteQuietly(partial);
        alreadyHave = 0;
      }

      final total = _expectedTotal(response, apk.sizeBytes, alreadyHave);
      final body = response.data;
      if (body == null) {
        await _deleteQuietly(partial);
        return const DownloadResult.failed(
          DownloadFailure.server,
          'Empty response body',
        );
      }

      var received = alreadyHave;
      IOSink? sink;
      try {
        sink = partial.openWrite(
          mode: partialAccepted ? FileMode.append : FileMode.write,
        );

        await for (final chunk in body.stream) {
          received += chunk.length;
          fetchedThisRun += chunk.length;
          sink.add(chunk);
          emit(received, total);

          if (maxBytesPerSecond != null && maxBytesPerSecond > 0) {
            final targetMs = (chunk.length / maxBytesPerSecond) * 1000;
            if (targetMs >= 1) {
              await Future.delayed(
                Duration(milliseconds: targetMs.round().clamp(1, 5000)),
              );
            }
          }
        }

        await sink.flush();
      } finally {
        // Closed even when the stream throws, otherwise the last chunk can be
        // left unwritten and the resume point moves backwards.
        await sink?.close();
      }

      if (_paused) {
        // No cleanup on purpose: the bytes on disk are the resume point.
        return const DownloadResult.failed(DownloadFailure.paused);
      }

      if (_cancelled) {
        await _deleteQuietly(partial);
        return const DownloadResult.failed(DownloadFailure.cancelled);
      }

      // A stream that ends early (dropped connection, truncated response) is
      // not a completed download. Refusing here is what keeps a half APK away
      // from the installer, where it would fail with an opaque parse error.
      if (total > 0 && received != total) {
        debugPrint('[Update] truncated: got $received of $total bytes');
        return DownloadResult.failed(
          DownloadFailure.server,
          'Download ended early',
        );
      }

      if (received <= 0) {
        return const DownloadResult.failed(
          DownloadFailure.integrity,
          'Downloaded file is empty',
        );
      }

      // A PKZip-based APK always starts with "PK\x03\x04". Cheap guard against
      // an HTML error page being saved as .apk.
      final header = await _readHeader(partial, 4);
      if (header.length < 4 ||
          header[0] != 0x50 ||
          header[1] != 0x4B ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        await _deleteQuietly(partial);
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
        await partial.rename(destination.path);
        return DownloadResult.success(destination.path, verified: false);
      }

      final actual = await _sha256Of(partial);
      if (actual != expected) {
        await _deleteQuietly(partial);
        debugPrint(
          '[Update] checksum mismatch: expected $expected got $actual',
        );
        return const DownloadResult.failed(
          DownloadFailure.integrity,
          'Checksum verification failed',
        );
      }

      // Verified, so the download is finished. Promote the partial so the
      // installer never sees a file that could still be appended to.
      await partial.rename(destination.path);
      return DownloadResult.success(destination.path, verified: true);
    } on DioException catch (error) {
      // 416 means the server considered our offset past the end of the file,
      // so the partial cannot be trusted. Throw it away and let the user retry
      // from zero rather than looping on the same bad offset.
      if (error.response?.statusCode == 416) {
        debugPrint('[Update] range rejected (416); discarding partial');
        await _deleteQuietly(partial);
      } else if (_paused) {
        return const DownloadResult.failed(DownloadFailure.paused);
      } else if (_cancelled || error.type == DioExceptionType.cancel) {
        await _deleteQuietly(partial);
        return const DownloadResult.failed(DownloadFailure.cancelled);
      } else {
        final failure = _classify(error);
        if (failure == DownloadFailure.offline ||
            failure == DownloadFailure.timeout ||
            failure == DownloadFailure.server) {
          // Keep the partial: a dropped connection must not throw away bytes
          // a later attempt (or the next launch) can resume from.
          debugPrint('[Update] network failure ($failure); keeping partial');
        } else {
          await _deleteQuietly(partial);
        }
        return DownloadResult.failed(failure, error.message);
      }
      return DownloadResult.failed(_classify(error), error.message);
    } on FileSystemException catch (error) {
      // ENOSPC surfaces here as "No space left on device".
      await _deleteQuietly(partial);
      final text = '${error.osError?.message ?? ''} ${error.message}'
          .toLowerCase();
      return DownloadResult.failed(
        text.contains('space')
            ? DownloadFailure.notEnoughSpace
            : DownloadFailure.unknown,
        error.message,
      );
    } catch (error) {
      if (_paused) {
        return const DownloadResult.failed(DownloadFailure.paused);
      }
      await _deleteQuietly(partial);
      debugPrint('[Update] download failed: $error');
      return const DownloadResult.failed(DownloadFailure.unknown);
    } finally {
      _cancelToken = null;
    }
  }

  /// Deletes a downloaded APK. Called after a successful install, or when the
  /// user skips an update that was already on disk.
  Future<void> deleteDownloadedFile(String path) async {
    await _deleteQuietly(File(path));
    // Clear a leftover partial too, otherwise the next update for the same
    // asset would try to resume from a file the user already discarded.
    await _deleteQuietly(File('$path.part'));
  }

  /// Total size of the asset, preferring what the server reports.
  ///
  /// Falls back to the size GitHub published on the release asset, which is
  /// what a range response would otherwise leave us guessing at.
  static int _expectedTotal(
    Response<dynamic> response,
    int publishedSize,
    int received,
  ) {
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      // `bytes 1234-5678/9012`: the part after `/` is the full size.
      final total = int.tryParse(contentRange.split('/').last.trim());
      if (total != null && total > 0) return total;
    }

    final contentLength =
        int.tryParse(response.headers.value('content-length') ?? '');
    if (contentLength != null && contentLength > 0) {
      // A 206 reports only the length of the range, so the full asset is the
      // range plus what we already had.
      return response.statusCode == 206
          ? contentLength + received
          : contentLength;
    }

    return publishedSize;
  }

  /// Throws away a paused partial file so the next attempt starts from zero.
  ///
  /// Used when the user cancels rather than resumes, or when a paused file is
  /// for a version that is no longer being offered.
  Future<void> discardPartial(String apkName) async {
    try {
      final directory = await _resolveTargetDirectory();
      await _deleteQuietly(File(p.join(directory.path, '$apkName.part')));
    } catch (error) {
      debugPrint('[Update] could not discard partial: $error');
    }
  }

  /// Whether a resumable partial file for [apkName] is already on disk.
  Future<bool> hasPartial(String apkName) async {
    try {
      final directory = await _resolveTargetDirectory();
      final partial = File(p.join(directory.path, '$apkName.part'));
      return await partial.exists() && await partial.length() > 0;
    } catch (_) {
      return false;
    }
  }

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

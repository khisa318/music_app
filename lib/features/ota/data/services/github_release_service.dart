import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/app_repository.dart';
import '../models/github_release.dart';

/// Why an update check could not produce a release.
///
/// Every one of these is an *expected* condition - offline, rate limited,
/// GitHub having a bad minute. The app treats them all the same way: carry on
/// working and try again later.
enum ReleaseCheckFailure {
  /// No route to the network, DNS failure, airplane mode.
  offline,

  /// GitHub returned 403/429 for the anonymous request quota.
  rateLimited,

  /// 404 - the repository has no releases yet, or is private.
  notFound,

  /// Any other non-2xx response, including a GitHub 5xx outage.
  serverError,

  /// The request exceeded the configured timeout.
  timeout,

  /// 2xx, but the body was not JSON we recognise.
  malformed,

  /// Anything unclassified.
  unknown,
}

/// Result of [GitHubReleaseService.fetchLatestRelease].
///
/// A failure is data, not an exception: `checkForUpdates` must never throw and
/// must never block the user from using the app.
class ReleaseCheckResult {
  const ReleaseCheckResult.success(this.release)
    : failure = null,
      message = null;

  const ReleaseCheckResult.failed(this.failure, [this.message])
    : release = null;

  final GitHubRelease? release;
  final ReleaseCheckFailure? failure;
  final String? message;

  bool get isSuccess => release != null;

  /// A well-formed response that simply contains no installable release, e.g.
  /// the very first run before `v1.0.0` is tagged.
  const ReleaseCheckResult.empty()
    : release = null,
      failure = null,
      message = null;

  bool get isEmpty => release == null && failure == null;
}

/// Seam for tests: swap the whole HTTP call out, no network required.
typedef HttpGet = Future<Response<dynamic>> Function(Uri url);

/// Reads the app's releases from the GitHub Releases API.
///
/// Uses the JSON API (`/repos/{owner}/{repo}/releases`), never HTML scraping.
///
/// Only stable, non-draft, installable releases are returned by default.
/// Pre-releases are opt-in through [allowPreReleases], matching the existing
/// "Update channel" setting in the app.
class GitHubReleaseService {
  GitHubReleaseService({
    Dio? dio,
    AppRepository? repository,
    this.allowPreReleases = false,
  }) : repository = repository ?? AppRepository.current,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 15),
               sendTimeout: const Duration(seconds: 15),
               responseType: ResponseType.json,
               headers: const {
                 // The Releases API requires a User-Agent. Identifying the app
                 // also keeps the anonymous quota shared with other apps
                 // rather than looking like a generic script.
                 'User-Agent': 'MusiX-Android',
                 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2022-11-28',
               },
             ),
           );

  final Dio _dio;
  final AppRepository repository;

  /// When true, pre-releases are considered. Drafts never are.
  bool allowPreReleases;

  HttpGet? _httpGetOverride;

  /// Installs a fake transport. Used by tests only.
  @visibleForTesting
  void overrideHttpGet(HttpGet httpGet) => _httpGetOverride = httpGet;

  Future<Response<dynamic>> _get(Uri url) {
    final override = _httpGetOverride;
    return override != null ? override(url) : _dio.get<dynamic>(url.toString());
  }

  /// The newest release a user of this channel should be offered, or an
  /// explicit failure explaining why there isn't one.
  Future<ReleaseCheckResult> fetchLatestRelease() async {
    try {
      // `/releases/latest` already excludes drafts and pre-releases, so it is
      // the cheap path for the common stable channel. The beta channel needs
      // the list endpoint.
      final response = await _get(
        allowPreReleases ? repository.releasesApi : repository.latestReleaseApi,
      );

      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return ReleaseCheckResult.failed(_classifyStatus(status));
      }

      final data = response.data;

      final List<dynamic> candidates;
      if (data is List) {
        candidates = data;
      } else if (data is Map) {
        candidates = [data];
      } else {
        return const ReleaseCheckResult.failed(
          ReleaseCheckFailure.malformed,
          'Unexpected release payload type',
        );
      }

      final releases = <GitHubRelease>[];
      for (final entry in candidates) {
        if (entry is! Map) continue;
        try {
          releases.add(GitHubRelease.fromJson(entry.cast<String, dynamic>()));
        } catch (_) {
          // A single malformed entry must not discard the whole response.
        }
      }

      if (releases.isEmpty) return const ReleaseCheckResult.empty();

      releases.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      for (final release in releases) {
        if (release.isDraft) continue;
        if (release.isPrerelease && !allowPreReleases) continue;
        if (!release.isInstallable(host: repository.host)) continue;
        return ReleaseCheckResult.success(release);
      }

      return const ReleaseCheckResult.empty();
    } on DioException catch (error) {
      return ReleaseCheckResult.failed(_classifyDio(error), error.message);
    } catch (error) {
      debugPrint('[Update] release lookup failed: $error');
      return const ReleaseCheckResult.failed(ReleaseCheckFailure.unknown);
    }
  }

  static ReleaseCheckFailure _classifyStatus(int status) {
    if (status == 403 || status == 429) return ReleaseCheckFailure.rateLimited;
    if (status == 404) return ReleaseCheckFailure.notFound;
    if (status >= 500) return ReleaseCheckFailure.serverError;
    return ReleaseCheckFailure.unknown;
  }

  static ReleaseCheckFailure _classifyDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ReleaseCheckFailure.timeout;
      case DioExceptionType.connectionError:
        return ReleaseCheckFailure.offline;
      case DioExceptionType.badResponse:
        return _classifyStatus(error.response?.statusCode ?? 0);
      case DioExceptionType.cancel:
        return ReleaseCheckFailure.unknown;
      case DioExceptionType.badCertificate:
        return ReleaseCheckFailure.unknown;
      case DioExceptionType.unknown:
        return ReleaseCheckFailure.unknown;
    }
  }
}

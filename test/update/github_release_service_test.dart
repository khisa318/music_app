import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/ota/data/services/github_release_service.dart';

/// Answers every request with a fixed status and body, so a test can drive a
/// real [Dio] - and therefore the real status validation - without a socket.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a [Response] the way Dio would, without a network round trip.
Response<dynamic> _response(int statusCode, Object? data) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/repos/khisa318/music_app/releases'),
  statusCode: statusCode,
  data: data,
);

Map<String, dynamic> _releaseJson({
  String tag = 'v1.2.0',
  bool draft = false,
  bool prerelease = false,
  String publishedAt = '2026-09-01T10:00:00Z',
  List<Map<String, dynamic>>? assets,
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'name': tag,
    'body': '* Something changed',
    'html_url': 'https://github.com/khisa318/music_app/releases/tag/$tag',
    'published_at': publishedAt,
    'draft': draft,
    'prerelease': prerelease,
    'assets':
        assets ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'musix-$tag.apk',
            'size': 45000000,
            'browser_download_url':
                'https://github.com/khisa318/music_app/releases/download/$tag/musix-$tag.apk',
            'content_type': 'application/vnd.android.package-archive',
          },
        ],
  };
}

void main() {
  late List<Uri> requested;

  setUp(() {
    requested = <Uri>[];
  });

  GitHubReleaseService serviceWith(Response<dynamic> Function(Uri url) fake) {
    final service = GitHubReleaseService();
    service.overrideHttpGet((url) {
      requested.add(url);
      return Future<Response<dynamic>>.value(fake(url));
    });
    return service;
  }

  group('URL', () {
    test('stable channel uses the /releases/latest endpoint', () async {
      final service = serviceWith((_) => _response(200, _releaseJson()));
      await service.fetchLatestRelease();

      expect(requested.single.path, contains('/releases/latest'));
    });

    test('beta channel uses the list endpoint', () async {
      final service = GitHubReleaseService(allowPreReleases: true);
      service.overrideHttpGet((url) {
        requested.add(url);
        return Future<Response<dynamic>>.value(
          _response(200, <Map<String, dynamic>>[_releaseJson()]),
        );
      });
      await service.fetchLatestRelease();

      expect(requested.single.path, contains('/releases'));
      expect(requested.single.path, isNot(contains('latest')));
    });

    test('always targets this repository over https', () async {
      final service = serviceWith((_) => _response(200, _releaseJson()));
      await service.fetchLatestRelease();

      expect(requested.single.host, 'api.github.com');
      expect(requested.single.path, startsWith('/repos/khisa318/music_app'));
    });
  });

  group('success', () {
    test('accepts a single release object', () async {
      final service = serviceWith((_) => _response(200, _releaseJson()));

      final result = await service.fetchLatestRelease();

      expect(result.isSuccess, isTrue);
      expect(result.release?.tagName, 'v1.2.0');
      expect(result.release?.version?.publicVersion, '1.2.0');
      expect(result.failure, isNull);
    });

    test('accepts a list and picks the newest installable entry', () async {
      final service = GitHubReleaseService(allowPreReleases: true);
      service.overrideHttpGet((_) {
        return Future<Response<dynamic>>.value(
          _response(
            200,
            <Map<String, dynamic>>[
              _releaseJson(tag: 'v1.1.0', publishedAt: '2026-01-01T00:00:00Z'),
              _releaseJson(tag: 'v1.3.0', publishedAt: '2026-06-01T00:00:00Z'),
              _releaseJson(tag: 'v1.2.0', publishedAt: '2026-03-01T00:00:00Z'),
            ],
          ),
        );
      });

      final result = await service.fetchLatestRelease();

      expect(result.release?.tagName, 'v1.3.0');
    });

    test('skips drafts and picks the next candidate', () async {
      final service = serviceWith(
        (_) => _response(
          200,
          <Map<String, dynamic>>[
            _releaseJson(tag: 'v2.0.0', draft: true),
            _releaseJson(tag: 'v1.9.0'),
          ],
        ),
      );

      final result = await service.fetchLatestRelease();

      expect(result.release?.tagName, 'v1.9.0');
    });

    test('skips pre-releases on the stable channel', () async {
      final service = serviceWith(
        (_) => _response(
          200,
          <Map<String, dynamic>>[
            _releaseJson(tag: 'v1.3.0-beta.1', prerelease: true),
            _releaseJson(tag: 'v1.2.0'),
          ],
        ),
      );

      final result = await service.fetchLatestRelease();

      expect(result.release?.tagName, 'v1.2.0');
    });

    test('accepts a pre-release on the beta channel', () async {
      final service = GitHubReleaseService(allowPreReleases: true);
      service.overrideHttpGet((_) {
        return Future<Response<dynamic>>.value(
          _response(
            200,
            <Map<String, dynamic>>[
              _releaseJson(tag: 'v1.3.0-beta.1', prerelease: true),
              _releaseJson(tag: 'v1.2.0'),
            ],
          ),
        );
      });

      final result = await service.fetchLatestRelease();

      expect(result.release?.tagName, 'v1.3.0-beta.1');
    });

    test('skips a release whose APK is on the wrong host', () async {
      final service = serviceWith((_) {
        return _response(
          200,
          <Map<String, dynamic>>[
            _releaseJson(
              tag: 'v2.0.0',
              assets: <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'musix.apk',
                  'size': 1,
                  'browser_download_url': 'https://cdn.evil.example/musix.apk',
                  'content_type': 'application/vnd.android.package-archive',
                },
              ],
            ),
            _releaseJson(tag: 'v1.2.0'),
          ],
        );
      });

      final result = await service.fetchLatestRelease();

      expect(result.release?.tagName, 'v1.2.0');
    });

    test('skips a release tagged with something that is not a version', () async {
      final service = serviceWith((_) {
        return _response(
          200,
          <Map<String, dynamic>>[_releaseJson(tag: 'nightly')],
        );
      });

      final result = await service.fetchLatestRelease();

      expect(result.isSuccess, isFalse);
      expect(result.isEmpty, isTrue);
    });

    test('survives one malformed entry in a list', () async {
      final service = serviceWith((_) {
        return _response(
          200,
          <Object>[
            'not-a-map',
            <String, dynamic>{'tag_name': 12345},
            _releaseJson(),
          ],
        );
      });

      final result = await service.fetchLatestRelease();

      expect(result.release?.tagName, 'v1.2.0');
    });

    test('accepts an empty array as "no releases yet"', () async {
      final service = serviceWith((_) => _response(200, <dynamic>[]));

      final result = await service.fetchLatestRelease();

      expect(result.isEmpty, isTrue);
      expect(result.failure, isNull);
      expect(result.isSuccess, isFalse);
    });
  });

  group('failures', () {
    test('404 from /releases/latest means "no releases yet"', () async {
      // GitHub answers 404 for a project that has never published a release.
      // The beta channel sees the same state as 200 with an empty array, so
      // neither may be reported as a failure.
      final service = serviceWith((_) => _response(404, null));

      final result = await service.fetchLatestRelease();

      expect(result.isEmpty, isTrue);
      expect(result.failure, isNull);
      expect(result.isSuccess, isFalse);
    });

    test('a real 404 response is not thrown by validateStatus', () async {
      // The other tests in this group fake the transport, which skips Dio's own
      // status handling. This one drives a real Dio built from the app's
      // production options, so it covers the exact path that used to surface
      // "validateStatus was configured to throw for this status code".
      final service = GitHubReleaseService(
        dio: Dio(GitHubReleaseService.baseOptions)
          ..httpClientAdapter = _StubAdapter(404, ''),
      );

      final result = await service.fetchLatestRelease();

      expect(result.isEmpty, isTrue);
      expect(result.failure, isNull);
    });

    test('other non-2xx statuses still throw and are classified', () async {
      for (final status in <int>[403, 500, 502]) {
        final service = GitHubReleaseService(
          dio: Dio(GitHubReleaseService.baseOptions)
            ..httpClientAdapter = _StubAdapter(status, ''),
        );

        expect((await service.fetchLatestRelease()).failure, isNotNull,
            reason: '$status');
      }
    });

    test('403 and 429 become rateLimited', () async {
      for (final status in <int>[403, 429]) {
        final service = serviceWith((_) => _response(status, null));
        final result = await service.fetchLatestRelease();
        expect(
          result.failure,
          ReleaseCheckFailure.rateLimited,
          reason: '$status',
        );
      }
    });

    test('5xx becomes serverError', () async {
      for (final status in <int>[500, 502, 503]) {
        final service = serviceWith((_) => _response(status, null));
        expect((await service.fetchLatestRelease()).failure,
            ReleaseCheckFailure.serverError);
      }
    });

    test('an unclassified 4xx becomes unknown', () async {
      final service = serviceWith((_) => _response(418, null));
      expect(
        (await service.fetchLatestRelease()).failure,
        ReleaseCheckFailure.unknown,
      );
    });

    test('a connection error becomes offline', () async {
      final service = GitHubReleaseService();
      service.overrideHttpGet((_) {
        return Future<Response<dynamic>>.error(
          DioException(
            requestOptions: RequestOptions(path: '/repos'),
            type: DioExceptionType.connectionError,
          ),
        );
      });

      final result = await service.fetchLatestRelease();

      expect(result.failure, ReleaseCheckFailure.offline);
    });

    test('every timeout type becomes timeout', () async {
      for (final type in <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        final service = GitHubReleaseService();
        service.overrideHttpGet((_) {
          return Future<Response<dynamic>>.error(
            DioException(
              requestOptions: RequestOptions(path: '/repos'),
              type: type,
            ),
          );
        });

        expect(
          (await service.fetchLatestRelease()).failure,
          ReleaseCheckFailure.timeout,
          reason: '$type',
        );
      }
    });

    test('a non-JSON payload becomes malformed', () async {
      // A proxy or captive portal returning HTML must not be parsed as JSON.
      final service = serviceWith((_) => _response(200, '<html>nope</html>'));

      final result = await service.fetchLatestRelease();

      expect(result.failure, ReleaseCheckFailure.malformed);
    });

    test('an unexpected non-throwing error never escapes', () async {
      final service = GitHubReleaseService();
      service.overrideHttpGet((_) {
        return Future<Response<dynamic>>.error(
          StateError('something unexpected'),
        );
      });

      // checkForUpdates must never throw: an update check is never allowed to
      // stop the user using the app.
      final result = await service.fetchLatestRelease();

      expect(result.failure, ReleaseCheckFailure.unknown);
    });

    test('a 2xx with a null body becomes malformed, not a crash', () async {
      final service = serviceWith((_) => _response(200, null));

      final result = await service.fetchLatestRelease();

      expect(result.failure, ReleaseCheckFailure.malformed);
    });
  });
}
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:music_app/features/ota/data/models/github_release.dart';
import 'package:music_app/features/ota/data/services/apk_download_service.dart';
import 'package:music_app/core/models/ota_model.dart';

/// A path provider that hands out a temp folder, so the service writes where
/// the test can inspect it instead of onto a device.
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Serves a scripted [ResponseBody] per request so resume behaviour can be
/// driven precisely: which `Range` was asked for, and whether the reply is a
/// 206 or a whole-file 200.
///
/// Dio 5's [Dio] only has factory constructors, so it cannot be subclassed with
/// a generative constructor. The supported seam is the adapter instead: the
/// test installs this on a real [Dio] and Dio performs the request/response
/// plumbing (status code, headers, response type) exactly as it would in
/// production.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responder);

  /// Called with the resolved request options; returns the body to hand back.
  final FutureOr<ResponseBody> Function(RequestOptions options) responder;

  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final body = await responder(options);
    if (cancelFuture == null) return body;
    return _cancelable(body, options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

/// Wraps [body] so that cancelling the request tears the stream down with a
/// [DioException], which is what the service's pause path relies on.
ResponseBody _cancelable(
  ResponseBody body,
  RequestOptions options,
  Future<void> cancelFuture,
) {
  final controller = StreamController<Uint8List>();
  StreamSubscription<Uint8List>? subscription;
  var closed = false;

  void finish() {
    if (closed) return;
    closed = true;
    subscription?.cancel();
    controller.close();
  }

  cancelFuture.then((_) {
    if (closed) return;
    controller.addError(
      DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled by the test',
      ),
    );
    finish();
  });

  subscription = body.stream.listen(
    controller.add,
    onError: (Object error, StackTrace stackTrace) {
      controller.addError(error, stackTrace);
      finish();
    },
    onDone: finish,
    cancelOnError: true,
  );

  return ResponseBody(
    controller.stream,
    body.statusCode,
    headers: body.headers,
    statusMessage: body.statusMessage,
    isRedirect: body.isRedirect,
    redirects: body.redirects,
  );
}

Dio _dioWith(_ScriptedAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  /// A believable APK: the service only checks the PKZip magic and, when a
  /// checksum is supplied, the SHA-256.
  final apkBytes = Uint8List.fromList([
    0x50, 0x4B, 0x03, 0x04, // "PK\x03\x04"
    ...List<int>.generate(60 * 1024, (i) => i % 251),
  ]);

  ReleaseAsset apkAsset({int? size}) => ReleaseAsset(
    name: 'musix-test.apk',
    sizeBytes: size ?? apkBytes.length,
    downloadUrl: Uri.parse('https://github.test/musix-test.apk'),
    contentType: 'application/vnd.android.package-archive',
  );

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('apk_resume_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPathProvider(tempRoot.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  File partialFile(String name) =>
      File(p.join(tempRoot.path, 'updates', '$name.part'));

  File finalFile(String name) => File(p.join(tempRoot.path, 'updates', name));

  ResponseBody body(
    Uint8List bytes,
    int statusCode, [
    Map<String, List<String>> headers = const {},
  ]) {
    return ResponseBody(
      Stream<Uint8List>.value(bytes),
      statusCode,
      headers: headers,
    );
  }

  test('fresh download writes the APK and leaves no partial behind', () async {
    final service = ApkDownloadService(
      dio: _dioWith(
        _ScriptedAdapter(
          (options) async => body(apkBytes, 200, {
            'content-length': [apkBytes.length.toString()],
          }),
        ),
      ),
    );

    final result = await service.download(apk: apkAsset(), host: 'github.test');

    expect(result.isSuccess, isTrue);
    expect(result.filePath, finalFile('musix-test.apk').path);
    expect(finalFile('musix-test.apk').readAsBytesSync(), apkBytes);
    expect(partialFile('musix-test.apk').existsSync(), isFalse);
  });

  test('a paused download keeps its partial file for later', () async {
    late final ApkDownloadService service;

    service = ApkDownloadService(
      dio: _dioWith(
        _ScriptedAdapter((options) async {
          // A server that dribbles the body out, so the pause lands mid-stream.
          final controller = StreamController<Uint8List>();
          scheduleMicrotask(() async {
            for (var offset = 0; offset < apkBytes.length; offset += 4096) {
              final end = (offset + 4096).clamp(0, apkBytes.length);
              controller.add(Uint8List.sublistView(apkBytes, offset, end));
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            await controller.close();
          });

          // Pause as soon as the transfer is under way.
          scheduleMicrotask(
            () => Future<void>.delayed(
              const Duration(milliseconds: 20),
              service.pause,
            ),
          );

          return ResponseBody(
            controller.stream,
            200,
            headers: {
              'content-length': [apkBytes.length.toString()],
            },
          );
        }),
      ),
    );

    final result = await service.download(apk: apkAsset(), host: 'github.test');

    expect(result.failure, DownloadFailure.paused);
    expect(
      partialFile('musix-test.apk').existsSync(),
      isTrue,
      reason: 'pause must not throw away what was already received',
    );
    expect(partialFile('musix-test.apk').lengthSync(), greaterThan(0));
    expect(
      partialFile('musix-test.apk').lengthSync(),
      lessThan(apkBytes.length),
    );
    expect(finalFile('musix-test.apk').existsSync(), isFalse);
  });

  test('resuming asks for the remaining range and appends', () async {
    // Seed a partial file exactly as an interrupted download would leave it.
    final seed = Uint8List.sublistView(apkBytes, 0, 4096);
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(seed);

    final adapter = _ScriptedAdapter((options) async {
      final range = options.headers['Range'] ?? options.headers['range'];
      expect(range, 'bytes=4096-', reason: 'resume must skip what is on disk');

      return ResponseBody(
        Stream<Uint8List>.value(Uint8List.sublistView(apkBytes, 4096)),
        206,
        headers: {
          'content-range': [
            'bytes 4096-${apkBytes.length - 1}/${apkBytes.length}',
          ],
          'content-length': [(apkBytes.length - 4096).toString()],
        },
      );
    });

    final service = ApkDownloadService(dio: _dioWith(adapter));
    final result = await service.download(apk: apkAsset(), host: 'github.test');

    expect(result.isSuccess, isTrue);
    expect(finalFile('musix-test.apk').readAsBytesSync(), apkBytes);
    expect(
      partialFile('musix-test.apk').existsSync(),
      isFalse,
      reason: 'a finished download must not leave a resumable partial',
    );
  });

  test(
    'a server that ignores Range restarts instead of doubling the file',
    () async {
      partialFile('musix-test.apk')
        ..createSync(recursive: true)
        ..writeAsBytesSync(Uint8List.sublistView(apkBytes, 0, 4096));

      final service = ApkDownloadService(
        dio: _dioWith(
          _ScriptedAdapter((options) async {
            expect(options.headers['Range'], 'bytes=4096-');

            // Deliberately answers 200 with the whole file, the way some CDNs do
            // when they do not handle Range.
            return body(apkBytes, 200, {
              'content-length': [apkBytes.length.toString()],
            });
          }),
        ),
      );

      final result = await service.download(
        apk: apkAsset(),
        host: 'github.test',
      );

      expect(result.isSuccess, isTrue);
      expect(
        finalFile('musix-test.apk').readAsBytesSync(),
        apkBytes,
        reason:
            'appending to the partial would have produced a double-length APK',
      );
    },
  );

  test('a truncated body is rejected and the partial discarded', () async {
    final service = ApkDownloadService(
      dio: _dioWith(
        _ScriptedAdapter((options) async {
          // Server claims the full size but sends half and closes.
          return body(
            Uint8List.sublistView(apkBytes, 0, apkBytes.length ~/ 2),
            200,
            {
              'content-length': [apkBytes.length.toString()],
            },
          );
        }),
      ),
    );

    final result = await service.download(apk: apkAsset(), host: 'github.test');

    expect(result.failure, DownloadFailure.server);
    expect(result.message, contains('ended early'));
    expect(finalFile('musix-test.apk').existsSync(), isFalse);
  });

  test(
    'a partial at or past the published size is not used as a resume point',
    () async {
      // A partial longer than the asset cannot be part of it, so it must be
      // thrown away instead of being sent as a Range that will 416.
      partialFile('musix-test.apk')
        ..createSync(recursive: true)
        ..writeAsBytesSync(Uint8List(apkBytes.length + 512));

      final service = ApkDownloadService(
        dio: _dioWith(
          _ScriptedAdapter((options) async {
            expect(
              options.headers.containsKey('Range'),
              isFalse,
              reason: 'an over-long partial must trigger a clean download',
            );
            return body(apkBytes, 200, {
              'content-length': [apkBytes.length.toString()],
            });
          }),
        ),
      );

      final result = await service.download(
        apk: apkAsset(),
        host: 'github.test',
      );

      expect(result.isSuccess, isTrue);
      expect(finalFile('musix-test.apk').readAsBytesSync(), apkBytes);
    },
  );

  test('discardPartial removes the saved bytes', () async {
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

    await ApkDownloadService().discardPartial('musix-test.apk');

    expect(partialFile('musix-test.apk').existsSync(), isFalse);
  });

  test(
    'deleteDownloadedFile clears the finished APK and its partial',
    () async {
      finalFile('musix-test.apk')
        ..createSync(recursive: true)
        ..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      partialFile('musix-test.apk')
        ..createSync(recursive: true)
        ..writeAsBytesSync(Uint8List.fromList([4, 5]));

      await ApkDownloadService().deleteDownloadedFile(
        finalFile('musix-test.apk').path,
      );

      expect(finalFile('musix-test.apk').existsSync(), isFalse);
      expect(partialFile('musix-test.apk').existsSync(), isFalse);
    },
  );

  test('an untrusted host is refused before any request is made', () async {
    final adapter = _ScriptedAdapter(
      (options) async => throw StateError('must not be called'),
    );

    final result = await ApkDownloadService(
      dio: _dioWith(adapter),
    ).download(apk: apkAsset(), host: 'someone-else.test');

    expect(result.failure, DownloadFailure.server);
    expect(adapter.seen, isEmpty);
  });

  test('progress reports carry the resumed byte count, not zero', () async {
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.sublistView(apkBytes, 0, 4096));

    final seen = <OTADownloadProgress>[];

    final service = ApkDownloadService(
      dio: _dioWith(
        _ScriptedAdapter((options) async {
          // Emit one real chunk so the throttled callback actually fires.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return ResponseBody(
            Stream<Uint8List>.value(Uint8List.sublistView(apkBytes, 4096)),
            206,
            headers: {
              'content-range': [
                'bytes 4096-${apkBytes.length - 1}/${apkBytes.length}',
              ],
            },
          );
        }),
      ),
    );

    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
      onProgress: seen.add,
    );

    expect(result.isSuccess, isTrue);
    expect(seen, isNotEmpty);
    // The UI has to jump straight to where the user left off, never to 0%.
    expect(seen.first.downloaded, greaterThanOrEqualTo(4096));
    expect(seen.last.percentage, closeTo(100, 0.001));
  });
}

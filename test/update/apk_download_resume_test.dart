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

/// Serves a scripted response per request so resume behaviour can be driven
/// precisely: which `Range` was asked for, and whether the reply is a 206 or a
/// whole-file 200.
class _ScriptedDio extends Dio {
  _ScriptedDio(this.responder);

  /// Called with the request options; returns the response to hand back.
  final FutureOr<Response<ResponseBody>> Function(
    String url,
    Options options,
  ) responder;

  final List<Options> seen = [];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final opts = options ?? Options();
    seen.add(opts);

    // Honour the token exactly like the real adapter does, so a pause
    // mid-stream tears the transfer down instead of quietly completing.
    cancelToken?.whenCancel.then((reason) {
      throw DioException.requestCancelled(
        requestOptions: opts,
        reason: reason.toString(),
      );
    });

    final response = await responder(path, opts);
    return Response<ResponseBody>.fromStream(
      Stream<ResponseBody>.value(response),
      opts,
    ) as Response<T>;
  }
}

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

  File partialFile(String name) => File(
    p.join(tempRoot.path, 'updates', '$name.part'),
  );

  File finalFile(String name) => File(p.join(tempRoot.path, 'updates', name));

  test('fresh download writes the APK and leaves no partial behind', () async {
    final service = ApkDownloadService(
      dio: _ScriptedDio(
        (url, options) async => Response<ResponseBody>(
          ResponseBody(
            Stream<Uint8List>.value(apkBytes),
            200,
            headers: {
              'content-length': [apkBytes.length.toString()],
            },
          ),
          200,
        ),
      ),
    );

    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
    );

    expect(result.isSuccess, isTrue);
    expect(result.filePath, finalFile('musix-test.apk').path);
    expect(finalFile('musix-test.apk').readAsBytesSync(), apkBytes);
    expect(partialFile('musix-test.apk').existsSync(), isFalse);
  });

  test('a paused download keeps its partial file for later', () async {
    final service = ApkDownloadService(
      dio: _ScriptedDio(
        (url, options) async {
          // A server that dribbles the body out, so the pause lands mid-stream.
          final controller = StreamController<Uint8List>();
          scheduleMicrotask(() async {
            for (var offset = 0; offset < apkBytes.length; offset += 4096) {
              final end = (offset + 4096).clamp(0, apkBytes.length);
              controller.add(
                Uint8List.sublistView(apkBytes, offset, end),
              );
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

          return Response<ResponseBody>(
            ResponseBody(
              controller.stream,
              200,
              headers: {
                'content-length': [apkBytes.length.toString()],
              },
            ),
            200,
          );
        },
      ),
    );

    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
    );

    expect(result.failure, DownloadFailure.paused);
    expect(
      partialFile('musix-test.apk').existsSync(),
      isTrue,
      reason: 'pause must not throw away what was already received',
    );
    expect(partialFile('musix-test.apk').lengthSync(), greaterThan(0));
    expect(partialFile('musix-test.apk').lengthSync(), lessThan(apkBytes.length));
    expect(finalFile('musix-test.apk').existsSync(), isFalse);
  });

  test('resuming asks for the remaining range and appends', () async {
    // Seed a partial file exactly as an interrupted download would leave it.
    final seed = Uint8List.sublistView(apkBytes, 0, 4096);
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(seed);

    final dio = _ScriptedDio((url, options) async {
      final range = options.headers['Range'] ?? options.headers['range'];
      expect(range, 'bytes=4096-', reason: 'resume must skip what is on disk');

      return Response<ResponseBody>(
        ResponseBody(
          Stream<Uint8List>.value(
            Uint8List.sublistView(apkBytes, 4096),
          ),
          206,
          headers: {
            'content-range': ['bytes 4096-${apkBytes.length - 1}/${apkBytes.length}'],
            'content-length': [(apkBytes.length - 4096).toString()],
          },
        ),
        206,
      );
    });

    final service = ApkDownloadService(dio: dio);
    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
    );

    expect(result.isSuccess, isTrue);
    expect(finalFile('musix-test.apk').readAsBytesSync(), apkBytes);
    expect(
      partialFile('musix-test.apk').existsSync(),
      isFalse,
      reason: 'a finished download must not leave a resumable partial',
    );
  });

  test('a server that ignores Range restarts instead of doubling the file',
      () async {
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.sublistView(apkBytes, 0, 4096));

    final service = ApkDownloadService(
      dio: _ScriptedDio((url, options) async {
        expect(options.headers['Range'], 'bytes=4096-');

        // Deliberately answers 200 with the whole file, the way some CDNs do
        // when they do not handle Range.
        return Response<ResponseBody>(
          ResponseBody(
            Stream<Uint8List>.value(apkBytes),
            200,
            headers: {
              'content-length': [apkBytes.length.toString()],
            },
          ),
          200,
        );
      }),
    );

    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
    );

    expect(result.isSuccess, isTrue);
    expect(
      finalFile('musix-test.apk').readAsBytesSync(),
      apkBytes,
      reason: 'appending to the partial would have produced a double-length APK',
    );
  });

  test('a truncated body is rejected and the partial discarded', () async {
    final service = ApkDownloadService(
      dio: _ScriptedDio((url, options) async {
        // Server claims the full size but sends half and closes.
        return Response<ResponseBody>(
          ResponseBody(
            Stream<Uint8List>.value(
              Uint8List.sublistView(apkBytes, 0, apkBytes.length ~/ 2),
            ),
            200,
            headers: {
              'content-length': [apkBytes.length.toString()],
            },
          ),
          200,
        );
      }),
    );

    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
    );

    expect(result.failure, DownloadFailure.server);
    expect(result.message, contains('ended early'));
    expect(finalFile('musix-test.apk').existsSync(), isFalse);
  });

  test('a partial at or past the published size is not used as a resume point',
      () async {
    // A partial longer than the asset cannot be part of it, so it must be
    // thrown away instead of being sent as a Range that will 416.
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        Uint8List(apkBytes.length + 512),
      );

    final service = ApkDownloadService(
      dio: _ScriptedDio((url, options) async {
        expect(
          options.headers.containsKey('Range'),
          isFalse,
          reason: 'an over-long partial must trigger a clean download',
        );
        return Response<ResponseBody>(
          ResponseBody(
            Stream<Uint8List>.value(apkBytes),
            200,
            headers: {
              'content-length': [apkBytes.length.toString()],
            },
          ),
          200,
        );
      }),
    );

    final result = await service.download(
      apk: apkAsset(),
      host: 'github.test',
    );

    expect(result.isSuccess, isTrue);
    expect(finalFile('musix-test.apk').readAsBytesSync(), apkBytes);
  });

  test('discardPartial removes the saved bytes', () async {
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

    await ApkDownloadService().discardPartial('musix-test.apk');

    expect(partialFile('musix-test.apk').existsSync(), isFalse);
  });

  test('deleteDownloadedFile clears the finished APK and its partial', () async {
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
  });

  test('an untrusted host is refused before any request is made', () async {
    final dio = _ScriptedDio(
      (url, options) async => throw StateError('must not be called'),
    );

    final result = await ApkDownloadService(dio: dio).download(
      apk: apkAsset(),
      host: 'someone-else.test',
    );

    expect(result.failure, DownloadFailure.server);
    expect(dio.seen, isEmpty);
  });

  test('progress reports carry the resumed byte count, not zero', () async {
    partialFile('musix-test.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.sublistView(apkBytes, 0, 4096));

    final seen = <OTADownloadProgress>[];

    final service = ApkDownloadService(
      dio: _ScriptedDio((url, options) async {
        // Emit one real chunk so the throttled callback actually fires.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return Response<ResponseBody>(
          ResponseBody(
            Stream<Uint8List>.value(
              Uint8List.sublistView(apkBytes, 4096),
            ),
            206,
            headers: {
              'content-range': [
                'bytes 4096-${apkBytes.length - 1}/${apkBytes.length}',
              ],
            },
          ),
          206,
        );
      }),
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
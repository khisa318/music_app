import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/network_failure.dart';

NetworkFailure _classify(Object error) => NetworkFailure.classify(error);

DioException _dio(DioExceptionType type, {int? statusCode, Object? inner}) =>
    DioException(
      requestOptions: RequestOptions(path: '/releases/latest'),
      type: type,
      response: statusCode == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: '/releases/latest'),
              statusCode: statusCode,
            ),
      error: inner,
    );

void main() {
  group('NetworkFailure.classify', () {
    test('a socket failure means there was no connection', () {
      expect(
        _classify(const SocketException('Failed host lookup')).kind,
        NetworkFailureKind.offline,
      );
    });

    test('a DNS or TLS failure also means there was no connection', () {
      expect(
        _classify(const HandshakeException('handshake failed')).kind,
        NetworkFailureKind.offline,
      );
      expect(
        _classify(const TlsException('handshake')).kind,
        NetworkFailureKind.offline,
      );
      expect(
        _classify(HttpException('unreachable')).kind,
        NetworkFailureKind.offline,
      );
    });

    test('a Dio connection error is offline, not a server problem', () {
      expect(
        _classify(_dio(DioExceptionType.connectionError)).kind,
        NetworkFailureKind.offline,
      );
      expect(
        _classify(_dio(DioExceptionType.badCertificate)).kind,
        NetworkFailureKind.offline,
      );
    });

    test('every Dio timeout reads as a timeout', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        expect(
          _classify(_dio(type)).kind,
          NetworkFailureKind.timeout,
          reason: '$type should read as a timeout',
        );
      }
    });

    test('a plain TimeoutException is a timeout', () {
      expect(
        _classify(TimeoutException('took too long')).kind,
        NetworkFailureKind.timeout,
      );
    });

    test('a 5xx is the server failing', () {
      final failure = _classify(
        _dio(DioExceptionType.badResponse, statusCode: 503),
      );

      expect(failure.kind, NetworkFailureKind.server);
      expect(failure.statusCode, 503);
    });

    test('a 4xx is the request being rejected and is not worth a retry', () {
      final failure = _classify(
        _dio(DioExceptionType.badResponse, statusCode: 404),
      );

      expect(failure.kind, NetworkFailureKind.request);
      expect(failure.canRetry, isFalse);
    });

    test('a 403 is likewise not retried', () {
      expect(
        _classify(_dio(DioExceptionType.badResponse, statusCode: 403)).canRetry,
        isFalse,
      );
    });

    test('a Dio error with no type is judged by its cause', () {
      expect(
        _classify(
          _dio(
            DioExceptionType.unknown,
            inner: const SocketException('Network is unreachable'),
          ),
        ).kind,
        NetworkFailureKind.offline,
      );
    });

    test('a Dio error with neither type nor cause stays unknown', () {
      expect(
        _classify(_dio(DioExceptionType.unknown)).kind,
        NetworkFailureKind.unknown,
      );
      expect(
        _classify(_dio(DioExceptionType.cancel)).kind,
        NetworkFailureKind.unknown,
      );
    });

    test('an already classified failure is passed through unchanged', () {
      const original = NetworkFailure(
        NetworkFailureKind.timeout,
        statusCode: 504,
      );

      expect(_classify(original), same(original));
    });

    test('an unrecognised error is unknown rather than being lost', () {
      expect(_classify(StateError('boom')).kind, NetworkFailureKind.unknown);
    });
  });

  group('NetworkFailure', () {
    test('each kind offers a different translation key', () {
      final keys = NetworkFailureKind.values
          .map((kind) => NetworkFailure(kind).messageKey)
          .toSet();

      expect(keys, hasLength(NetworkFailureKind.values.length));
      expect(keys, everyElement(isNotEmpty));
    });

    test('offline, timeout and server failures can be retried', () {
      for (final kind in [
        NetworkFailureKind.offline,
        NetworkFailureKind.timeout,
        NetworkFailureKind.server,
        NetworkFailureKind.unknown,
      ]) {
        expect(NetworkFailure(kind).canRetry, isTrue, reason: kind.name);
      }
    });

    test('the failure keeps the status code and the cause for the log', () {
      final cause = StateError('boom');
      final failure = NetworkFailure(
        NetworkFailureKind.server,
        statusCode: 500,
        cause: cause,
      );

      expect(failure.cause, same(cause));
      expect(failure.toString(), contains('server'));
      expect(failure.toString(), contains('500'));
    });

    test('a failure with no status code leaves it out', () {
      expect(
        NetworkFailure(NetworkFailureKind.offline).toString(),
        isNot(contains('status')),
      );
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// What kind of failure a request ended in.
///
/// Every network call in the app funnels through here so the UI can say
/// something the reader can act on, instead of leaking a raw
/// `SocketException` or a Dio type name into a snackbar.
enum NetworkFailureKind {
  /// The request never reached a server: no usable connection, DNS failure or
  /// a rejected TLS handshake.
  offline,

  /// The connection was there, but nothing came back in time.
  timeout,

  /// The server answered with a failure of its own.
  server,

  /// The request was turned down before it was worth sending again.
  request,

  /// Anything that could not be placed.
  unknown,
}

/// A request failure described in terms the UI can present.
class NetworkFailure implements Exception {
  const NetworkFailure(this.kind, {this.statusCode, this.cause});

  final NetworkFailureKind kind;
  final int? statusCode;
  final Object? cause;

  /// Sending the same request again can only help when it never landed, or
  /// when the far side was the part that failed. A rejected request will be
  /// rejected again.
  bool get canRetry => kind != NetworkFailureKind.request;

  /// The translation key holding the message for this kind of failure.
  String get messageKey => switch (kind) {
    NetworkFailureKind.offline => 'error_no_internet',
    NetworkFailureKind.timeout => 'error_request_timed_out',
    NetworkFailureKind.server => 'error_server_unavailable',
    NetworkFailureKind.request => 'error_request_rejected',
    NetworkFailureKind.unknown => 'error_unexpected',
  };

  @override
  String toString() =>
      'NetworkFailure(${kind.name}'
      '${statusCode == null ? '' : ', status $statusCode'})';

  /// Places [error] into one of the kinds above.
  ///
  /// Passing an existing [NetworkFailure] through returns it unchanged, so a
  /// service that already classified its failure does not get flattened.
  static NetworkFailure classify(Object error) {
    if (error is NetworkFailure) {
      return error;
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return NetworkFailure(NetworkFailureKind.timeout, cause: error);
        case DioExceptionType.connectionError:
        case DioExceptionType.badCertificate:
          return NetworkFailure(NetworkFailureKind.offline, cause: error);
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          return NetworkFailure(
            code != null && code >= 500
                ? NetworkFailureKind.server
                : NetworkFailureKind.request,
            statusCode: code,
            cause: error,
          );
        case DioExceptionType.cancel:
          return NetworkFailure(NetworkFailureKind.unknown, cause: error);
        case DioExceptionType.unknown:
          // Dio wraps transport failures without giving them a type of their
          // own, so the real cause is worth another look.
          final cause = error.error;
          return cause == null
              ? NetworkFailure(NetworkFailureKind.unknown, cause: error)
              : classify(cause);
      }
    }

    if (error is TimeoutException) {
      return NetworkFailure(NetworkFailureKind.timeout, cause: error);
    }

    if (error is SocketException ||
        error is HandshakeException ||
        error is TlsException ||
        error is HttpException) {
      return NetworkFailure(NetworkFailureKind.offline, cause: error);
    }

    return NetworkFailure(NetworkFailureKind.unknown, cause: error);
  }
}

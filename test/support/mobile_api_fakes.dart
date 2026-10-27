import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scripted Mobile API reply.
class FakeReply {
  const new(this.status, [this.body]);

  final int status;
  final Object? body;

  /// A reply that never arrives unless the request is cancelled.
  static const FakeReply hang = FakeReply(-1);
}

/// Fake Mobile API server behind a real [Dio] pipeline (status validation,
/// JSON transformer, cancellation). Routes by `METHOD path` below the API base.
class FakeMobileApiServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final _routes = <String, FutureOr<FakeReply> Function(RequestOptions)>{};

  void on(
    String route,
    FutureOr<FakeReply> Function(RequestOptions request) reply,
  ) => _routes[route] = reply;

  List<RequestOptions> called(String route) => [
    for (final request in requests)
      if (_route(request) == route) request,
  ];

  static String _route(RequestOptions request) {
    final path = request.uri.path;
    final index = path.indexOf('/api/orangeone/mobile/v1');
    final local = index < 0
        ? path
        : path.substring(index + '/api/orangeone/mobile/v1'.length);
    return '${request.method} $local';
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final route = _route(options);
    final handler = _routes[route];
    if (handler == null) {
      throw StateError('No fake route for $route');
    }
    final reply = await handler(options);
    if (identical(reply, FakeReply.hang)) {
      await (cancelFuture ?? Completer<void>().future);
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled',
      );
    }
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> requestBody(RequestOptions request) =>
    request.data as Map<String, dynamic>;

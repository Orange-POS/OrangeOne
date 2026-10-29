import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/api_configuration.dart';

/// The shared HTTP stack: flavor timeouts, JSON, no redirects.
final dioProvider = Provider<Dio>((ref) {
  final configuration = ref.watch(apiConfigurationProvider);
  final dio = Dio(
    BaseOptions(
      connectTimeout: configuration.connectTimeout,
      sendTimeout: configuration.connectTimeout,
      receiveTimeout: configuration.responseTimeout,
      contentType: Headers.jsonContentType,
      headers: {'Accept': Headers.jsonContentType},
      followRedirects: false,
      maxRedirects: 0,
    ),
  );
  // Deliberately no body/header logging or automatic request retries.
  ref.onDispose(() => dio.close(force: true));
  return dio;
}, name: 'dioProvider');

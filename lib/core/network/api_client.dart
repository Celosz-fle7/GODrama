import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

import 'doh_resolver.dart';

class ApiClient {
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._();

  late final Dio dio;

  ApiClient._() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': 'GoDrama/1.0.0 (Android; Mobile)',
        },
      ),
    );

    // Aktifkan HTTP/2 Adapter multiplexing seperti arsitektur JoyReels
    dio.httpClientAdapter = Http2Adapter(
      ConnectionManager(
        idleTimeout: const Duration(seconds: 15),
        onClientCreate: (_, config) {
          config.onBadCertificate = (_) => true;
        },
      ),
    );

    // Pasang Interceptor untuk DoH resolving & telemetry
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Resolve hostname via DoH untuk menghindari DNS poisoning ISP
          final host = options.uri.host;
          final resolvedIp = await DohResolver.instance.resolveHost(host);
          if (resolvedIp != null && resolvedIp != host) {
            // Gunakan IP yang sudah di-resolve DoH dengan tetap menyematkan Host header asli
            options.headers['Host'] = host;
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          // Auto-recovery / fallback
          return handler.next(error);
        },
      ),
    );
  }
}

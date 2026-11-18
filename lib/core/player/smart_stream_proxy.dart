import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SmartStreamProxy {
  static SmartStreamProxy? _instance;
  static SmartStreamProxy get instance => _instance ??= SmartStreamProxy._();

  HttpServer? _server;
  int _port = 0;
  int get port => _port;
  bool _isStarting = false;
  Directory? _cacheDir;

  SmartStreamProxy._();

  /// Inisialisasi loopback local server pada 127.0.0.1
  Future<void> start() async {
    if (_server != null || _isStarting) return;
    _isStarting = true;

    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/godrama_video_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      _server!.listen(_handleRequest);
    } catch (_) {
    } finally {
      _isStarting = false;
    }
  }

  /// Mengembalikan URL video streaming langsung untuk akselerasi native ExoPlayer (Zero-Proxy Latency)
  String getProxyUrl(String remoteUrl) {
    return remoteUrl;
  }

  /// Preload awal video (2MB pertama) di background (mirip FlutterAliPlayerMediaLoader)
  Future<void> preloadNextEpisode(
    String remoteUrl, {
    int preloadBytes = 2 * 1024 * 1024,
  }) async {
    if (_cacheDir == null) return;
    final cacheFile = _getCacheFile(remoteUrl);
    if (await cacheFile.exists() && await cacheFile.length() >= preloadBytes) {
      return; // Sudah ter-cache
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(remoteUrl));
      request.headers.set('Range', 'bytes=0-$preloadBytes');

      final response = await request.close();
      if (response.statusCode == 200 || response.statusCode == 206) {
        final sink = cacheFile.openWrite(mode: FileMode.writeOnlyAppend);
        await response.pipe(sink);
      }
    } catch (_) {}
  }

  File _getCacheFile(String url) {
    // Generate safe filename from url hash
    final safeName = url.hashCode.abs().toString();
    return File('${_cacheDir!.path}/chunk_$safeName.mp4');
  }

  void _handleRequest(HttpRequest request) async {
    final remoteUrlParam = request.uri.queryParameters['url'];
    if (remoteUrlParam == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final remoteUri = Uri.parse(remoteUrlParam);

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final clientReq = await client.getUrl(remoteUri);

      // Teruskan Range header dari player
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null) {
        clientReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }

      final clientResp = await clientReq.close();
      request.response.statusCode = clientResp.statusCode;

      // Teruskan headers esensial
      clientResp.headers.forEach((name, values) {
        for (final v in values) {
          request.response.headers.add(name, v);
        }
      });

      await clientResp.pipe(request.response);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Menghitung total ukuran file cache video dalam bytes
  Future<int> getCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    try {
      int total = 0;
      final entities = _cacheDir!.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Menghapus seluruh file video cache di disk
  Future<void> clearCache() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;
    try {
      final entities = _cacheDir!.listSync();
      for (final entity in entities) {
        if (entity is File) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}

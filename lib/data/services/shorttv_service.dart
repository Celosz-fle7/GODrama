import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/drama_model.dart';

class ShortTvService {
  static ShortTvService? _instance;
  static ShortTvService get instance => _instance ??= ShortTvService._();

  ShortTvService._() {
    _ensureDeviceId();
  }

  static const String _baseUrl = 'https://api4sg.aoneroom.com';
  static final List<int> _gatewaySecret = base64.decode(
    '76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O',
  );
  static const String _userAgent =
      'com.community.oneroom/50020132 (Linux; U; Android 16; id_ID; Infinix X6870; Build/BP2A.250605.031.A3; Cronet/155.0.8059.16)';

  String _deviceId = '';
  String? _token;
  bool _isHandshaking = false;

  void _ensureDeviceId() {
    if (_deviceId.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
      _deviceId = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
  }

  /// Format path dan query string sesuai spesifikasi kanonis MovieBox / ShortTV:
  /// Query string wajib di-sort alfabetis berdasarkan key tanpa merusak nilai raw parameter.
  String _formatPathQuery(String pathWithQuery) {
    final parts = pathWithQuery.split('?');
    final path = parts[0];
    final query = parts.length > 1 ? parts[1] : '';
    if (query.isEmpty) return path;

    final pairs = <MapEntry<String, String>>[];
    for (final part in query.split('&')) {
      if (part.contains('=')) {
        final eqIdx = part.indexOf('=');
        final k = part.substring(0, eqIdx);
        final v = part.substring(eqIdx + 1);
        pairs.add(MapEntry(k, v));
      } else if (part.isNotEmpty) {
        pairs.add(MapEntry(part, ''));
      }
    }
    pairs.sort((a, b) => a.key.compareTo(b.key));
    final sorted = pairs
        .where((e) => e.key.isNotEmpty)
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return sorted.isNotEmpty ? '$path?$sorted' : path;
  }

  String _generateSignature(
    String method,
    String pathWithQuery, {
    String body = '',
    String accept = '*/*',
    String contentType = '',
    required String ts,
  }) {
    final cl = body.isNotEmpty ? utf8.encode(body).length.toString() : '';
    final bodyMd5 = body.isNotEmpty
        ? md5
              .convert(
                utf8.encode(
                  body.length > 102400 ? body.substring(0, 102400) : body,
                ),
              )
              .toString()
        : '';
    final formattedPath = _formatPathQuery(pathWithQuery);

    final lines = [
      method.toUpperCase(),
      accept,
      contentType,
      cl,
      ts,
      bodyMd5,
      formattedPath,
    ];
    final toSign = lines.join('\n');
    final hmac = Hmac(md5, _gatewaySecret);
    final digest = hmac.convert(utf8.encode(toSign));
    final sig = base64.encode(digest.bytes);
    return '$ts|2|$sig';
  }

  Future<void> _handshake() async {
    if (_isHandshaking) return;
    _isHandshaking = true;
    _ensureDeviceId();

    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final sig = _generateSignature(
        'GET',
        '/wefeed-mobile-bff/app/config',
        ts: ts,
      );
      final revTsMd5 = md5
          .convert(utf8.encode(ts.split('').reversed.join('')))
          .toString();

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse('$_baseUrl/wefeed-mobile-bff/app/config'),
      );

      request.headers.set('User-Agent', _userAgent);
      request.headers.set('accept', '*/*');
      request.headers.set('x-tr-signature', sig);
      request.headers.set('x-tr-timestamp', ts);
      request.headers.set('X-Client-Token', '$ts,$revTsMd5');
      request.headers.set('X-Client-Status', '1');
      request.headers.set('X-Client-Language', 'id');
      request.headers.set('X-Client-DeviceId', _deviceId);
      request.headers.set(
        'X-Client-Info',
        jsonEncode({
          'device_id': _deviceId,
          'package': 'com.community.oneroom',
          'region': 'ID',
          'language': 'in',
          'model': 'Infinix X6870',
          'X-Play-Mode': '2',
        }),
      );

      final response = await request.close();
      final xUser = response.headers.value('x-user');
      if (xUser != null && xUser.isNotEmpty) {
        try {
          final userMap = jsonDecode(xUser);
          if (userMap is Map<String, dynamic> && userMap['token'] != null) {
            _token = userMap['token'].toString();
          }
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _isHandshaking = false;
    }
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String pathWithQuery, {
    Map<String, dynamic>? bodyJson,
  }) async {
    if (_token == null && !_isHandshaking) {
      await _handshake();
    }

    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final bodyStr = bodyJson != null ? jsonEncode(bodyJson) : '';
    final contentType = bodyJson != null ? 'application/json' : '';
    final sig = _generateSignature(
      method,
      pathWithQuery,
      body: bodyStr,
      contentType: contentType,
      ts: ts,
    );

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      final uri = Uri.parse('$_baseUrl$pathWithQuery');
      final request = await (method == 'POST'
          ? client.postUrl(uri)
          : client.getUrl(uri));

      request.headers.set('User-Agent', _userAgent);
      request.headers.set('accept', '*/*');
      request.headers.set('x-tr-signature', sig);
      request.headers.set('x-tr-timestamp', ts);
      request.headers.set('X-Client-Status', '1');
      request.headers.set('X-Client-Language', 'id');
      request.headers.set('X-Client-DeviceId', _deviceId);
      request.headers.set(
        'X-Client-Info',
        jsonEncode({
          'device_id': _deviceId,
          'package': 'com.community.oneroom',
          'region': 'ID',
          'language': 'in',
          'model': 'Infinix X6870',
          'X-Play-Mode': '2',
        }),
      );

      if (contentType.isNotEmpty) {
        request.headers.set('content-type', contentType);
      }

      if (_token != null && _token!.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $_token');
      } else {
        final revTsMd5 = md5
            .convert(utf8.encode(ts.split('').reversed.join('')))
            .toString();
        request.headers.set('X-Client-Token', '$ts,$revTsMd5');
      }

      if (bodyStr.isNotEmpty) {
        request.add(utf8.encode(bodyStr));
      }

      final response = await request.close();

      // Tangkap pembaruan token dari x-user jika ada
      final xUser = response.headers.value('x-user');
      if (xUser != null && xUser.isNotEmpty) {
        try {
          final userMap = jsonDecode(xUser);
          if (userMap is Map<String, dynamic> && userMap['token'] != null) {
            _token = userMap['token'].toString();
          }
        } catch (_) {}
      }

      if (response.statusCode == 200) {
        final respBody = await response.transform(utf8.decoder).join();
        return jsonDecode(respBody) as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        _token = null;
        await _handshake();
      }
    } catch (_) {}

    return null;
  }

  /// Ambil Tangga Algoritma Resmi ShortTV untuk audiens Indonesia:
  /// Urutan mutlak server: Sedang Trending -> Sulih Suara Indonesia (Hot) -> Terbaru.
  Future<List<DramaModel>> fetchForYouAlgorithm() async {
    final list = <DramaModel>[];
    final seen = <String>{};

    // 1. Ambil tangga operasional Tab 13 (Sedang Trending & Sulih Suara terhangat hari ini)
    try {
      final tabResp = await _request(
        'GET',
        '/wefeed-mobile-bff/tab-operating?tabId=13',
      );
      if (tabResp != null &&
          tabResp['code'] == 0 &&
          tabResp['data'] is Map<String, dynamic>) {
        final sections = tabResp['data']['items'] as List?;
        if (sections != null) {
          for (final sec in sections) {
            if (sec is! Map<String, dynamic>) continue;
            final subjects = sec['subjects'] ?? sec['items'];
            if (subjects is List) {
              for (final sub in subjects) {
                if (sub is Map<String, dynamic>) {
                  final model = _mapToDramaModel(sub);
                  if (model.id.isNotEmpty && seen.add(model.id)) {
                    list.add(model);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Ambil katalog kurasi Sulih Suara Indonesia (Hot)
    try {
      final indoDramas = await fetchShortTvDramas(
        page: 1,
        perPage: 20,
        classify: 'Sulih suara Indonesia',
        sort: 'Hot',
      );
      for (final d in indoDramas) {
        if (seen.add(d.id)) {
          list.add(d);
        }
      }
    } catch (_) {}

    // 3. Fallback jika kosong: ambil ShortTV general
    if (list.isEmpty) {
      list.addAll(await fetchShortTvDramas(page: 1, perPage: 20));
    }

    return list;
  }

  /// Ambil daftar drama ShortTV vertikal resmi (subjectType: 7) dengan filter taksonomi
  Future<List<DramaModel>> fetchShortTvDramas({
    int page = 1,
    int perPage = 20,
    String? classify,
    String? sort = 'Hot',
  }) async {
    final payload = <String, dynamic>{
      'page': page,
      'perPage': perPage,
      'subjectType': 7, // 7 = ShortTV Micro-Drama
    };
    if (classify != null && classify.isNotEmpty) {
      payload['classify'] = classify;
    }
    if (sort != null && sort.isNotEmpty) {
      payload['sort'] = sort;
    }

    final resp = await _request(
      'POST',
      '/wefeed-mobile-bff/subject-api/search',
      bodyJson: payload,
    );

    if (resp != null &&
        resp['code'] == 0 &&
        resp['data'] is Map<String, dynamic>) {
      final items = resp['data']['items'] as List?;
      if (items != null) {
        return items
            .whereType<Map<String, dynamic>>()
            .map(_mapToDramaModel)
            .where((d) => d.id.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  Map<String, List<DramaModel>>? _cachedSections;

  /// Mengambil seksi operasional tab ShortTV (tabId=13 untuk ShortTV/Sulih Suara Indonesia)
  Future<Map<String, List<DramaModel>>> fetchOperatingSections({
    int tabId = 13,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedSections != null && _cachedSections!.isNotEmpty) {
      return _cachedSections!;
    }

    final sectionsMap = <String, List<DramaModel>>{};
    final resp =
        await _request('GET', '/wefeed-mobile-bff/tab-operating?tabId=$tabId');
    if (resp != null &&
        resp['code'] == 0 &&
        resp['data'] is Map<String, dynamic>) {
      final items = resp['data']['items'] as List?;
      if (items != null) {
        for (final sec in items) {
          if (sec is! Map<String, dynamic>) continue;
          final title = sec['title']?.toString().trim() ?? '';
          final subjects = sec['subjects'] ?? sec['items'];
          if (subjects is List && subjects.isNotEmpty) {
            final dramas = subjects
                .whereType<Map<String, dynamic>>()
                .map(_mapToDramaModel)
                .where((d) => d.id.isNotEmpty)
                .toList();
            if (dramas.isNotEmpty && title.isNotEmpty) {
              sectionsMap[title] = dramas;
            }
          }
        }
      }
    }
    if (sectionsMap.isNotEmpty) {
      _cachedSections = sectionsMap;
    }
    return sectionsMap;
  }

  /// Mengambil katalog drama Beranda untuk 3 tab murni (tanpa sub-filter):
  /// 1. 'sulih_suara': Gudang penuh drama sulih suara / dubbing Indonesia (ratusan judul)
  /// 2. 'versi_sub': Drama versi subtitle / audio asli teks Indonesia
  /// 3. 'global': Tembak gudang campur seluruh drama global dari semua genre
  Future<List<DramaModel>> getBerandaDramas({
    required String tab,
    bool forceRefresh = false,
  }) async {
    final sections = await fetchOperatingSections(
      tabId: 13,
      forceRefresh: forceRefresh,
    );

    final seen = <String>{};
    final list = <DramaModel>[];

    if (tab == 'sulih_suara') {
      // 1. Seksi prioritas Sulih Suara & Lokal
      final dub = sections['🎧Drama Dubbing'] ?? [];
      final lokal = sections['🇮🇩Lokal Short TV '] ?? [];
      for (final d in [...dub, ...lokal]) {
        if (seen.add(d.id)) list.add(d);
      }

      // 2. Tambah dari semua seksi lain yang berjudul/berdeskripsi Sulih Suara / Dubbing
      for (final dramaList in sections.values) {
        for (final d in dramaList) {
          final t = d.title.toLowerCase();
          final desc = d.description.toLowerCase();
          if (t.contains('sulih suara') ||
              t.contains('dubbing') ||
              desc.contains('sulih suara') ||
              desc.contains('dubbing')) {
            if (seen.add(d.id)) list.add(d);
          }
        }
      }

      // 3. Tarik pencarian keyword 'Sulih Suara' dan 'Dubbing' untuk memperkaya hingga ratusan judul
      try {
        final dub1 = await searchShortTv('Sulih Suara', perPage: 20);
        for (final d in dub1) {
          if (seen.add(d.id)) list.add(d);
        }
        final dub2 = await searchShortTv('Dubbing', perPage: 20);
        for (final d in dub2) {
          if (seen.add(d.id)) list.add(d);
        }
      } catch (_) {}

      // Jika masih sedikit, sertakan seksi trending
      if (list.length < 20) {
        final trending = sections['🔥Sedang Trending'] ?? [];
        for (final d in trending) {
          if (seen.add(d.id)) list.add(d);
        }
      }
      return list;
    } else if (tab == 'versi_sub') {
      // Drama versi subtitle (teks Indonesia / audio asli)
      for (final entry in sections.entries) {
        if (entry.key.contains('Dubbing') || entry.key.contains('Lokal')) {
          continue;
        }
        for (final d in entry.value) {
          final t = d.title.toLowerCase();
          if (!t.contains('sulih suara') && !t.contains('dubbing')) {
            if (seen.add(d.id)) list.add(d);
          }
        }
      }
      return list;
    } else {
      // 'global': Tembak gudang campur seluruh drama dari semua seksi operasional tanpa filter
      for (final dramaList in sections.values) {
        for (final d in dramaList) {
          if (seen.add(d.id)) list.add(d);
        }
      }
      return list;
    }
  }

  /// Ambil daftar episode dan stream URL langsung dari ShortTV API:
  /// Menggunakan batch chunking (10 item/chunk) karena gateway membatasi rentang request <= 15 (PARAMS_ERROR: exceed limit)
  Future<List<EpisodeModel>> fetchShortTvEpisodes(
    String subjectId, {
    int startPos = 0,
    int endPosition = 20,
  }) async {
    final chunks = <Future<List<EpisodeModel>>>[];
    int cur = startPos;
    final limit = endPosition < startPos ? startPos + 10 : endPosition;
    while (cur < limit) {
      final chunkStart = cur;
      final chunkEnd = (cur + 10 <= limit) ? cur + 10 : limit;
      chunks.add(_fetchSingleChunk(subjectId, chunkStart, chunkEnd));
      cur = chunkEnd + 1;
    }

    final results = await Future.wait(chunks);
    final all = <EpisodeModel>[];
    for (final r in results) {
      all.addAll(r);
    }
    return all;
  }

  Future<List<EpisodeModel>> _fetchSingleChunk(
    String subjectId,
    int startPos,
    int endPosition,
  ) async {
    final path =
        '/wefeed-mobile-bff/shorts/mini-list?endPosition=$endPosition&pagerMode=1&startPosition=$startPos&subjectId=$subjectId';

    final resp = await _request('GET', path);
    if (resp != null &&
        resp['code'] == 0 &&
        resp['data'] is Map<String, dynamic>) {
      final items = resp['data']['items'] as List?;
      if (items != null) {
        return items
            .whereType<Map<String, dynamic>>()
            .map((it) {
              final epNum = (it['ep'] as num?)?.toInt() ?? 1;
              final vidObj = it['video'] as Map<String, dynamic>?;
              final addrObj = vidObj?['videoAddress'] as Map<String, dynamic>?;
              final streamUrl = addrObj?['url']?.toString() ?? '';

              // Ekstraksi seluruh pilihan resolusi (1080p, 720p, 480p)
              final resMap = <String, String>{};
              final addrList = vidObj?['addressList'] as List?;
              if (addrList != null) {
                for (final a in addrList) {
                  final r = a['resolution']?.toString() ?? '720';
                  final u = a['url']?.toString() ?? '';
                  if (u.isNotEmpty) {
                    resMap['${r}p'] = u;
                  }
                }
              }
              if (resMap.isEmpty && streamUrl.isNotEmpty) {
                final defaultRes = addrObj?['resolution']?.toString() ?? '720';
                resMap['${defaultRes}p'] = streamUrl;
              }

              return EpisodeModel(
                id: it['miniId']?.toString() ?? '${subjectId}_$epNum',
                episodeNumber: epNum,
                title: 'Episode $epNum',
                videoUrl: streamUrl,
                durationSeconds: (addrObj?['duration'] as num?)?.toInt() ?? 90,
                isUnlocked: true,
                resolutions: resMap,
              );
            })
            .where((ep) => ep.videoUrl.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  /// Cari drama ShortTV
  Future<List<DramaModel>> searchShortTv(
    String keyword, {
    int page = 1,
    int perPage = 10,
  }) async {
    final payload = {'keyword': keyword, 'page': page, 'perPage': perPage};

    final resp = await _request(
      'POST',
      '/wefeed-mobile-bff/subject-api/search',
      bodyJson: payload,
    );
    if (resp != null &&
        resp['code'] == 0 &&
        resp['data'] is Map<String, dynamic>) {
      final items = resp['data']['items'] as List?;
      if (items != null) {
        return items
            .whereType<Map<String, dynamic>>()
            .where(
              (it) =>
                  it['subjectType'] == 7 ||
                  it['genre']?.toString().toLowerCase().contains('short') ==
                      true,
            )
            .map(_mapToDramaModel)
            .toList();
      }
    }
    return [];
  }

  String _extractImageUrl(dynamic imgObj) {
    if (imgObj == null) return '';
    if (imgObj is String) return imgObj;
    if (imgObj is Map) {
      if (imgObj['url'] != null) return imgObj['url'].toString();
      if (imgObj['uri'] != null) return imgObj['uri'].toString();
      if (imgObj['cover'] != null) return _extractImageUrl(imgObj['cover']);
    }
    return '';
  }

  DramaModel _mapToDramaModel(Map<String, dynamic> json) {
    final subjectId =
        json['subjectId']?.toString() ??
        json['id']?.toString() ??
        json['miniId']?.toString() ??
        '';
    final title = json['title']?.toString() ?? 'Short Drama';
    final desc =
        json['description']?.toString() ??
        json['brief']?.toString() ??
        'Drama pendek populer ber-subtitle dan bersulih suara Indonesia.';
    final cover = _extractImageUrl(json['cover']);
    final banner = _extractImageUrl(json['banner']).isNotEmpty
        ? _extractImageUrl(json['banner'])
        : cover;
    final totalEpisodes =
        (json['totalEpisodes'] as num?)?.toInt() ??
        (json['episodesCount'] as num?)?.toInt() ??
        (json['episodeCount'] as num?)?.toInt() ??
        50;

    final tags = <String>[];
    if (json['genre'] != null) tags.add(json['genre'].toString());
    if (json['classify'] != null) tags.add(json['classify'].toString());
    if (tags.isEmpty) tags.addAll(['Trending', 'Sulih Suara', 'Romansa']);

    final viewCountNum =
        (json['viewCount'] as num?)?.toInt() ??
        (json['playCount'] as num?)?.toInt() ??
        Random().nextInt(80000) + 12000;
    final viewCountStr = viewCountNum > 1000
        ? '${(viewCountNum / 1000).toStringAsFixed(1)}K'
        : '$viewCountNum';

    final rating =
        ((json['rating'] as num?)?.toDouble() ??
                (4.5 + Random().nextDouble() * 0.4))
            .clamp(4.0, 5.0);

    return DramaModel(
      id: subjectId,
      title: title,
      coverUrl: cover,
      bannerUrl: banner,
      description: desc,
      tags: tags,
      totalEpisodes: totalEpisodes,
      viewCount: viewCountStr,
      rating: double.parse(rating.toStringAsFixed(1)),
      isTrending: true,
      episodes: const [],
    );
  }
}

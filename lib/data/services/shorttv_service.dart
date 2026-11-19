import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Satu HttpClient bersama untuk semua request (connection reuse /
  // keep-alive), bukan HttpClient baru per request.
  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 15);

  String _deviceId = '';
  String? _token;
  bool _isHandshaking = false;
  Completer<void>? _handshakeCompleter;

  void _ensureDeviceId() {
    if (_deviceId.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
      _deviceId = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
  }

  /// DeviceId persisten per instalasi: pakai yang tersimpan bila ada,
  /// kalau belum ada simpan yang sudah dibuat. Dipanggil di awal handshake,
  /// sebelum request apa pun memakai ID ini.
  Future<void> _loadPersistedDeviceId() async {
    _ensureDeviceId();
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('godrama_device_id');
      if (stored != null && stored.isNotEmpty) {
        _deviceId = stored;
      } else {
        await prefs.setString('godrama_device_id', _deviceId);
      }
    } catch (e) {
      debugPrint('[ShortTvService] Gagal baca/simpan deviceId: $e');
    }
  }

  Future<void> _ensureToken() async {
    if (_token != null && _token!.isNotEmpty) return;
    if (_handshakeCompleter != null) {
      await _handshakeCompleter!.future;
      return;
    }
    _handshakeCompleter = Completer<void>();
    try {
      await _handshake();
    } finally {
      _handshakeCompleter?.complete();
      _handshakeCompleter = null;
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
    await _loadPersistedDeviceId();

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

      final request = await _httpClient.getUrl(
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
        } catch (e) {
          debugPrint('[ShortTvService] Gagal parse token handshake: $e');
        }
      }
    } catch (e) {
      debugPrint('[ShortTvService] Handshake gagal: $e');
    } finally {
      _isHandshaking = false;
    }
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String pathWithQuery, {
    Map<String, dynamic>? bodyJson,
    bool isRetry = false,
  }) async {
    await _ensureToken();

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
      final uri = Uri.parse('$_baseUrl$pathWithQuery');
      final request = await (method == 'POST'
          ? _httpClient.postUrl(uri)
          : _httpClient.getUrl(uri));

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
        final bodyBytes = utf8.encode(bodyStr);
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
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
        } catch (e) {
          debugPrint('[ShortTvService] Gagal parse token x-user: $e');
        }
      }

      if (response.statusCode == 200) {
        final respBody = await response.transform(utf8.decoder).join();
        return jsonDecode(respBody) as Map<String, dynamic>;
      } else {
        final errBody = await response.transform(utf8.decoder).join();
        debugPrint(
            '[ShortTvService] HTTP ${response.statusCode} for $pathWithQuery: $errBody');
        if ((response.statusCode == 401 || response.statusCode == 441) &&
            !isRetry) {
          _token = null;
          await _ensureToken();
          return await _request(
            method,
            pathWithQuery,
            bodyJson: bodyJson,
            isRetry: true,
          );
        }
      }
    } catch (e) {
      debugPrint('[ShortTvService] Request gagal ($method $pathWithQuery): $e');
    }

    return null;
  }

  /// Pencarian yang tidak pernah throw: gagal jaringan = daftar kosong.
  /// Dipakai di dalam Future.wait agar satu request gagal tidak
  /// menggagalkan seluruh halaman.
  Future<List<DramaModel>> _safeSearch(
    String keyword, {
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      return await searchShortTv(keyword, page: page, perPage: perPage);
    } catch (e) {
      debugPrint('[ShortTvService] Search "$keyword" p$page gagal: $e');
      return [];
    }
  }

  Future<Map<String, List<DramaModel>>> _safeSections({
    int tabId = 13,
    bool forceRefresh = false,
  }) async {
    try {
      return await fetchOperatingSections(
        tabId: tabId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[ShortTvService] Sections tab $tabId gagal: $e');
      return {};
    }
  }

  /// Interleave 1:1 dua pool (sulih suara / dubbing).
  List<DramaModel> _interleave(
    List<DramaModel> a,
    List<DramaModel> b,
  ) {
    final out = <DramaModel>[];
    final maxLen = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < maxLen; i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    return out;
  }

  /// For You per halaman (mix rotasi sulih suara / dubbing, interleave 1:1).
  /// Semua request dalam satu halaman jalan PARALEL (Future.wait), bukan
  /// sekuensial — halaman 1 hanya butuh ~1x waktu request, bukan 13x.
  /// Halaman 1 = seksi + sulih p1 + dubbing p1; halaman 2-3 = halaman
  /// pencarian berikutnya + varian keyword. Di luar itu kosong.
  /// Dedup antar halaman dilakukan pemanggil (layar menyimpan seen-set).
  Future<List<DramaModel>> fetchForYouPage(int page) async {
    if (page < 1) return [];
    if (page == 1) {
      final (sections, sulih, dub) = await (
        _safeSections(tabId: 13, forceRefresh: true),
        _safeSearch('sulih suara', page: 1),
        _safeSearch('dubbing', page: 1),
      ).wait;
      final sulihPool = <DramaModel>[
        ...sections['🇮🇩Lokal Short TV '] ?? [],
        ...sulih,
      ];
      final dubPool = <DramaModel>[
        ...sections['🎧Drama Dubbing'] ?? [],
        ...dub,
      ];
      return _interleave(_dedupe(sulihPool), _dedupe(dubPool));
    }
    if (page == 2) {
      final (sulih2, dub2, sulihVar, dubVar) = await (
        _safeSearch('sulih suara', page: 2),
        _safeSearch('dubbing', page: 2),
        _safeSearch('sulih suara indonesia', page: 1),
        _safeSearch('dubbing indo', page: 1),
      ).wait;
      final sulihPool = <DramaModel>[...sulih2, ...sulihVar];
      final dubPool = <DramaModel>[...dub2, ...dubVar];
      return _interleave(_dedupe(sulihPool), _dedupe(dubPool));
    }
    if (page == 3) {
      final (sulih3, dub3, sulihV, suaraV, dubInd, dubV) = await (
        _safeSearch('sulih suara', page: 3),
        _safeSearch('dubbing', page: 3),
        _safeSearch('sulih', page: 1),
        _safeSearch('suara', page: 1),
        _safeSearch('dubbing indonesia', page: 1),
        _safeSearch('dub', page: 1),
      ).wait;
      final sulihPool = <DramaModel>[...sulih3, ...sulihV, ...suaraV];
      final dubPool = <DramaModel>[...dub3, ...dubInd, ...dubV];
      return _interleave(_dedupe(sulihPool), _dedupe(dubPool));
    }
    return [];
  }

  List<DramaModel> _dedupe(List<DramaModel> input) {
    final seen = <String>{};
    return input.where((d) => d.id.isNotEmpty && seen.add(d.id)).toList();
  }

  // Cache seksi per tabId dengan TTL — sebelumnya satu cache tanpa TTL
  // yang mengabaikan tabId (cache tab 13 dipakai untuk tab lain).
  static const _sectionsTtl = Duration(minutes: 10);
  final Map<int, _SectionsCacheEntry> _sectionsCache = {};

  /// Mengambil seksi operasional tab ShortTV (tabId=13 untuk ShortTV/Sulih Suara Indonesia)
  Future<Map<String, List<DramaModel>>> fetchOperatingSections({
    int tabId = 13,
    bool forceRefresh = false,
  }) async {
    final cached = _sectionsCache[tabId];
    if (!forceRefresh &&
        cached != null &&
        cached.sections.isNotEmpty &&
        DateTime.now().difference(cached.fetchedAt) < _sectionsTtl) {
      return cached.sections;
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
      _sectionsCache[tabId] = _SectionsCacheEntry(
        sections: sectionsMap,
        fetchedAt: DateTime.now(),
      );
    }
    return sectionsMap;
  }

  /// Katalog drama Beranda per halaman, untuk 4 tab:
  /// 1. 'untuk_anda': seksi sulih suara + pencarian "sulih suara"
  /// 2. 'terbaru': seksi terbaru + pencarian "dubbing"
  /// 3. 'terpanas': seksi trending + pencarian "versi dub"
  /// 4. 'peringkat': semua seksi (diiris per halaman, tanpa request tambahan)
  /// Halaman 1 memuat seksi + halaman pencarian pertama + varian keyword
  /// (paralel); halaman 2-3 memuat halaman pencarian berikutnya.
  /// Dedup antar halaman dilakukan pemanggil.
  Future<List<DramaModel>> getBerandaDramasPage({
    required String tab,
    required int page,
    bool forceRefresh = false,
  }) async {
    if (page < 1) return [];

    if (tab == 'untuk_anda') {
      if (page == 1) {
        final (sections, sulih, sulihId, sulihV, suaraV) = await (
          _safeSections(tabId: 13, forceRefresh: forceRefresh),
          _safeSearch('sulih suara', page: 1),
          _safeSearch('sulih suara indonesia', page: 1),
          _safeSearch('sulih', page: 1),
          _safeSearch('suara', page: 1),
        ).wait;
        return _dedupe([
          ...sections['🎧Drama Dubbing'] ?? [],
          ...sections['🇮🇩Lokal Short TV '] ?? [],
          ...sulih,
          ...sulihId,
          ...sulihV,
          ...suaraV,
        ]);
      }
      if (page <= 3) return _safeSearch('sulih suara', page: page);
      return [];
    }

    if (tab == 'terbaru') {
      if (page == 1) {
        final (sections, dub, dubIndo, dubId, dubV) = await (
          _safeSections(tabId: 13, forceRefresh: forceRefresh),
          _safeSearch('dubbing', page: 1),
          _safeSearch('dubbing indo', page: 1),
          _safeSearch('dubbing indonesia', page: 1),
          _safeSearch('dub', page: 1),
        ).wait;
        return _dedupe([
          ...sections['🎉Terbaru'] ?? [],
          ...dub,
          ...dubIndo,
          ...dubId,
          ...dubV,
        ]);
      }
      if (page <= 3) return _safeSearch('dubbing', page: page);
      return [];
    }

    if (tab == 'terpanas') {
      if (page == 1) {
        final (sections, versiDub, indonesian) = await (
          _safeSections(tabId: 13, forceRefresh: forceRefresh),
          _safeSearch('versi dub', page: 1),
          _safeSearch('indonesian', page: 1),
        ).wait;
        return _dedupe([
          ...sections['🔥Sedang Trending'] ?? [],
          ...versiDub,
          ...indonesian,
        ]);
      }
      if (page <= 3) {
        final (versiDub, indonesian) = await (
          _safeSearch('versi dub', page: page),
          _safeSearch('indonesian', page: page),
        ).wait;
        return _dedupe([...versiDub, ...indonesian]);
      }
      return [];
    }

    // 'peringkat': semua seksi digabung, diiris 30 item per halaman.
    // Seksi di-cache (TTL 10 menit), jadi halaman 2+ tanpa request baru.
    final sections = await _safeSections(
      tabId: 13,
      forceRefresh: forceRefresh,
    );
    final all = _dedupe(sections.values.expand((l) => l).toList());
    const pageSize = 30;
    final start = (page - 1) * pageSize;
    if (start >= all.length) return [];
    final end = (start + pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  /// Ambil daftar episode dan stream URL langsung dari ShortTV API.
  /// Chunk 10 episode, diambil per gelombang 3 chunk PARALEL (bukan satu
  /// per satu). Berhenti di chunk pertama yang pendek/kosong — itu tanda
  /// sudah sampai episode terakhir di server. Pemanggil yang butuh cepat
  /// (player) cukup minta chunk pertama (endPosition 10), lalu minta
  /// sisanya di latar belakang setelah video mulai main.
  Future<List<EpisodeModel>> fetchShortTvEpisodes(
    String subjectId, {
    int startPos = 1,
    int endPosition = 100,
  }) async {
    final actualStart = startPos <= 0 ? 1 : startPos;
    final actualEnd =
        endPosition < actualStart ? actualStart + 20 : endPosition;

    final all = <EpisodeModel>[];
    int cur = actualStart;
    while (cur <= actualEnd) {
      // Satu gelombang: sampai 3 chunk sekaligus.
      final ranges = <(int, int)>[];
      for (int i = 0; i < 3 && cur <= actualEnd; i++) {
        final chunkEnd = (cur + 9 <= actualEnd) ? cur + 9 : actualEnd;
        ranges.add((cur, chunkEnd));
        cur = chunkEnd + 1;
      }
      final chunks = await Future.wait(
        ranges.map((r) => _fetchSingleChunk(subjectId, r.$1, r.$2)),
      );
      var reachedEnd = false;
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final expected = ranges[i].$2 - ranges[i].$1 + 1;
        if (chunk.isEmpty) {
          reachedEnd = true;
          break;
        }
        all.addAll(chunk);
        if (chunk.length < expected) {
          reachedEnd = true;
          break;
        }
      }
      if (reachedEnd) break;
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
    // Tanpa deskripsi dari server, kosongkan — jangan karang deskripsi.
    final desc =
        json['description']?.toString() ?? json['brief']?.toString() ?? '';
    final cover = _extractImageUrl(json['cover']);
    final banner = _extractImageUrl(json['banner']).isNotEmpty
        ? _extractImageUrl(json['banner'])
        : cover;
    // 0 = server tidak memberi jumlah episode (angka riil didapat saat
    // daftar episode di-fetch). Jangan default 50.
    final totalEpisodes =
        (json['totalEpisodes'] as num?)?.toInt() ??
        (json['episodesCount'] as num?)?.toInt() ??
        (json['episodeCount'] as num?)?.toInt() ??
        0;

    final tags = <String>[];
    if (json['genre'] != null) tags.add(json['genre'].toString());
    if (json['classify'] != null) tags.add(json['classify'].toString());

    // Tanpa angka penonton dari server, kosongkan — jangan acak.
    final viewCountNum = (json['viewCount'] as num?)?.toInt() ??
        (json['playCount'] as num?)?.toInt();
    final viewCountStr = viewCountNum == null
        ? ''
        : viewCountNum > 1000
            ? '${(viewCountNum / 1000).toStringAsFixed(1)}K'
            : '$viewCountNum';

    // Tanpa rating dari server, null — jangan acak 4.5-4.9.
    final rating = (json['rating'] as num?)?.toDouble();

    return DramaModel(
      id: subjectId,
      title: title,
      coverUrl: cover,
      bannerUrl: banner,
      description: desc,
      tags: tags,
      totalEpisodes: totalEpisodes,
      viewCount: viewCountStr,
      rating: rating == null
          ? null
          : double.parse(rating.clamp(0.0, 5.0).toStringAsFixed(1)),
      isTrending: false,
      episodes: const [],
    );
  }
}

/// Satu entri cache seksi: isi + kapan diambil (untuk TTL).
class _SectionsCacheEntry {
  final Map<String, List<DramaModel>> sections;
  final DateTime fetchedAt;

  const _SectionsCacheEntry({
    required this.sections,
    required this.fetchedAt,
  });
}

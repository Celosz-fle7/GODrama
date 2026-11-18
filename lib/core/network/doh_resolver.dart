import 'dart:async';
import 'dart:convert';
import 'dart:io';

class _DnsCacheEntry {
  final String ip;
  final DateTime expiresAt;

  _DnsCacheEntry({required this.ip, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class DohResolver {
  static DohResolver? _instance;
  static DohResolver get instance => _instance ??= DohResolver._();

  DohResolver._();

  final Map<String, _DnsCacheEntry> _ramCache = {};
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..badCertificateCallback = (cert, host, port) => true;

  /// DoH Server Endpoints (Cloudflare & Google DNS)
  static const String _cloudflareDoh = 'https://1.1.1.1/dns-query';
  static const String _googleDoh = 'https://dns.google/resolve';

  /// Resolve hostname ke IPv4 via DNS over HTTPS
  Future<String?> resolveHost(String host) async {
    // Jika input sudah berupa IP address, langsung kembalikan
    if (_isIpAddress(host)) return host;

    // Cek cache RAM
    final cached = _ramCache[host];
    if (cached != null && !cached.isExpired) {
      return cached.ip;
    }

    // Coba via Cloudflare DoH
    String? resolvedIp = await _queryDoh(_cloudflareDoh, host);

    // Fallback ke Google DoH jika Cloudflare gagal
    resolvedIp ??= await _queryDoh(_googleDoh, host);

    if (resolvedIp != null) {
      // Simpan di RAM cache selama 5 menit
      _ramCache[host] = _DnsCacheEntry(
        ip: resolvedIp,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      return resolvedIp;
    }

    // Fallback terakhir: native DNS
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isNotEmpty) {
        return addresses.first.address;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _queryDoh(String endpoint, String host) async {
    try {
      final uri = Uri.parse('$endpoint?name=$host&type=A');
      final request = await _client.getUrl(uri);
      request.headers.set('Accept', 'application/dns-json');

      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final answers = json['Answer'] as List?;
        if (answers != null && answers.isNotEmpty) {
          for (final ans in answers) {
            // Type 1 = DNS A Record (IPv4)
            if (ans['type'] == 1 && ans['data'] != null) {
              return ans['data'].toString();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isIpAddress(String host) {
    return RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  }
}

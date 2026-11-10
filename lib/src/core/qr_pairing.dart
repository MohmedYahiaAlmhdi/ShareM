import 'dart:io';

/// ShareM QR advertises a local endpoint; it is not cryptographic authentication.
/// Never put file permissions, session tokens, or Wi-Fi credentials in a QR.
class QrPeer {
  const QrPeer({required this.id, required this.name,
    required this.ip, required this.port});

  final String id;
  final String name;
  final String ip;
  final int port;

  String get endpoint => '$ip:$port';

  String encode() => Uri(
    scheme: 'sharem',
    host: 'pair',
    queryParameters: {
      'v': '1',
      'id': id,
      'name': name,
      'ip': ip,
      'port': '$port',
    },
  ).toString();

  static QrPeer? tryParse(String value) {
    if (value.length > 1024) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'sharem' || uri.host != 'pair' ||
        uri.path.isNotEmpty || uri.queryParameters['v'] != '1' ||
        uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) return null;
    const keys = {'v', 'id', 'name', 'ip', 'port'};
    if (uri.queryParameters.length != keys.length ||
        !uri.queryParameters.keys.toSet().containsAll(keys)) return null;
    final id = uri.queryParameters['id'] ?? '';
    final name = uri.queryParameters['name'] ?? '';
    final ip = uri.queryParameters['ip'] ?? '';
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        name.trim().isEmpty || name.length > 36 ||
        !isLocalIpv4(ip) || port == null || port < 1 || port > 65535) {
      return null;
    }
    return QrPeer(id: id, name: name, ip: ip, port: port);
  }

  static bool isLocalIpv4(String input) {
    final parsed = InternetAddress.tryParse(input);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return false;
    final b = parsed.rawAddress;
    return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254);
  }
}

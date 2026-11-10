import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/qr_pairing.dart';

void main() {
  test('QR payload round trip supports Arabic device names', () {
    const peer = QrPeer(
      id: '0123456789abcdef0123456789abcdef',
      name: 'هاتف محمد', ip: '192.168.49.1', port: 43887,
    );
    final parsed = QrPeer.tryParse(peer.encode());
    expect(parsed, isNotNull);
    expect(parsed!.name, 'هاتف محمد');
    expect(parsed.endpoint, '192.168.49.1:43887');
  });

  test('QR rejects public addresses, URLs and malformed payload', () {
    const valid = QrPeer(id: '0123456789abcdef0123456789abcdef',
      name: 'Android', ip: '192.168.1.10', port: 43887);
    expect(QrPeer.tryParse('https://evil.test'), isNull);
    expect(QrPeer.tryParse(valid.encode().replaceAll('192.168.1.10',
      '8.8.8.8')), isNull);
    expect(QrPeer.tryParse(valid.encode().replaceFirst('v=1','v=99')), isNull);
    expect(QrPeer.tryParse(valid.encode().replaceFirst('43887','0')), isNull);
    expect(QrPeer.tryParse(valid.encode().replaceAll('pair','other')), isNull);
    expect(QrPeer.tryParse(''), isNull);
  });

  test('IP validator permits private network ranges, not public IPv4', () {
    for (final ip in ['10.2.3.4', '172.16.4.2', '172.31.255.10',
        '192.168.49.1', '169.254.13.2']) {
      expect(QrPeer.isLocalIpv4(ip), isTrue, reason: ip);
    }
    for (final ip in ['127.0.0.1', '1.1.1.1', '172.32.0.1',
        '192.169.0.1', '192.168.999.1', 'localhost', '::1']) {
      expect(QrPeer.isLocalIpv4(ip), isFalse, reason: ip);
    }
  });
}

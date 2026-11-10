import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharem/src/core/lan_transfer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LanTransferService service;
  late HttpClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = LanTransferService();
    client = HttpClient();
    await service.start();
  });

  tearDown(() {
    client.close(force: true);
    service.dispose();
  });

  test('serves local device identity on loopback', () async {
    expect(service.running, isTrue);
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:' + service.port.toString() + '/v1/hello'),
    );
    final resp = await req.close();
    final body = jsonDecode(await utf8.decoder.bind(resp).join());
    expect(resp.statusCode, 200);
    expect(body['app'], 'ShareM');
    expect(body['id'], service.deviceId);
  });

  test('offers require receiver consent and token', () async {
    final req = await client.postUrl(
      Uri.parse('http://127.0.0.1:' + service.port.toString() + '/v1/offer'),
    );
    final bytes = utf8.encode(jsonEncode({
      'sender': 'Sender',
      'files': [
        {'name': 'test.txt', 'size': 4, 'sha256': 'a' * 64},
      ],
    }));
    req.contentLength = bytes.length;
    req.add(bytes);
    final response = await req.close();
    final offer = jsonDecode(await utf8.decoder.bind(response).join());
    expect(response.statusCode, 200);
    expect(service.incomingOffer?.peerName, 'Sender');

    final offerId = offer['offerId'] as String;
    Future<Map<String, dynamic>> getStatus() async {
      final statusRequest = await client.getUrl(Uri.parse(
        'http://127.0.0.1:' + service.port.toString() +
          '/v1/status/' + offerId,
      ));
      final statusResponse = await statusRequest.close();
      return Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(statusResponse).join()),
      );
    }

    expect((await getStatus())['status'], 'pending');
    service.respondToOffer(true);
    final accepted = await getStatus();
    expect(accepted['status'], 'accepted');
    expect((accepted['token'] as String).length, 48);

    final badUpload = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() +
        '/v1/files/' + offerId + '/0',
    ));
    badUpload.contentLength = 4;
    badUpload.add([1, 2, 3, 4]);
    final rejected = await badUpload.close();
    await rejected.drain<void>();
    expect(rejected.statusCode, 403);
  });

  test('malformed metadata is not accepted', () async {
    final req = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() + '/v1/offer',
    ));
    final bytes = utf8.encode(jsonEncode({
      'files': [{'name': 'bad.bin', 'size': -1, 'sha256': 'bad'}],
    }));
    req.contentLength = bytes.length;
    req.add(bytes);
    final response = await req.close();
    await response.drain<void>();
    expect(response.statusCode, 400);
    expect(service.incomingOffer, isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:crypto/crypto.dart';
import 'package:sharem/src/core/lan_transfer_service.dart';

class _RealNetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  _RealNetworkTestBinding();

  late LanTransferService service;
  late HttpClient client;
  late Directory temp;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('sharem-test-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(temp.path);
    service = LanTransferService();
    client = HttpClient();
    await service.start();
  });

  tearDown(() async {
    client.close(force: true);
    service.dispose();
    PathProviderPlatform.instance = previousPaths;
    if (await temp.exists()) await temp.delete(recursive: true);
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
  test('receives and verifies file content end-to-end over loopback', () async {
    const sample = 'ShareM integration payload';
    final bytes = utf8.encode(sample);
    final hash = sha256.convert(bytes).toString();
    final offerReq = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() + '/v1/offer',
    ));
    final payload = utf8.encode(jsonEncode({
      'sender': 'Computer',
      'files': [{'name': '../../sample.txt', 'size': bytes.length, 'sha256': hash}],
    }));
    offerReq.contentLength = payload.length;
    offerReq.add(payload);
    final offerResp = await offerReq.close();
    final offer = jsonDecode(await utf8.decoder.bind(offerResp).join());
    expect(offerResp.statusCode, 200);
    service.respondToOffer(true);
    final id = offer['offerId'].toString();

    final statusReq = await client.getUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() + '/v1/status/' + id,
    ));
    final statusResp = await statusReq.close();
    final status = jsonDecode(await utf8.decoder.bind(statusResp).join());
    final token = status['token'] as String;
    final req = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() + '/v1/files/' + id + '/0',
    ));
    req.headers.set('X-ShareM-Token', token);
    req.contentLength = bytes.length;
    req.add(bytes);
    final reply = await req.close();
    await reply.drain<void>();
    expect(reply.statusCode, 200);
    final saved = File(p.join(temp.path, 'ShareM', 'Received', 'sample.txt'));
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsString(), sample);
    expect(service.history.first.status.name, 'completed');
  });

}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sharem/src/core/transfer_models.dart';
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

  test('remote cancellation rejects wrong secret and stops pending offer',
      () async {
    final secret = 'b' * 48;
    final offerReq = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() + '/v1/offer'));
    final jsonBody = utf8.encode(jsonEncode({
      'sender': 'Other device',
      'cancelToken': secret,
      'files': [{'name': 'video.mp4', 'size': 100,
        'sha256': 'c' * 64}],
    }));
    offerReq.contentLength = jsonBody.length;
    offerReq.add(jsonBody);
    final offerResponse = await offerReq.close();
    final offer = jsonDecode(await utf8.decoder.bind(offerResponse).join());
    expect(offerResponse.statusCode, 200);
    final id = offer['offerId'] as String;

    Future<int> cancel(String value) async {
      final req = await client.postUrl(Uri.parse(
        'http://127.0.0.1:' + service.port.toString() +
        '/v1/cancel/' + id));
      req.headers.set('X-ShareM-Cancel', value);
      req.contentLength = 0;
      final response = await req.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await cancel('d' * 48), 403);
    expect(service.incomingOffer?.status, 'pending');
    expect(await cancel(secret), 200);
    expect(service.incomingOffer, isNull);

    final statusRequest = await client.getUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() +
      '/v1/status/' + id));
    final status = await statusRequest.close();
    final body = jsonDecode(await utf8.decoder.bind(status).join());
    expect(body['status'], 'cancelled');
  });

  test('invalid hashes never leave a received file on disk', () async {
    final bytes = utf8.encode('file with wrong hash');
    final offerReq = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() + '/v1/offer'));
    final payload = utf8.encode(jsonEncode({
      'sender': 'Computer',
      'files': [{'name': 'photo.jpg', 'size': bytes.length,
        'sha256': 'f' * 64}],
    }));
    offerReq.contentLength = payload.length;
    offerReq.add(payload);
    final offerResp = await offerReq.close();
    final offer = jsonDecode(await utf8.decoder.bind(offerResp).join());
    expect(offerResp.statusCode, 200);
    service.respondToOffer(true);
    final id = offer['offerId'] as String;
    final statusReq = await client.getUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() +
      '/v1/status/' + id));
    final status = jsonDecode(await utf8.decoder.bind(
      await statusReq.close()).join());
    final upload = await client.postUrl(Uri.parse(
      'http://127.0.0.1:' + service.port.toString() +
      '/v1/files/' + id + '/0'));
    upload.headers.set('X-ShareM-Token', status['token'] as String);
    upload.contentLength = bytes.length;
    upload.add(bytes);
    final response = await upload.close();
    await response.drain<void>();
    expect(response.statusCode, 422);
    final folder = Directory(p.join(temp.path, 'ShareM', 'Received'));
    expect(await folder.list().toList(), isEmpty);
    expect(service.history.first.status.name, 'failed');
  });

  test('damaged saved history never stops LAN receiver', () async {
    SharedPreferences.setMockInitialValues({
      'history': '{broken-json',
    });
    final recovered = LanTransferService();
    try {
      await recovered.start();
      expect(recovered.running, isTrue);
      expect(recovered.history, isEmpty);
    } finally {
      recovered.dispose();
    }
  });

  test('remote peer identity mismatch prevents outgoing transfer', () async {
    final peerFile = File(p.join(temp.path, 'hello.txt'));
    await peerFile.writeAsString('important file');
    final peer = NearbyDevice(
      id: 'd' * 32, name: 'Other device',
      host: '127.0.0.1', port: service.port,
    );
    await service.sendFiles(peer, [
      PlatformFile(name: 'hello.txt',
        size: await peerFile.length(), path: peerFile.path),
    ]);
    expect(service.history.first.status, TransferStatus.failed);
    expect(service.incomingOffer, isNull);
  });

}

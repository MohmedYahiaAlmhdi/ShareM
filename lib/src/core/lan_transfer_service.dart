import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'transfer_models.dart';

/// Direct LAN file transfer. HTTP transport is NOT encrypted in v0.1.
class LanTransferService extends ChangeNotifier {
  static const discoveryPort = 43886;
  final deviceId = randomHex();
  final peers = <NearbyDevice>[];
  final history = <TransferEntry>[];
  final _offers = <String, IncomingOffer>{};
  final _uploads = <String, HttpClientRequest>{};
  final _receivingOffers = <String>{};
  HttpServer? _server;
  RawDatagramSocket? _socket;
  Timer? _heartbeat;
  Timer? _cleanup;
  IncomingOffer? incomingOffer;
  String deviceName = 'ShareM';
  String localAddress = '—';
  String? startupError;
  int port = 0;
  bool running = false;
  bool _disposed = false;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  void changed() { if (!_disposed) notifyListeners(); }

  void _progressChanged() {
    final now = DateTime.now();
    if (now.difference(_lastProgressUpdate).inMilliseconds >= 90) {
      _lastProgressUpdate = now;
      changed();
    }
  }

  Future<void> start() async {
    if (running) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      deviceName = prefs.getString('device_name') ?? 'ShareM ' + Platform.operatingSystem;
      final data = prefs.getString('history');
      if (data != null) {
        for (final row in (jsonDecode(data) as List).whereType<Map>()) {
          final item = TransferEntry.fromJson(Map<String, dynamic>.from(row));
          if (item.isRunning) item.status = TransferStatus.failed;
          history.add(item);
        }
      }
      final networks = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final address in networks.expand((e) => e.addresses)) {
        if (!address.address.startsWith('169.254.')) {
          localAddress = address.address; break;
        }
      }
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      port = _server!.port;
      _server!.listen(_handle, onError: (Object e) { startupError = e.toString(); changed(); });
      running = true;
      changed();
      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort,
            reuseAddress: true, reusePort: !Platform.isWindows);
        _socket!.broadcastEnabled = true;
        _socket!.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = _socket?.receive()) != null) {
            try {
              final json = jsonDecode(utf8.decode(datagram!.data));
              if (json is! Map || json['app'] != 'ShareM' || json['v'] != 1 ||
                  json['id'] == deviceId || json['id'] is! String ||
                  json['name'] is! String || json['port'] is! int) continue;
              final discoveredPort = json['port'] as int;
              if (discoveredPort < 1 || discoveredPort > 65535) continue;
              final name = json['name'] as String;
              _upsert(NearbyDevice(id: json['id'] as String,
                name: name.length > 36 ? name.substring(0, 36) : name,
                host: datagram.address.address, port: discoveredPort));
            } catch (_) { /* Ignore untrusted discovery packets. */ }
          }
        });
        _announce();
        _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) => _announce());
      } catch (_) { /* Manual connection works without UDP broadcast. */ }
      _cleanup = Timer.periodic(const Duration(seconds: 10), (_) {
        peers.removeWhere((e) => DateTime.now().difference(e.lastSeen) > const Duration(seconds: 22));
        _offers.removeWhere((id, offer) => DateTime.now().difference(offer.createdAt) >
            const Duration(hours: 2) && !history.any((e) => e.id == id && e.isRunning));
        changed();
      });
    } catch (e) {
      startupError = 'Unable to start: ' + e.toString(); changed();
    }
  }

  Future<void> rename(String value) async {
    final name = value.trim();
    if (name.isEmpty || name.length > 36) throw const FormatException('Name must be 1–36 characters');
    deviceName = name;
    (await SharedPreferences.getInstance()).setString('device_name', name);
    _announce(); changed();
  }

  void refresh() => _announce();
  void _announce() {
    try {
      final bytes = utf8.encode(jsonEncode({'app': 'ShareM', 'v': 1, 'id': deviceId,
        'name': deviceName, 'port': port}));
      _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
  }

  void _upsert(NearbyDevice peer) {
    final index = peers.indexWhere((e) => e.id == peer.id);
    if (index < 0) { peers.add(peer); } else { peers[index] = peer; }
    changed();
  }

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);

  Future<void> addManualPeer(String hostAndPort) async {
    final uri = Uri.tryParse('http://' + hostAndPort.trim());
    if (uri == null || uri.host.isEmpty || !uri.hasPort ||
        uri.port < 1 || uri.port > 65535) {
      throw const FormatException('Use IP:port, e.g. 192.168.1.7:12345');
    }
    final client = _client();
    try {
      final req = await client.getUrl(uri.replace(path: '/v1/hello')).timeout(const Duration(seconds: 6));
      final json = await _decode(await req.close());
      if (json['app'] != 'ShareM' || json['v'] != 1 ||
          json['id'] is! String || json['name'] is! String) {
        throw const FormatException('Device is not running ShareM');
      }
      if (json['id'] == deviceId) throw StateError('This device cannot connect to itself');
      _upsert(NearbyDevice(id: json['id'] as String, name: json['name'] as String,
        host: uri.host, port: uri.port));
    } finally { client.close(force: true); }
  }

  void cancel(TransferEntry entry) {
    if (entry.direction != TransferDirection.outgoing || !entry.isRunning) return;
    entry.cancellationRequested = true;
    _uploads[entry.id]?.abort(StateError('Cancelled'));
    entry.status = TransferStatus.cancelled; changed();
  }

  void _check(TransferEntry entry) {
    if (entry.cancellationRequested) throw StateError('Cancelled by user');
  }

  Future<void> sendFiles(NearbyDevice peer, List<PlatformFile> files) async {
    if (files.isEmpty) return;
    final entry = TransferEntry(id: randomHex(), peerName: peer.name,
      direction: TransferDirection.outgoing, files: files.map((e) => safeFileName(e.name)).toList());
    history.insert(0, entry); changed();
    final client = _client();
    try {
      if (files.length > 100) throw StateError('Maximum 100 files');
      final manifest = <FileManifest>[];
      for (final file in files) {
        _check(entry);
        final length = file.lengthSync() ?? await file.length();
        if (length == null || length > 20 * 1024 * 1024 * 1024) {
          throw StateError('Unreadable or too large (maximum 20 GB) file');
        }
        final digest = await sha256.bind(file.readAsByteStream()).first;
        manifest.add(FileManifest(name: safeFileName(file.name), size: length, sha256: digest.toString()));
      }
      _check(entry);
      entry.totalBytes = manifest.fold<int>(0, (sum, file) => sum + file.size);
      entry.status = TransferStatus.waiting; changed();
      final offer = await _post(client, peer, '/v1/offer', {'sender': deviceName,
        'files': manifest.map((f) => f.toJson()).toList()});
      final id = offer['offerId'];
      if (id is! String) throw const FormatException('Invalid offer ID');
      String? token;
      for (var i = 0; i < 120; i++) {
        _check(entry);
        await Future<void>.delayed(const Duration(seconds: 1));
        final req = await client.getUrl(Uri(scheme: 'http', host: peer.host,
          port: peer.port, path: '/v1/status/$id'));
        final status = await _decode(await req.close());
        if (status['status'] == 'rejected') {
          entry.status = TransferStatus.rejected; changed(); return;
        }
        if (status['status'] == 'accepted') {
          token = status['token'] as String?; break;
        }
      }
      if (token == null) throw TimeoutException('Receiver did not accept');
      entry.status = TransferStatus.transferring; changed();
      for (var i = 0; i < files.length; i++) {
        _check(entry);
        final req = await client.postUrl(Uri(scheme: 'http', host: peer.host,
          port: peer.port, path: '/v1/files/$id/$i'));
        _uploads[entry.id] = req;
        req.headers.set('X-ShareM-Token', token);
        req.contentLength = manifest[i].size;
        await req.addStream(files[i].readAsByteStream().map((chunk) {
          _check(entry); entry.doneBytes += chunk.length; _progressChanged(); return chunk;
        }));
        final reply = await req.close();
        _uploads.remove(entry.id);
        await _decode(reply);
      }
      entry.status = TransferStatus.completed;
      entry.doneBytes = entry.totalBytes;
    } catch (e) {
      entry.status = entry.cancellationRequested ? TransferStatus.cancelled : TransferStatus.failed;
      entry.error = e.toString();
    } finally {
      _uploads.remove(entry.id); client.close(force: true);
      changed(); await _persist();
    }
  }

  void respondToOffer(bool accept) {
    final offer = incomingOffer;
    if (offer == null || offer.status != 'pending') return;
    offer.status = accept ? 'accepted' : 'rejected';
    if (accept) {
      offer.token = randomHex(24);
      history.insert(0, TransferEntry(id: offer.id, peerName: offer.peerName,
        files: offer.files.map((f) => f.name).toList(),
        direction: TransferDirection.incoming, status: TransferStatus.transferring,
        totalBytes: offer.totalBytes));
    }
    incomingOffer = null; changed(); _persist();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final route = req.uri.pathSegments;
      if (req.method == 'GET' && req.uri.path == '/v1/hello') {
        _reply(req, 200, {'app': 'ShareM', 'v': 1, 'id': deviceId, 'name': deviceName});
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/v1/offer') {
        if (incomingOffer != null) { _reply(req, 409, {'error': 'Busy'}); return; }
        if (req.contentLength < 0 || req.contentLength > 65536) {
          throw const FormatException('Offer too large');
        }
        final raw = await utf8.decoder.bind(req).join();
        if (raw.length > 65536) throw const FormatException('Offer too large');
        final body = jsonDecode(raw);
        if (body is! Map || body['files'] is! List) throw const FormatException('Invalid offer');
        final rawFiles = body['files'] as List;
        if (rawFiles.isEmpty || rawFiles.length > 100) throw const FormatException('Invalid files');
        final files = rawFiles.map(FileManifest.fromJson).toList();
        final sender = body['sender'] is String ? body['sender'] as String : 'Nearby device';
        final offer = IncomingOffer(id: randomHex(24),
          peerName: sender.length > 36 ? sender.substring(0, 36) : sender,
          sourceIp: req.connectionInfo?.remoteAddress.address ?? '', files: files);
        _offers[offer.id] = offer;
        incomingOffer = offer; changed();
        _reply(req, 200, {'offerId': offer.id}); return;
      }
      if (req.method == 'GET' && route.length == 3 &&
          route[0] == 'v1' && route[1] == 'status') {
        final offer = _offers[route[2]];
        if (offer == null || !_sameSender(req, offer)) {
          _reply(req, 404, {'error': 'Not found'}); return;
        }
        _reply(req, 200, {'status': offer.status,
          if (offer.status == 'accepted') 'token': offer.token}); return;
      }
      if (req.method == 'POST' && route.length == 4 &&
          route[0] == 'v1' && route[1] == 'files') {
        final offer = _offers[route[2]];
        final index = int.tryParse(route[3]);
        if (offer == null || index == null || index < 0 ||
            index >= offer.files.length || offer.status != 'accepted' ||
            index != offer.nextIndex || _receivingOffers.contains(offer.id) ||
            !_sameSender(req, offer) ||
            req.headers.value('X-ShareM-Token') != offer.token) {
          _reply(req, 403, {'error': 'Unauthorized'}); return;
        }
        if (req.contentLength != offer.files[index].size) {
          _reply(req, 400, {'error': 'Size mismatch'}); return;
        }
        _receivingOffers.add(offer.id);
        try {
          await _receive(req, offer, index);
        } finally {
          _receivingOffers.remove(offer.id);
        }
        return;
      }
      _reply(req, 404, {'error': 'Not found'});
    } on FormatException catch (e) {
      _reply(req, 400, {'error': e.message});
    } catch (_) {
      try { _reply(req, 500, {'error': 'Transfer failed'}); } catch (_) {}
    }
  }

  bool _sameSender(HttpRequest req, IncomingOffer offer) =>
    req.connectionInfo?.remoteAddress.address == offer.sourceIp;

  Future<void> _receive(HttpRequest req, IncomingOffer offer, int index) async {
    final metadata = offer.files[index];
    final directory = Directory(p.join((await getApplicationDocumentsDirectory()).path,
      'ShareM', 'Received'));
    await directory.create(recursive: true);
    var target = p.join(directory.path, safeFileName(metadata.name));
    final extension = p.extension(target);
    final basename = p.basenameWithoutExtension(target);
    var counter = 1;
    while (await File(target).exists()) {
      target = p.join(directory.path, '$basename ($counter)$extension'); counter++;
    }
    final output = File(target);
    final sink = output.openWrite();
    final entry = history.firstWhere((e) => e.id == offer.id);
    var received = 0;
    try {
      await for (final chunk in req) {
        received += chunk.length;
        if (received > metadata.size) throw const FormatException('Oversized upload');
        sink.add(chunk); entry.doneBytes += chunk.length; _progressChanged();
      }
      await sink.flush(); await sink.close();
      if (received != metadata.size) throw const FormatException('Incomplete upload');
      final hash = (await sha256.bind(output.openRead()).first).toString();
      if (hash != metadata.sha256) throw const FormatException('Hash mismatch');
      entry.receivedPaths.add(output.path);
      offer.nextIndex++;
      if (offer.nextIndex == offer.files.length) {
        offer.status = 'completed'; entry.status = TransferStatus.completed;
        await _persist();
      }
      changed(); _reply(req, 200, {'ok': true});
    } catch (e) {
      await sink.close();
      if (await output.exists()) await output.delete();
      offer.status = 'failed'; entry.status = TransferStatus.failed;
      entry.error = e.toString(); changed(); await _persist();
      _reply(req, 422, {'error': 'Integrity check failed'});
    }
  }

  Future<Map<String, dynamic>> _post(HttpClient client, NearbyDevice peer,
      String route, Object body) async {
    final req = await client.postUrl(Uri(scheme: 'http', host: peer.host,
      port: peer.port, path: route));
    final payload = utf8.encode(jsonEncode(body));
    req.headers.contentType = ContentType.json;
    req.contentLength = payload.length; req.add(payload);
    return _decode(await req.close());
  }

  Future<Map<String, dynamic>> _decode(HttpClientResponse response) async {
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('Peer responded ' + response.statusCode.toString() + ': ' + body);
    }
    final json = jsonDecode(body);
    if (json is! Map) throw const FormatException('Invalid server response');
    return Map<String, dynamic>.from(json);
  }

  void _reply(HttpRequest request, int status, Object body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('history', jsonEncode(history.take(50).map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true; _heartbeat?.cancel(); _cleanup?.cancel();
    _socket?.close(); _server?.close(force: true); super.dispose();
  }
}

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
import 'verified_file_writer.dart';

/// Direct LAN file transfer. HTTP transport is NOT encrypted in v0.1.
class LanTransferService extends ChangeNotifier {
  static const discoveryPort = 43886;
  /// Predictable owner endpoint for Android Wi-Fi Direct group clients.
  static const transferPort = 43887;
  final deviceId = randomHex();
  final peers = <NearbyDevice>[];
  final history = <TransferEntry>[];
  final _offers = <String, IncomingOffer>{};
  final _uploads = <String, HttpClientRequest>{};
  final _remoteCancellations =
      <String, ({NearbyDevice peer, String offerId, String secret})>{};
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
      await refreshLocalAddress();
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, transferPort);
      } on SocketException {
        // A port collision allows LAN QR with the chosen ephemeral port,
        // but Wi-Fi Direct automatic owner connection needs transferPort.
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
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

  /// Prefer reachable Wi-Fi and P2P interfaces, not VPN/cellular IPs.
  Future<void> refreshLocalAddress() async {
    try {
      final networks = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
      String? direct, wifi, wired;
      for (final n in networks) {
        final name = n.name.toLowerCase();
        if (name.startsWith('tun') || name.startsWith('utun') ||
            name.startsWith('rmnet') || name.startsWith('ccmni') ||
            name.startsWith('pdp') || name.startsWith('lo')) continue;
        for (final address in n.addresses) {
          final ip = address.address;
          if (!_privateIpv4(ip)) continue;
          if (name.startsWith('p2p') || ip.startsWith('192.168.49.')) {
            direct ??= ip;
          } else if (name.startsWith('wlan') ||
                     name.startsWith('wifi') || name.startsWith('swlan') ||
                     name.startsWith('ap')) {
            wifi ??= ip;
          } else if (name.startsWith('eth') || name.startsWith('en')) {
            wired ??= ip;
          }
        }
      }
      localAddress = direct ?? wifi ?? wired ?? '—';
      changed();
    } catch (_) {
      localAddress = '—';
      changed();
    }
  }

  static bool _privateIpv4(String host) {
    final items = host.split('.').map(int.tryParse).toList();
    if (items.length != 4 ||
        items.any((x) => x == null || x < 0 || x > 255)) return false;
    final first = items[0]!, second = items[1]!;
    return first == 10 || first == 192 && second == 168 ||
      first == 172 && second >= 16 && second <= 31;
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

  Future<void> addManualPeer(String hostAndPort, {String? expectedId}) async {
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
      if (expectedId != null && json['id'] != expectedId) {
        throw StateError('The responder is not the device advertised by this QR code');
      }
      _upsert(NearbyDevice(id: json['id'] as String, name: json['name'] as String,
        host: uri.host, port: uri.port));
    } finally { client.close(force: true); }
  }

  /// Announce the P2P client to its group owner; this is discovery only.
  /// Transferring files still requires explicit receiver approval.
  Future<void> introduceToGroupOwner(String host) async {
    if (!running || port <= 0) return;
    final bytes = utf8.encode(jsonEncode({
      'app': 'ShareM', 'v': 1,
      'id': deviceId, 'name': deviceName, 'port': port,
    }));
    final client = _client();
    try {
      final req = await client.postUrl(Uri(
        scheme: 'http', host: host, port: transferPort,
        path: '/v1/introduce')).timeout(const Duration(seconds: 6));
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw const HttpException('Could not introduce device');
      }
      await res.drain<void>();
    } finally { client.close(force: true); }
  }

  /// Both sender and receiver can cancel an in-progress transfer. A sender's
  /// cancellation uses an unguessable, per-offer secret to notify the peer.
  void cancel(TransferEntry entry) {
    if (!entry.isRunning) return;
    entry.cancellationRequested = true;
    entry.status = TransferStatus.cancelled;
    if (entry.direction == TransferDirection.outgoing) {
      _uploads[entry.id]?.abort(const TransferCancelledException());
      final remote = _remoteCancellations[entry.id];
      if (remote != null) unawaited(_notifyCancellation(remote));
    } else {
      final offer = _offers[entry.id];
      if (offer != null && offer.status == 'accepted') {
        offer.status = 'cancelled';
      }
    }
    changed();
    unawaited(_persist());
  }

  Future<void> _notifyCancellation(
    ({NearbyDevice peer, String offerId, String secret}) session,
  ) async {
    final http = _client();
    try {
      final req = await http.postUrl(Uri(
        scheme: 'http', host: session.peer.host, port: session.peer.port,
        path: '/v1/cancel/' + session.offerId,
      )).timeout(const Duration(seconds: 5));
      req.headers.set('X-ShareM-Cancel', session.secret);
      req.contentLength = 0;
      await (await req.close().timeout(const Duration(seconds: 5)))
        .drain<void>();
    } catch (_) {
      // The remote device might already be disconnected or stopped.
    } finally {
      http.close(force: true);
    }
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
      final cancelSecret = randomHex(24);
      final offer = await _post(client, peer, '/v1/offer', {
        'sender': deviceName,
        'cancelToken': cancelSecret,
        'files': manifest.map((f) => f.toJson()).toList(),
      });
      final id = offer['offerId'];
      if (id is! String) throw const FormatException('Invalid offer ID');
      _remoteCancellations[entry.id] = (
        peer: peer, offerId: id, secret: cancelSecret,
      );
      if (entry.cancellationRequested) {
        unawaited(_notifyCancellation(_remoteCancellations[entry.id]!));
        throw const TransferCancelledException();
      }
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
        if (status['status'] == 'cancelled') {
          entry.status = TransferStatus.cancelled; changed(); return;
        }
        if (status['status'] == 'accepted') {
          token = status['token'] as String?; break;
        }
      }
      if (token == null) throw TimeoutException('Receiver did not accept');
      entry.status = TransferStatus.transferring;
      entry.transferStartedAt = DateTime.now();
      changed();
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
      _uploads.remove(entry.id);
      _remoteCancellations.remove(entry.id);
      client.close(force: true);
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
        totalBytes: offer.totalBytes,
        transferStartedAt: DateTime.now()));
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
      if (req.method == 'POST' && req.uri.path == '/v1/introduce') {
        if (req.contentLength < 1 || req.contentLength > 1024) {
          _reply(req, 413, {'error': 'Too large'}); return;
        }
        final raw = await utf8.decoder.bind(req).join();
        if (raw.length > 1024) throw const FormatException('Too large');
        final body = jsonDecode(raw);
        if (body is! Map || body['app'] != 'ShareM' || body['v'] != 1 ||
            body['id'] is! String || body['name'] is! String ||
            body['port'] is! int) {
          throw const FormatException('Invalid discovery message');
        }
        final id = body['id'] as String;
        final name = (body['name'] as String).trim();
        final remotePort = body['port'] as int;
        final remote = req.connectionInfo?.remoteAddress.address;
        if (id.isEmpty || id.length > 80 || id == deviceId ||
            name.isEmpty || name.length > 36 || remotePort < 1 ||
            remotePort > 65535 || remote == null || !_privateIpv4(remote)) {
          throw const FormatException('Invalid P2P device');
        }
        _upsert(NearbyDevice(id: id, name: name, host: remote,
          port: remotePort));
        _reply(req, 200, {'ok': true}); return;
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
        final rawCancelToken = body['cancelToken'];
        if (rawCancelToken != null && (rawCancelToken is! String ||
            !RegExp(r'^[a-f0-9]{48}
        final offer = IncomingOffer(id: randomHex(24),
          peerName: sender.length > 36 ? sender.substring(0, 36) : sender,
          sourceIp: req.connectionInfo?.remoteAddress.address ?? '',
          files: files, cancelToken: rawCancelToken as String?);
        _offers[offer.id] = offer;
        incomingOffer = offer; changed();
        _reply(req, 200, {'offerId': offer.id}); return;
      }
      if (req.method == 'POST' && route.length == 3 &&
          route[0] == 'v1' && route[1] == 'cancel') {
        final offer = _offers[route[2]];
        if (offer == null || !canCancelOffer(
              offer, req.connectionInfo?.remoteAddress.address,
              req.headers.value('X-ShareM-Cancel'))) {
          _reply(req, 403, {'error': 'Cancellation not authorized'});
          return;
        }
        if (offer.status == 'pending' || offer.status == 'accepted') {
          offer.status = 'cancelled';
          if (incomingOffer?.id == offer.id) incomingOffer = null;
          for (final entry in history.where((e) => e.id == offer.id)) {
            entry.status = TransferStatus.cancelled;
            entry.cancellationRequested = true;
          }
          changed();
          unawaited(_persist());
        }
        _reply(req, 200, {'status': offer.status});
        return;
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
    final directory = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path, 'ShareM', 'Received'));
    final entry = history.firstWhere((e) => e.id == offer.id);
    try {
      final destination = await VerifiedFileWriter.receive(
        directory: directory,
        metadata: metadata,
        chunks: req,
        onProgress: (count) {
          entry.doneBytes += count;
          _progressChanged();
        },
        isCancelled: () =>
          offer.status == 'cancelled' || entry.cancellationRequested,
      );
      entry.receivedPaths.add(destination);
      offer.nextIndex += 1;
      if (offer.nextIndex == offer.files.length) {
        offer.status = 'completed';
        entry.status = TransferStatus.completed;
        await _persist();
      }
      changed();
      _reply(req, 200, {'ok': true});
    } catch (error) {
      final cancelled = offer.status == 'cancelled' ||
          error is TransferCancelledException;
      offer.status = cancelled ? 'cancelled' : 'failed';
      entry.status = cancelled
        ? TransferStatus.cancelled : TransferStatus.failed;
      entry.error = cancelled ? null : error.toString();
      changed();
      await _persist();
      try {
        _reply(req, cancelled ? 410 : 422,
          {'error': cancelled ? 'Cancelled' : 'Integrity check failed'});
      } catch (_) {}
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

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WifiDirectPeer {
  const WifiDirectPeer({required this.address, required this.name,
    required this.status});
  final String address;
  final String name;
  final int status;
}

class WifiDirectService extends ChangeNotifier {
  static const _methods = MethodChannel('sharem/wifi_direct');
  static const _events = EventChannel('sharem/wifi_direct/events');

  final peers = <WifiDirectPeer>[];
  StreamSubscription<dynamic>? _subscription;

  bool available = false;
  bool enabled = false;
  bool connected = false;
  bool groupOwner = false;
  bool busy = false;
  String? ownerIp;
  String? error;
  bool _disposed = false;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  bool get canScan => isAndroid && available;

  Future<void> initialize() async {
    if (!isAndroid) return;
    _subscription ??= _events.receiveBroadcastStream().listen(_receive,
      onError: (Object e) { error = e.toString(); _notify(); });
    try {
      final info = await _methods.invokeMapMethod<String, dynamic>('initialize');
      available = info?['available'] == true;
      enabled = info?['enabled'] == true;
      connected = info?['connected'] == true;
      _notify();
      if (available) await refresh();
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
      _notify();
    } on MissingPluginException {
      error = 'Wi-Fi Direct native module is not installed on this build.';
      _notify();
    }
  }

  Future<void> refresh() async {
    if (!canScan) return;
    try {
      await _methods.invokeMethod<void>('refresh');
    } on PlatformException catch (e) {
      error = e.message ?? e.code; _notify();
    }
  }

  Future<void> discover() async {
    if (!canScan || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final permission = await _methods.invokeMethod<bool>('requestPermission');
      if (permission != true) throw StateError('Nearby Wi-Fi permission was denied');
      await _methods.invokeMethod<void>('discover');
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false; _notify();
    }
  }

  Future<void> connect(String peerAddress) async {
    if (!canScan || busy) return;
    if (!peers.any((peer) => peer.address == peerAddress)) {
      error = 'Device no longer appears in Wi-Fi Direct discovery';
      _notify();
      return;
    }
    busy = true; error = null; _notify();
    try {
      final permission = await _methods.invokeMethod<bool>('requestPermission');
      if (permission != true) throw StateError('Nearby Wi-Fi permission was denied');
      await _methods.invokeMethod<void>('connect', {'address': peerAddress});
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false; _notify();
    }
  }

  Future<void> disconnect() async {
    if (!isAndroid) return;
    try {
      await _methods.invokeMethod<void>('disconnect');
    } catch (e) {
      error = e.toString(); _notify();
    }
  }

  void _receive(dynamic raw) {
    if (raw is! Map) return;
    final event = raw['type'];
    if (event == 'state') {
      enabled = raw['enabled'] == true;
    } else if (event == 'peers' && raw['peers'] is List) {
      peers.clear();
      for (final value in (raw['peers'] as List)) {
        if (value is! Map || value['address'] is! String) continue;
        peers.add(WifiDirectPeer(
          address: value['address'] as String,
          name: value['name'] as String? ?? 'Android device',
          status: value['status'] as int? ?? -1,
        ));
      }
    } else if (event == 'connection') {
      connected = raw['connected'] == true;
      groupOwner = raw['groupOwner'] == true;
      ownerIp = connected && raw['ownerIp'] is String
        ? raw['ownerIp'] as String : null;
    } else if (event == 'error') {
      error = raw['message'] as String? ?? 'Wi-Fi Direct error';
    }
    _notify();
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

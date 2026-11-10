import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'release_models.dart';

enum UpdatePhase { idle, checking, current, available, downloading, ready, installing, failed }

/// GitHub Releases update client. Android owns installation; no silent installs.
class UpdateService extends ChangeNotifier {
  static final Uri manifestUrl = Uri.parse(
    'https://github.com/MohmedYahiaAlmhdi/ShareM/releases/latest/download/update.json');
  static const channel = MethodChannel('sharem/installer');
  UpdatePhase phase = UpdatePhase.idle;
  ShareMRelease? release;
  ReleaseApk? selected;
  String currentVersion = '—';
  String? message;
  String? cachedApk;
  int downloaded = 0;
  bool _cancelled = false;
  bool _disposed = false;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  bool get hasUpdate => release != null && (
    phase == UpdatePhase.available || phase == UpdatePhase.downloading ||
    phase == UpdatePhase.ready || phase == UpdatePhase.installing);
  double get progress => selected == null ? 0.0 :
      (downloaded / selected!.sizeBytes).clamp(0.0, 1.0).toDouble();

  void _emit(UpdatePhase next, [String? detail]) {
    phase = next;
    message = detail;
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.installing) return;
    _emit(UpdatePhase.checking);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      currentVersion = (await PackageInfo.fromPlatform()).version;
      final request = await http.getUrl(manifestUrl);
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('No published release (' + response.statusCode.toString() + ')');
      }
      if (response.contentLength > 24000) throw const FormatException('Manifest too large');
      final output = BytesBuilder(copy: false);
      await for (final part in response) {
        output.add(part);
        if (output.length > 24000) throw const FormatException('Manifest too large');
      }
      final parsed = ShareMRelease.parse(jsonDecode(utf8.decode(output.takeBytes())));
      release = parsed;
      if (!parsed.isNewerThan(currentVersion)) {
        selected = null;
        _emit(UpdatePhase.current);
        return;
      }
      if (!isAndroid) {
        _emit(UpdatePhase.available);
        return;
      }
      final abis = await channel.invokeListMethod<String>('getSupportedAbis') ?? <String>[];
      selected = parsed.forAbis(abis);
      if (selected == null) {
        throw StateError('No APK provided for this Android CPU');
      }
      _emit(UpdatePhase.available);
    } catch (error) {
      _emit(UpdatePhase.failed, error.toString());
    } finally {
      http.close(force: true);
    }
  }

  Future<void> download() async {
    final apk = selected;
    if (!isAndroid || apk == null || phase != UpdatePhase.available) return;
    _cancelled = false;
    cachedApk = null;
    downloaded = 0;
    _emit(UpdatePhase.downloading);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    File? target;
    try {
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'sharem_updates'));
      await dir.create(recursive: true);
      target = File(p.join(dir.path,
        'ShareM-' + release!.version + '-' + apk.abi + '.apk'));
      if (await target.exists()) await target.delete();

      final req = await http.getUrl(apk.url);
      final response = await req.close().timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw HttpException('Download failed (' + response.statusCode.toString() + ')');
      }
      if (response.contentLength > apk.sizeBytes) {
        throw const FormatException('Unexpected APK length');
      }
      final sink = target.openWrite();
      try {
        var last = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final bytes in response) {
          if (_cancelled) throw StateError('Download cancelled');
          downloaded += bytes.length;
          if (downloaded > apk.sizeBytes) {
            throw const FormatException('APK too large');
          }
          sink.add(bytes);
          if (DateTime.now().difference(last).inMilliseconds > 150) {
            last = DateTime.now();
            if (!_disposed) notifyListeners();
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (downloaded != apk.sizeBytes) {
        throw const FormatException('Incomplete APK');
      }
      final digest = (await sha256.bind(target.openRead()).first).toString();
      if (digest != apk.sha256) {
        throw const FormatException('APK SHA-256 mismatch');
      }
      if (_cancelled) throw StateError('Download cancelled');
      cachedApk = target.path;
      _emit(UpdatePhase.ready);
    } catch (error) {
      if (target != null && await target.exists()) await target.delete();
      _emit(UpdatePhase.failed, error.toString());
    } finally {
      http.close(force: true);
    }
  }

  void cancel() { if (phase == UpdatePhase.downloading) _cancelled = true; }

  Future<void> install() async {
    if (!isAndroid || cachedApk == null || phase != UpdatePhase.ready) return;
    try {
      final result = await channel.invokeMethod<String>('installUpdate', {'path': cachedApk});
      if (result == 'permission_required') {
        _emit(UpdatePhase.ready, 'اسمح بتثبيت التحديثات من ShareM في إعدادات Android ثم اضغط تثبيت مرة أخرى.');
      } else if (result == 'launched') {
        _emit(UpdatePhase.installing);
      } else {
        throw StateError('APK installer not available');
      }
    } catch (e) {
      _emit(UpdatePhase.ready, e.toString());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    super.dispose();
  }
}

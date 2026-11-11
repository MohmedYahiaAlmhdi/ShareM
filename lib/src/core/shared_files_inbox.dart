import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// A disk-backed file delivered by Android Sharesheet. Does not load its bytes
/// into RAM; it streams through the same transport as a picked file.
class LocalSharedPlatformFile extends PlatformFile {
  LocalSharedPlatformFile({
    required this.name,
    required this.path,
    required this.byteLength,
  });

  @override
  final String name;

  @override
  final String path;

  final int byteLength;

  @override
  Uri get uri => Uri.file(path);

  @override
  XFile get xFile => XFile(path, name: name);

  @override
  int? lengthSync() => byteLength;

  @override
  Future<int?> length() async => File(path).length();

  @override
  Future<Uint8List> readAsBytes() => File(path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(path).openRead().map(Uint8List.fromList);
}

/// Receives files copied by Android's share-intent bridge. Users still choose
/// a receiver, who must approve the incoming file manifest before transfer.
class SharedFilesInbox extends ChangeNotifier {
  static const MethodChannel _method =
      MethodChannel('sharem/shared_files');
  static const EventChannel _events =
      EventChannel('sharem/shared_files/events');

  final _newFiles = <LocalSharedPlatformFile>[];
  StreamSubscription<dynamic>? _subscription;
  bool _reading = false;
  bool _again = false;
  bool _disposed = false;
  String? error;

  bool get hasNewFiles => _newFiles.isNotEmpty;

  List<LocalSharedPlatformFile> takeNewFiles() {
    final files = List<LocalSharedPlatformFile>.of(_newFiles);
    _newFiles.clear();
    return files;
  }

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _subscription ??= _events.receiveBroadcastStream().listen((_) {
      unawaited(checkPending());
    }, onError: (Object e) {
      error = 'تعذر الوصول إلى الملفات المشتركة.';
      _notify();
    });
    await checkPending();
  }

  Future<void> checkPending() async {
    if (_reading) {
      _again = true;
      return;
    }
    _reading = true;
    try {
      do {
        _again = false;
        final rows = await _method.invokeListMethod<dynamic>('takePending');
        if (rows == null) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          if (row['error'] is String) {
            error = row['error'] as String;
            _notify();
            continue;
          }
          final path = row['path'];
          final name = row['name'];
          final size = row['size'];
          if (path is! String || name is! String || size is! int ||
              size < 0 || size > 2 * 1024 * 1024 * 1024) continue;
          if (!await File(path).exists()) continue;
          _newFiles.add(LocalSharedPlatformFile(
            name: name, path: path, byteLength: size));
        }
        if (_newFiles.isNotEmpty) _notify();
      } while (_again);
    } on MissingPluginException {
      // Older builds have no native share bridge.
    } on PlatformException catch (e) {
      error = e.message ?? 'تعذر استيراد الملفات.';
      _notify();
    } finally {
      _reading = false;
    }
  }

  /// Android 10+ only: copies an app-received file to public Downloads/ShareM.
  static Future<void> saveToDownloads(String path) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('الحفظ المباشر متاح على Android فقط');
    }
    await _method.invokeMethod<String>('saveToDownloads', {'path': path});
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/shared_files_inbox.dart';

void main() {
  test('shared Android files stream from disk without eager byte loading',
      () async {
    final folder = await Directory.systemTemp.createTemp('sharem-shared-');
    try {
      final file = File(folder.path + '/large.txt');
      final bytes = utf8.encode('Sample file shared from another app');
      await file.writeAsBytes(bytes);
      final shared = LocalSharedPlatformFile(
        name: 'large.txt', path: file.path, byteLength: bytes.length);
      expect(shared.name, 'large.txt');
      expect(shared.path, file.path);
      expect(shared.lengthSync(), bytes.length);
      expect(await shared.length(), bytes.length);
      expect(await shared.readAsBytes(), bytes);
      expect(await shared.readAsByteStream().expand((v) => v).toList(), bytes);
      expect(shared.uri.scheme, 'file');
    } finally {
      await folder.delete(recursive: true);
    }
  });
}

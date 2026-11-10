import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/transfer_models.dart';

void main() {
  test('sanitize paths and reserved characters', () {
    expect(safeFileName('../../secret.txt'), 'secret.txt');
    expect(safeFileName(r'C:\Users\test\file?.jpg'), 'file_.jpg');
    expect(safeFileName('..'), 'file');
    expect(safeFileName(''), 'file');
  });

  test('rejects invalid incoming metadata', () {
    expect(() => FileManifest.fromJson({'name': 'a', 'size': -1,
      'sha256': '0' * 64}), throwsFormatException);
    expect(() => FileManifest.fromJson({'name': 'a', 'size': 123,
      'sha256': 'bad'}), throwsFormatException);
  });

  test('accepts expected file metadata', () {
    final manifest = FileManifest.fromJson({
      'name': 'photo.jpg', 'size': 8192, 'sha256': 'a' * 64,
    });
    expect(manifest.size, 8192);
    expect(manifest.toJson()['name'], 'photo.jpg');
  });

  test('progress remains bounded and serializable', () {
    final entry = TransferEntry(
      id: 'id', peerName: 'Laptop', files: const ['a.txt'],
      direction: TransferDirection.outgoing,
      totalBytes: 100, doneBytes: 120);
    expect(entry.progress, 1);
    expect(TransferEntry.fromJson(entry.toJson()).peerName, 'Laptop');
  });

  test('random identifiers are different', () {
    expect(randomHex(24), isNot(randomHex(24)));
  });
}

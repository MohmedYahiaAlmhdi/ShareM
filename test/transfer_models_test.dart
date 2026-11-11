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


  test('remote cancellation requires the sender address and secret', () {
    final offer = IncomingOffer(
      id: 'offer', peerName: 'Phone', sourceIp: '192.168.49.2',
      files: [], cancelToken: 'a' * 48,
    );
    expect(canCancelOffer(offer, '192.168.49.2', 'a' * 48), isTrue);
    expect(canCancelOffer(offer, '192.168.49.3', 'a' * 48), isFalse);
    expect(canCancelOffer(offer, '192.168.49.2', 'b' * 48), isFalse);
    expect(canCancelOffer(offer, '192.168.49.2', null), isFalse);
    final legacy = IncomingOffer(
      id: 'old', peerName: 'Phone', sourceIp: '192.168.49.2',
      files: [],
    );
    expect(canCancelOffer(legacy, '192.168.49.2', null), isFalse);
  });

  test('transfer speed and ETA use completed bytes', () {
    final entry = TransferEntry(
      id: 'id', peerName: 'Phone', files: ['movie.mp4'],
      direction: TransferDirection.incoming,
      status: TransferStatus.transferring,
      totalBytes: 20 * 1024 * 1024,
      doneBytes: 10 * 1024 * 1024,
      transferStartedAt: DateTime.now().subtract(
        const Duration(seconds: 10)),
    );
    expect(entry.bytesPerSecond, greaterThan(900000));
    expect(entry.secondsRemaining, inInclusiveRange(9, 12));
    entry.status = TransferStatus.completed;
    expect(entry.bytesPerSecond, 0);
    expect(entry.secondsRemaining, isNull);
  });

  test('random identifiers are different', () {
    expect(randomHex(24), isNot(randomHex(24)));
  });
}

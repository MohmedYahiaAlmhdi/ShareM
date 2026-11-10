import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'transfer_models.dart';

/// Streams to a hidden temporary file and promotes it only after verifying
/// the receiver-approved byte count and SHA-256 checksum.
class VerifiedFileWriter {
  const VerifiedFileWriter._();

  static Future<String> receive({
    required Directory directory,
    required FileManifest metadata,
    required Stream<List<int>> chunks,
    required void Function(int count) onProgress,
    bool Function()? isCancelled,
  }) async {
    await directory.create(recursive: true);
    final temporary = File(p.join(directory.path,
      '.sharem-' + randomHex(16) + '.part'));
    IOSink? sink;
    var count = 0;
    try {
      sink = temporary.openWrite();
      final digest = await sha256.bind(chunks.map((chunk) {
        if (isCancelled?.call() ?? false) {
          throw const TransferCancelledException();
        }
        count += chunk.length;
        if (count > metadata.size) {
          throw const FormatException('Incoming file is larger than expected');
        }
        sink!.add(chunk);
        onProgress(chunk.length);
        return chunk;
      })).first;
      await sink.flush();
      await sink.close();
      sink = null;
      if (isCancelled?.call() ?? false) {
        throw const TransferCancelledException();
      }
      if (count != metadata.size) {
        throw const FormatException('Incoming file is incomplete');
      }
      if (digest.toString() != metadata.sha256) {
        throw const FormatException('Incoming file checksum does not match');
      }
      final name = safeFileName(metadata.name);
      final basename = p.basenameWithoutExtension(name);
      final extension = p.extension(name);
      var candidate = File(p.join(directory.path, name));
      var suffix = 1;
      while (await candidate.exists()) {
        candidate = File(p.join(directory.path,
          '$basename ($suffix)$extension'));
        suffix += 1;
      }
      return (await temporary.rename(candidate.path)).path;
    } catch (_) {
      if (sink != null) {
        try { await sink.close(); } catch (_) {}
      }
      if (await temporary.exists()) {
        try { await temporary.delete(); } catch (_) {}
      }
      rethrow;
    }
  }
}

class TransferCancelledException implements Exception {
  const TransferCancelledException();

  @override
  String toString() => 'تم إلغاء عملية النقل';
}

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
    RandomAccessFile? opened;
    var count = 0;
    try {
      final output = await temporary.open(mode: FileMode.write);
      opened = output;

      // Await each disk write before reading the next incoming chunk.
      // This applies backpressure and avoids unbounded IOSink buffering when
      // transfers are faster than local storage.
      Stream<List<int>> checkedChunks() async* {
        await for (final chunk in chunks) {
          if (isCancelled?.call() ?? false) {
            throw const TransferCancelledException();
          }
          count += chunk.length;
          if (count > metadata.size) {
            throw const FormatException('Incoming file is larger than expected');
          }
          await output.writeFrom(chunk);
          onProgress(chunk.length);
          yield chunk;
        }
      }

      final digest = await sha256.bind(checkedChunks()).first;
      await output.flush();
      await output.close();
      opened = null;
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
      if (opened != null) {
        try { await opened.close(); } catch (_) {}
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

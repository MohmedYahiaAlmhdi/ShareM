import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sharem/src/core/transfer_models.dart';
import 'package:sharem/src/core/verified_file_writer.dart';

void main() {
  late Directory folder;
  setUp(() async => folder =
    await Directory.systemTemp.createTemp('sharem-writer-test-'));
  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  FileManifest manifest(String name, List<int> data) => FileManifest(
    name: name, size: data.length,
    sha256: sha256.convert(data).toString(),
  );

  test('verified stream is saved once', () async {
    final data = utf8.encode('Hello ShareM');
    var progress = 0;
    final path = await VerifiedFileWriter.receive(
      directory: folder, metadata: manifest('hello.txt', data),
      chunks: Stream.value(data), onProgress: (n) => progress += n,
    );
    expect(await File(path).readAsBytes(), data);
    expect(progress, data.length);
    expect((await folder.list().toList()).length, 1);
  });

  test('truncation and checksum failure leave no output files', () async {
    final data = utf8.encode('Hello ShareM');
    for (final bad in [data.take(3).toList(), utf8.encode('wrong bytes!')]) {
      await expectLater(VerifiedFileWriter.receive(
        directory: folder, metadata: manifest('hello.txt', data),
        chunks: Stream.value(bad), onProgress: (_) {},
      ), throwsFormatException);
      expect(await folder.list().toList(), isEmpty);
    }
  });

  test('oversized data is rejected', () async {
    await expectLater(VerifiedFileWriter.receive(
      directory: folder, metadata: manifest('hello', [1]),
      chunks: Stream.value([1, 2]), onProgress: (_) {},
    ), throwsFormatException);
    expect(await folder.list().toList(), isEmpty);
  });

  test('cancelling stops a file without leaving partials', () async {
    final bytes = utf8.encode('hello');
    var cancel = false;
    await expectLater(VerifiedFileWriter.receive(
      directory: folder, metadata: manifest('hello', bytes),
      chunks: Stream.fromIterable([bytes.take(2).toList(),
        bytes.skip(2).toList()]),
      onProgress: (_) => cancel = true,
      isCancelled: () => cancel,
    ), throwsA(isA<TransferCancelledException>()));
    expect(await folder.list().toList(), isEmpty);
  });

  test('existing files are not overwritten', () async {
    final old = File(p.join(folder.path, 'photo.jpg'));
    await old.writeAsString('old');
    final bytes = utf8.encode('new file');
    final path = await VerifiedFileWriter.receive(
      directory: folder, metadata: manifest('photo.jpg', bytes),
      chunks: Stream.value(bytes), onProgress: (_) {},
    );
    expect(await old.readAsString(), 'old');
    expect(p.basename(path), 'photo (1).jpg');
    expect(await File(path).readAsBytes(), bytes);
  });

  test('zero byte files are valid', () async {
    final path = await VerifiedFileWriter.receive(
      directory: folder, metadata: manifest('empty.txt', []),
      chunks: const Stream<List<int>>.empty(), onProgress: (_) {},
    );
    expect(await File(path).length(), 0);
  });
}

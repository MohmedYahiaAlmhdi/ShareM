import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/received_file_catalog.dart';

void main() {
  final date = DateTime.utc(2026, 11, 11);
  final files = [
    ReceivedFileRecord(path: '/files/z.JPG', sizeBytes: 50,
      modified: date),
    ReceivedFileRecord(path: '/files/b.MP4', sizeBytes: 200,
      modified: date.subtract(const Duration(days: 1))),
    ReceivedFileRecord(path: '/files/a.pdf', sizeBytes: 100,
      modified: date.add(const Duration(days: 1))),
    ReceivedFileRecord(path: '/files/c.apk', sizeBytes: 80,
      modified: date),
    ReceivedFileRecord(path: '/files/d.zip', sizeBytes: 150,
      modified: date),
  ];

  test('categorizes common Android file formats case-insensitively', () {
    expect(receivedFileCategory('IMG.HEIC'), ReceivedFileCategory.images);
    expect(receivedFileCategory('video.mkv'), ReceivedFileCategory.videos);
    expect(receivedFileCategory('audio.opus'), ReceivedFileCategory.audio);
    expect(receivedFileCategory('app.APK'), ReceivedFileCategory.apps);
    expect(receivedFileCategory('book.PDF'), ReceivedFileCategory.documents);
    expect(receivedFileCategory('backup.tar.gz'),
      ReceivedFileCategory.archives);
    expect(receivedFileCategory('unknown'), ReceivedFileCategory.other);
  });

  test('filters by name and category without changing original order', () {
    final pictures = filterReceivedFiles(files,
      category: ReceivedFileCategory.images);
    expect(pictures.map((r) => r.name), ['z.JPG']);
    expect(filterReceivedFiles(files, query: ' B.MP4 ').single.name, 'b.MP4');
    expect(files.first.name, 'z.JPG');
    expect(filterReceivedFiles(files,
      category: ReceivedFileCategory.audio), isEmpty);
  });

  test('sorts by modification date, name and size', () {
    expect(filterReceivedFiles(files).first.name, 'a.pdf');
    expect(filterReceivedFiles(files, sort: ReceivedFileSort.oldest)
      .first.name, 'b.MP4');
    expect(filterReceivedFiles(files, sort: ReceivedFileSort.name)
      .first.name, 'a.pdf');
    expect(filterReceivedFiles(files, sort: ReceivedFileSort.largest)
      .first.name, 'b.MP4');
  });

  test('never shows hidden temporary uploads to users', () {
    expect(isUserReceivedFile('.sharem-abc123.part'), isFalse);
    expect(isUserReceivedFile('image.part'), isTrue);
    expect(isUserReceivedFile('report.pdf'), isTrue);
    expect(isUserReceivedFile(''), isFalse);
  });
}

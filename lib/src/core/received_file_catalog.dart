import 'package:path/path.dart' as p;

enum ReceivedFileCategory {
  all, images, videos, audio, documents, archives, apps, other,
}
enum ReceivedFileSort { newest, oldest, name, largest }

class ReceivedFileRecord {
  const ReceivedFileRecord({
    required this.path,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final int sizeBytes;
  final DateTime modified;
  String get name => p.basename(path);
  ReceivedFileCategory get category => receivedFileCategory(name);
}

/// In-progress files are never shown in the received-file gallery.
bool isUserReceivedFile(String name) =>
    name.isNotEmpty &&
    !(name.startsWith('.sharem-') && name.endsWith('.part'));

ReceivedFileCategory receivedFileCategory(String filename) {
  final ext = p.extension(filename).toLowerCase();
  if (const {
    '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif', '.avif',
  }.contains(ext)) return ReceivedFileCategory.images;
  if (const {
    '.mp4', '.mkv', '.mov', '.webm', '.avi', '.3gp', '.m4v',
  }.contains(ext)) return ReceivedFileCategory.videos;
  if (const {
    '.mp3', '.m4a', '.wav', '.aac', '.flac', '.ogg', '.opus', '.amr',
  }.contains(ext)) return ReceivedFileCategory.audio;
  if (const {
    '.apk', '.apks', '.xapk', '.aab',
  }.contains(ext)) return ReceivedFileCategory.apps;
  if (const {
    '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz',
  }.contains(ext)) return ReceivedFileCategory.archives;
  if (const {
    '.pdf', '.txt', '.doc', '.docx', '.odt', '.xls', '.xlsx', '.ppt', '.pptx',
    '.csv', '.json', '.xml', '.epub', '.md', '.html', '.rtf',
  }.contains(ext)) return ReceivedFileCategory.documents;
  return ReceivedFileCategory.other;
}

/// Pure, deterministic filtering / sorting so browsing can be unit-tested.
List<ReceivedFileRecord> filterReceivedFiles(
  Iterable<ReceivedFileRecord> files, {
  String query = '',
  ReceivedFileCategory category = ReceivedFileCategory.all,
  ReceivedFileSort sort = ReceivedFileSort.newest,
}) {
  final search = query.trim().toLowerCase();
  final matches = files.where((file) =>
    (category == ReceivedFileCategory.all || file.category == category) &&
    file.name.toLowerCase().contains(search)).toList();

  matches.sort((a, b) {
    final delta = switch (sort) {
      ReceivedFileSort.newest => b.modified.compareTo(a.modified),
      ReceivedFileSort.oldest => a.modified.compareTo(b.modified),
      ReceivedFileSort.name =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      ReceivedFileSort.largest => b.sizeBytes.compareTo(a.sizeBytes),
    };
    return delta == 0 ? a.path.compareTo(b.path) : delta;
  });
  return matches;
}

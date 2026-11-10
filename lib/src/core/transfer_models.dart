import 'dart:math';

enum TransferDirection { incoming, outgoing }

enum TransferStatus {
  preparing, waiting, transferring, completed, rejected, failed, cancelled,
}

class NearbyDevice {
  NearbyDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String id;
  final String name;
  final String host;
  final int port;
  DateTime lastSeen;

  String get endpoint => '$host:$port';
}

class FileManifest {
  const FileManifest({
    required this.name,
    required this.size,
    required this.sha256,
  });

  final String name;
  final int size;
  final String sha256;

  Map<String, Object> toJson() => {
    'name': name, 'size': size, 'sha256': sha256,
  };

  static FileManifest fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid file metadata');
    final name = raw['name'];
    final size = raw['size'];
    final hash = raw['sha256'];
    if (name is! String || name.isEmpty || name.length > 255 ||
        size is! int || size < 0 || size > 20 * 1024 * 1024 * 1024 ||
        hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid file descriptor');
    }
    return FileManifest(name: name, size: size, sha256: hash);
  }
}

class TransferEntry {
  TransferEntry({
    required this.id,
    required this.peerName,
    required this.files,
    required this.direction,
    this.status = TransferStatus.preparing,
    this.totalBytes = 0,
    this.doneBytes = 0,
    this.error,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  final String id;
  final String peerName;
  final List<String> files;
  final TransferDirection direction;
  final DateTime date;
  TransferStatus status;
  int totalBytes;
  int doneBytes;
  String? error;
  bool cancellationRequested = false;

  double get progress => totalBytes <= 0
      ? (status == TransferStatus.completed ? 1.0 : 0.0)
      : (doneBytes / totalBytes).clamp(0.0, 1.0).toDouble();

  bool get isRunning => const [
    TransferStatus.preparing, TransferStatus.waiting,
    TransferStatus.transferring,
  ].contains(status);

  Map<String, Object?> toJson() => {
    'id': id,
    'peerName': peerName,
    'files': files,
    'direction': direction.name,
    'status': status.name,
    'totalBytes': totalBytes,
    'doneBytes': doneBytes,
    'date': date.toIso8601String(),
    'error': error,
  };

  static TransferEntry fromJson(Map<String, dynamic> json) => TransferEntry(
    id: json['id'] as String? ?? '',
    peerName: json['peerName'] as String? ?? '',
    files: (json['files'] as List? ?? []).whereType<String>().toList(),
    direction: TransferDirection.values.firstWhere(
      (e) => e.name == json['direction'],
      orElse: () => TransferDirection.incoming,
    ),
    status: TransferStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => TransferStatus.failed,
    ),
    totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
    doneBytes: (json['doneBytes'] as num?)?.toInt() ?? 0,
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    error: json['error'] as String?,
  );
}

class IncomingOffer {
  IncomingOffer({
    required this.id,
    required this.peerName,
    required this.sourceIp,
    required this.files,
  });
  final String id;
  final String peerName;
  final String sourceIp;
  final List<FileManifest> files;
  String status = 'pending';
  String? token;
  int nextIndex = 0;
  DateTime createdAt = DateTime.now();

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

String safeFileName(String original) {
  final leaf = original.split(RegExp(r'[/\\]')).last;
  var result = leaf.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_').trim();
  if (result == '.' || result == '..' || result.isEmpty) result = 'file';
  result = result.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (result.isEmpty) result = 'file';
  if (result.length > 120) result = result.substring(result.length - 120);
  return result;
}

String randomHex([int bytes = 16]) {
  final rng = Random.secure();
  return List<int>.generate(bytes, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  do {
    value /= 1024;
    unit++;
  } while (value >= 1024 && unit < units.length - 1);
  return value.toStringAsFixed(value < 10 ? 1 : 0) + ' ' + units[unit];
}

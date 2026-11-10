class ReleaseApk {
  const ReleaseApk(this.abi, this.url, this.sha256, this.sizeBytes);
  final String abi;
  final Uri url;
  final String sha256;
  final int sizeBytes;

  static ReleaseApk parse(String abi, Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid APK metadata');
    final url = Uri.tryParse(raw['url'] is String ? raw['url'] as String : '');
    final hash = raw['sha256'];
    final size = raw['sizeBytes'];
    if (url == null || url.scheme != 'https' || url.host != 'github.com' ||
        url.userInfo.isNotEmpty || url.hasPort ||
        !url.path.startsWith('/MohmedYahiaAlmhdi/ShareM/releases/download/v') ||
        !url.path.endsWith('.apk') || url.fragment.isNotEmpty ||
        hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        size is! int || size <= 0 || size > 250 * 1024 * 1024) {
      throw const FormatException('Untrusted APK metadata');
    }
    return ReleaseApk(abi, url, hash, size);
  }
}

class ShareMRelease {
  const ShareMRelease(this.version, this.buildNumber, this.notes, this.apks);
  final String version;
  final int buildNumber;
  final String notes;
  final Map<String, ReleaseApk> apks;

  static ShareMRelease parse(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid release manifest');
    final version = raw['version'];
    final number = raw['buildNumber'];
    final notes = raw['notes'];
    final android = raw['android'];
    if (version is! String || !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
        number is! int || number < 1 || notes is! String ||
        notes.length > 2000 || android is! Map) {
      throw const FormatException('Invalid release fields');
    }
    final apks = <String, ReleaseApk>{};
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      if (!android.containsKey(abi)) continue;
      final asset = ReleaseApk.parse(abi, android[abi]);
      if (!asset.url.path.contains('/download/v' + version + '/')) {
        throw const FormatException('APK tag does not match version');
      }
      apks[abi] = asset;
    }
    if (apks.isEmpty) throw const FormatException('Missing APKs');
    return ShareMRelease(version, number, notes, apks);
  }

  bool isNewerThan(String current) {
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(current)) return false;
    final a = version.split('.').map(int.parse).toList();
    final b = current.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  ReleaseApk? forAbis(List<String> abis) {
    for (final abi in abis) {
      final apk = apks[abi];
      if (apk != null) return apk;
    }
    return null;
  }
}

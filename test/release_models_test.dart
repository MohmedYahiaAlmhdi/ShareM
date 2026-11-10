import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/release_models.dart';

Map<String, Object> sample({String host = 'github.com', String hash = ''}) => {
  'version': '0.3.0', 'buildNumber': 3,
  'notes': 'New updates',
  'android': {'arm64-v8a': {
    'url': 'https://' + host +
      '/MohmedYahiaAlmhdi/ShareM/releases/download/v0.3.0/ShareM-0.3.0-arm64-v8a.apk',
    'sha256': hash.isEmpty ? 'a' * 64 : hash, 'sizeBytes': 17000000,
  }},
};

void main() {
  test('newer versions and architecture matching', () {
    final m = ShareMRelease.parse(sample());
    expect(m.isNewerThan('0.2.0'), isTrue);
    expect(m.isNewerThan('0.3.0'), isFalse);
    expect(m.isNewerThan('0.10.0'), isFalse);
    expect(m.forAbis(['x86_64', 'arm64-v8a'])!.abi, 'arm64-v8a');
    expect(m.forAbis(['armeabi-v7a']), isNull);
  });
  test('rejects untrusted APK URL and digest', () {
    expect(() => ShareMRelease.parse(sample(host: 'evil.example')), throwsFormatException);
    expect(() => ShareMRelease.parse(sample(hash: 'xyz')), throwsFormatException);
  });
  test('rejects mismatched version tag', () {
    final changed = sample();
    changed['version'] = '0.4.0';
    expect(() => ShareMRelease.parse(changed), throwsFormatException);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sharem/src/core/device_identity.dart';

void main() {
  test('anonymous discovery ID remains unchanged between launches', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = await DeviceIdentity.loadOrCreate(prefs);
    final second = await DeviceIdentity.loadOrCreate(prefs);
    expect(first, second);
    expect(first.length, 32);
    expect(DeviceIdentity.isValid(first), isTrue);
  });

  test('existing valid ID survives upgrade', () async {
    SharedPreferences.setMockInitialValues({
      DeviceIdentity.preferenceKey: 'a' * 32,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(await DeviceIdentity.loadOrCreate(prefs), 'a' * 32);
  });

  test('invalid or damaged IDs are replaced', () async {
    for (final value in ['invalid', '../secret', 'A' * 32, '']) {
      SharedPreferences.setMockInitialValues({
        DeviceIdentity.preferenceKey: value,
      });
      final prefs = await SharedPreferences.getInstance();
      final actual = await DeviceIdentity.loadOrCreate(prefs);
      expect(DeviceIdentity.isValid(actual), isTrue);
      expect(actual, isNot(value));
    }
  });
}

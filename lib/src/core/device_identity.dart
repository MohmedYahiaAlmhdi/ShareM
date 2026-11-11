import 'package:shared_preferences/shared_preferences.dart';

import 'transfer_models.dart';

/// Random app identity, persisted only on this device. This is an anonymous
/// discovery identifier, not an identity certificate or authentication token.
class DeviceIdentity {
  const DeviceIdentity._();
  static const preferenceKey = 'sharem_device_id_v1';
  static final _format = RegExp(r'^[a-f0-9]{32}$');

  static bool isValid(String value) => _format.hasMatch(value);

  static Future<String> loadOrCreate(SharedPreferences prefs) async {
    final stored = prefs.getString(preferenceKey);
    if (stored != null && isValid(stored)) return stored;
    final id = randomHex();
    await prefs.setString(preferenceKey, id);
    return id;
  }
}

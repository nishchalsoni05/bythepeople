import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session token on this device.
class TokenStore {
  static const _key = 'token';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> write(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, token);
    }
  }
}

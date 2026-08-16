import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  const LocalStore();

  Future<String?> getString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      debugPrint('LocalStore.getString failed ($key): $e');
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('LocalStore.setString failed ($key): $e');
    }
  }

  /// Wipes everything this app has stored on the phone. Only account
  /// deletion calls it — "delete my account" has to mean the device copy too.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('LocalStore.clear failed: $e');
    }
  }
}

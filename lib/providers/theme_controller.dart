import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式控制器：管理 跟随系统/浅色/深色，并持久化到本地。
class ThemeController extends ChangeNotifier {
  static const String _prefKey = 'theme_mode';
  static const String _modeSystem = 'system';
  static const String _modeLight = 'light';
  static const String _modeDark = 'dark';

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  ThemeController() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefKey);
      switch (v) {
        case _modeLight:
          _mode = ThemeMode.light;
          break;
        case _modeDark:
          _mode = ThemeMode.dark;
          break;
        default:
          _mode = ThemeMode.system;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final String store;
      switch (mode) {
        case ThemeMode.light:
          store = _modeLight;
          break;
        case ThemeMode.dark:
          store = _modeDark;
          break;
        default:
          store = _modeSystem;
      }
      await prefs.setString(_prefKey, store);
    } catch (_) {}
  }
}

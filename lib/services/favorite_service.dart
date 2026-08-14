import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// 收藏管理（本地持久化，SharedPreferences 存 JSON）
class FavoriteService extends ChangeNotifier {
  static const String _prefsKey = 'favorites';

  final List<SongSearchResult> _favorites = [];
  bool _loaded = false;

  List<SongSearchResult> get favorites => List.unmodifiable(_favorites);
  bool get loaded => _loaded;

  /// 启动时加载一次
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _favorites
          ..clear()
          ..addAll(
            list
                .whereType<Map>()
                .map((e) => SongSearchResult.fromJson(
                    Map<String, dynamic>.from(e as Map))),
          );
      }
    } catch (_) {
      // 解析失败则视为空收藏
    }
    _loaded = true;
    notifyListeners();
  }

  bool isFavorite(MusicPlatform platform, String id) {
    return _favorites
        .any((s) => s.platform == platform && s.id == id);
  }

  /// 切换收藏状态，返回收藏后是否已收藏
  Future<bool> toggle(SongSearchResult song) async {
    final idx = _favorites.indexWhere(
        (s) => s.platform == song.platform && s.id == song.id);
    if (idx >= 0) {
      _favorites.removeAt(idx);
      notifyListeners();
      await _save();
      return false;
    } else {
      _favorites.insert(0, song);
      notifyListeners();
      await _save();
      return true;
    }
  }

  Future<void> remove(MusicPlatform platform, String id) async {
    final idx = _favorites.indexWhere(
        (s) => s.platform == platform && s.id == id);
    if (idx >= 0) {
      _favorites.removeAt(idx);
      notifyListeners();
      await _save();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_favorites.map((s) => s.toJson()).toList()),
    );
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// 我的歌单管理（导入的歌单本地持久化，SharedPreferences 存 JSON）
class PlaylistService extends ChangeNotifier {
  static const String _prefsKey = 'my_playlists';
  static const int maxPlaylists = 50;

  final List<PlaylistInfo> _playlists = [];
  bool _loaded = false;

  List<PlaylistInfo> get playlists => List.unmodifiable(_playlists);
  bool get loaded => _loaded;

  /// 启动时加载一次
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _playlists
          ..clear()
          ..addAll(
            list
                .whereType<Map>()
                .map((e) =>
                    PlaylistInfo.fromStoredJson(Map<String, dynamic>.from(e)))
                .where((p) => p.tracks.isNotEmpty),
          );
      }
    } catch (_) {
      // 解析失败则视为空歌单列表
    }
    _loaded = true;
    notifyListeners();
  }

  /// 添加歌单（同平台同 ID 覆盖旧歌单；超出上限时挤掉最旧的）。
  /// 返回保存后的索引（新歌单置于列表首位）。
  Future<int> add(PlaylistInfo playlist) async {
    final key = _keyOf(playlist);
    _playlists.removeWhere((p) => _keyOf(p) == key);
    _playlists.insert(0, playlist);
    while (_playlists.length > maxPlaylists) {
      _playlists.removeLast();
    }
    notifyListeners();
    await _save();
    return 0;
  }

  /// 按索引删除歌单
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _playlists.length) return;
    _playlists.removeAt(index);
    notifyListeners();
    await _save();
  }

  String _keyOf(PlaylistInfo p) => '${p.platformCode}_${p.id}';

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_playlists.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存歌单失败: $e');
    }
  }
}

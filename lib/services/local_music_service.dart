import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// 本地音乐文件（手机存储中扫描到的音频）
class LocalSong {
  final String path;      // 绝对路径（同时作为队列里的 id）
  final String name;      // 歌名（文件名解析）
  final String artist;    // 歌手（文件名解析，解析不出为 '本地音乐'）
  final String album;
  final int fileSize;

  LocalSong({
    required this.path,
    required this.name,
    required this.artist,
    this.album = '本地音乐',
    required this.fileSize,
  });

  /// 转为统一搜索结果模型（复用播放队列逻辑）
  SongSearchResult toSearchResult() => SongSearchResult(
        platform: MusicPlatform.local,
        id: path,
        name: name,
        artist: artist,
        album: album,
      );
}

/// 本地音乐扫描服务
/// 扫描用户配置的文件夹（默认 Music、Download，可自定义，持久化到
/// SharedPreferences['local_scan_dirs']），返回 LocalSong 列表；
/// 播放走 PlayerProvider 的 local 平台分支，不经 ChKSz 解析、不联网、不缓存。
class LocalMusicService {
  /// 扫描目录持久化 key（JSON 数组，存绝对路径）
  static const String _scanDirsKey = 'local_scan_dirs';

  /// 最多支持的自定义目录数（防止列表无限膨胀）
  static const int maxDirs = 20;

  /// 支持的音频扩展名（与缓存服务白名单一致）
  static const List<String> _audioExts = [
    'mp3', 'flac', 'm4a', 'aac', 'ogg', 'wav', 'ape',
  ];

  /// 小于该大小的文件跳过（过滤铃声/试听碎片）
  static const int _minFileSize = 300 * 1024;

  /// 读取扫描目录列表（绝对路径；未配置时返回默认 Music + Download）
  static Future<List<String>> getScanDirs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scanDirsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    final root = await _storageRoot();
    return ['$root/Music', '$root/Download'];
  }

  /// 保存扫描目录列表
  static Future<void> setScanDirs(List<String> dirs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scanDirsKey, jsonEncode(dirs));
  }

  /// 恢复默认扫描目录
  static Future<void> resetScanDirs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scanDirsKey);
  }

  /// 扫描本地音乐
  /// [dirs] 为绝对路径列表；不传则读取已保存的配置（默认 Music + Download）。
  static Future<List<LocalSong>> scan({List<String>? dirs}) async {
    final roots = dirs ?? await getScanDirs();
    final List<LocalSong> songs = [];
    for (final dirPath in roots) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = entity.path.split('.').last.toLowerCase();
          if (!_audioExts.contains(ext)) continue;
          try {
            final size = await entity.length();
            if (size < _minFileSize) continue;
            songs.add(_fromFile(entity.path, ext, size));
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('扫描 $dirPath 失败: $e');
      }
    }
    songs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return songs;
  }

  /// 从文件路径解析歌名/歌手
  /// 常见命名："歌手 - 歌名.mp3"；无分隔符时歌名 = 文件名，歌手显示为"本地音乐"
  static LocalSong _fromFile(String path, String ext, int size) {
    final base = path.split('/').last;
    final stem = base.substring(0, base.length - ext.length - 1);
    String name = stem;
    String artist = '本地音乐';
    final sep = stem.indexOf(' - ');
    if (sep > 0 && sep < stem.length - 3) {
      artist = stem.substring(0, sep).trim();
      name = stem.substring(sep + 3).trim();
    }
    return LocalSong(
      path: path,
      name: name.isEmpty ? stem : name,
      artist: artist.isEmpty ? '本地音乐' : artist,
      fileSize: size,
    );
  }

  /// 存储根目录（/storage/emulated/0）。
  /// 扫描的是公共存储目录，配合 MANAGE_EXTERNAL_STORAGE 权限 dart:io 可直接读取。
  static Future<String> _storageRoot() async => '/storage/emulated/0';
}

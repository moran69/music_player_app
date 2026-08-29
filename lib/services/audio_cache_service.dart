import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 缓存歌曲信息（用于列表展示）
class CachedSongInfo {
  final String platformCode;
  final String songId;
  final String name;
  final String artist;
  final String filePath;
  final int fileSize;

  CachedSongInfo({
    required this.platformCode,
    required this.songId,
    required this.name,
    required this.artist,
    required this.filePath,
    required this.fileSize,
  });
}

/// 音频缓存服务
/// 播放过的歌曲缓存到本地，下次播放不重新联网下载。
///
/// 缓存目录（可配置，见 settings 的「缓存位置」）：
///   1) 若已授予「所有文件访问」权限：写入公共存储的自定义相对路径
///      （默认 Music/momo —— 系统音乐 App 可扫描到，可通过 cache_base_path 修改；
///       老版本默认 Download/music_player 首次访问时自动整体迁移过来）
///   2) 否则回退到应用私有缓存目录 getApplicationCacheDirectory()/audio_cache/
/// 文件命名: 歌曲名-歌手.ext（特殊字符替换）
/// 元数据索引: <缓存目录>/_index.json（含 lastPlayed 时间戳，用于 LRU 自动清理）
///
/// 缓存上限：cache_limit_bytes（默认 2GB，0 = 不限制），
/// 超限时按最近播放时间从旧到新自动删除（正在播放/刚下载的不清）。
class AudioCacheService {
  static Directory? _cacheDir;
  static Map<String, Map<String, dynamic>>? _index;

  /// 获取缓存目录（延迟初始化）
  /// 优先：公共存储（需 MANAGE_EXTERNAL_STORAGE）；
  ///   - cache_base_path 以 / 开头 → 当作绝对路径直接用（目录选择器返回）
  ///   - 否则 → 拼到存储根 /storage/emulated/0 之后（手输相对路径）
  ///   - 为空 → 默认 /storage/emulated/0/Music/momo
  /// 回退：应用私有缓存目录（保证 App 始终可用）。
  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString('cache_base_path') ?? '').trim();
      final granted = await Permission.manageExternalStorage.isGranted;
      if (!granted) {
        // 未授权，直接走回退（即便配了路径也写不进公共存储）
        throw Exception('no manage_external_storage permission');
      }
      String target;
      if (saved.isEmpty) {
        target = await _defaultCacheDir();
      } else if (saved.startsWith('/')) {
        // 绝对路径（目录选择器返回）
        target = saved;
      } else {
        // 相对路径，拼到存储根
        final rel = saved.replaceAll(RegExp(r'^/+|/+$'), '');
        target = '${await _storageRoot()}/$rel';
      }
      final dir = Directory(target);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    } catch (_) {
      // 继续走回退逻辑
    }
    // 回退：应用私有缓存目录
    try {
      final base = await getApplicationCacheDirectory();
      final dir = Directory('${base.path}/audio_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    } catch (_) {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/audio_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    }
  }

  /// 默认缓存目录：Music/momo（系统音乐 App 能扫描到缓存歌曲）。
  /// 老版本默认在 Download/music_player，若存在则整体迁移（同一存储卷，rename 秒完成）。
  static Future<String> _defaultCacheDir() async {
    final root = await _storageRoot();
    final target = '$root/Music/momo';
    final legacy = '$root/Download/music_player';
    try {
      final legacyDir = Directory(legacy);
      if (await legacyDir.exists() && !await Directory(target).exists()) {
        await Directory('$root/Music').create(recursive: true);
        await legacyDir.rename(target);
        debugPrint('缓存目录已迁移: $legacy -> $target');
      }
    } catch (_) {
      return legacy; // 迁移失败继续用旧目录，保证已有缓存可用
    }
    return target;
  }

  /// 获取手机存储根目录（/storage/emulated/0）
  static Future<String> _storageRoot() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final segs = ext.path.split('/');
        if (segs.length >= 4) {
          return segs.sublist(0, 4).join('/');
        }
        return ext.path;
      }
    } catch (_) {}
    return '/storage/emulated/0';
  }

  /// 直接设置缓存目录为绝对路径（目录选择器调用）
  static Future<void> setCacheDirPath(String absPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_base_path', absPath);
    resetCacheDir();
  }

  /// 重置缓存目录与索引（权限授予或路径变更后调用，下次访问重新解析）
  static void resetCacheDir() {
    _cacheDir = null;
    _index = null;
  }

  /// 获取当前缓存目录绝对路径（用于设置页展示）
  static Future<String> getCacheDirPath() async {
    final dir = await _getCacheDir();
    return dir.path;
  }

  /// 是否已获得「所有文件访问」权限
  static Future<bool> hasStoragePermission() async {
    try {
      return await Permission.manageExternalStorage.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 缓存索引 key
  static String _cacheKey(String platformCode, String songId) =>
      '${platformCode}_$songId';

  /// 从 URL 中提取文件扩展名
  static String _extractExt(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot >= 0 && dot < clean.length - 1) {
      final ext = clean.substring(dot + 1).toLowerCase();
      if (['mp3', 'flac', 'm4a', 'aac', 'ogg', 'wav', 'ape'].contains(ext)) {
        return ext;
      }
    }
    return 'mp3';
  }

  /// 文件名安全化（替换非法字符）
  static String _sanitizeName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 生成缓存文件名: 歌曲名-歌手.ext
  static String _cacheFileName(String name, String artist, String ext) {
    final safeName = _sanitizeName(name);
    final safeArtist = _sanitizeName(artist);
    return '$safeName-$safeArtist.$ext';
  }

  /// 加载缓存索引
  static Future<Map<String, Map<String, dynamic>>> _loadIndex() async {
    if (_index != null) return _index!;
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/_index.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = json.decode(content);
        _index = data.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
      } else {
        _index = {};
      }
    } catch (e) {
      debugPrint('加载缓存索引失败: $e');
      _index = {};
    }
    return _index!;
  }

  /// 保存缓存索引
  static Future<void> _saveIndex() async {
    if (_index == null) return;
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/_index.json');
      await file.writeAsString(json.encode(_index));
    } catch (e) {
      debugPrint('保存缓存索引失败: $e');
    }
  }

  /// 检查指定歌曲是否已有缓存
  static Future<String?> getCachedPath({
    required String platformCode,
    required String songId,
    required String url,
  }) async {
    try {
      final index = await _loadIndex();
      final key = _cacheKey(platformCode, songId);
      final entry = index[key];
      if (entry != null) {
        final filePath = entry['filePath'] as String?;
        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists() && await file.length() > 10240) {
            // 记录最近播放时间（LRU 清理依据）
            entry['lastPlayed'] = DateTime.now().millisecondsSinceEpoch;
            await _saveIndex();
            return filePath;
          }
        }
      }
    } catch (e) {
      debugPrint('检查缓存失败: $e');
    }
    return null;
  }

  /// 下载音频并缓存到本地
  static Future<String?> cacheAudio({
    required String platformCode,
    required String songId,
    required String url,
    String name = '未知歌曲',
    String artist = '未知歌手',
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final index = await _loadIndex();
      final key = _cacheKey(platformCode, songId);

      // 先检查索引中是否已有缓存
      final existing = index[key];
      if (existing != null) {
        final existingPath = existing['filePath'] as String?;
        if (existingPath != null) {
          final file = File(existingPath);
          if (await file.exists() && await file.length() > 10240) {
            return existingPath;
          }
        }
      }

      final ext = _extractExt(url);
      final fileName = _cacheFileName(name, artist, ext);
      final dir2 = await _getCacheDir();
      final path = '${dir2.path}/$fileName';

      // 先下载到临时文件，成功后重命名
      final tempPath = '$path.tmp';
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      final dio = Dio();
      await dio.download(
        url,
        tempPath,
        onReceiveProgress: onProgress,
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      // 下载完成，重命名为正式缓存文件
      if (await tempFile.exists()) {
        final size = await tempFile.length();
        if (size > 10240) {
          // 如果目标文件已存在（同名不同歌曲），加 id 后缀
          String finalPath = path;
          if (await File(path).exists()) {
            finalPath = '${dir2.path}/${_sanitizeName(name)}-${_sanitizeName(artist)}_$songId.$ext';
          }
          await tempFile.rename(finalPath);
          // 更新索引
          index[key] = {
            'name': name,
            'artist': artist,
            'platformCode': platformCode,
            'songId': songId,
            'filePath': finalPath,
            'fileSize': size,
            'lastPlayed': DateTime.now().millisecondsSinceEpoch,
          };
          _index = index;
          await _saveIndex();
          debugPrint('缓存成功: $finalPath ($size bytes)');
          // 超出缓存上限时自动清理旧缓存（不清刚下载的这首）
          await _enforceLimit(excludeKey: key);
          return finalPath;
        } else {
          await tempFile.delete();
        }
      }
    } catch (e) {
      debugPrint('缓存下载失败: $e');
      try {
        final dir = await _getCacheDir();
        final ext = _extractExt(url);
        final fileName = _cacheFileName(name, artist, ext);
        final tempFile = File('${dir.path}/$fileName.tmp');
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
    return null;
  }

  /// 获取缓存总大小（字节）
  static Future<int> getCacheSize() async {
    try {
      final dir = await _getCacheDir();
      int total = 0;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File && !entity.path.endsWith('_index.json')) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      debugPrint('获取缓存大小失败: $e');
      return 0;
    }
  }

  /// 格式化缓存大小为可读字符串
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 获取缓存歌曲数量
  static Future<int> getCacheCount() async {
    try {
      final index = await _loadIndex();
      // 清理无效条目后返回数量
      int count = 0;
      for (final entry in index.values) {
        final filePath = entry['filePath'] as String?;
        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            count++;
          }
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// 获取缓存歌曲列表
  static Future<List<CachedSongInfo>> getCacheList() async {
    try {
      final index = await _loadIndex();
      final List<CachedSongInfo> list = [];
      for (final entry in index.values) {
        final filePath = entry['filePath'] as String?;
        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            final size = await file.length();
            if (size > 10240) {
              list.add(CachedSongInfo(
                platformCode: entry['platformCode'] as String? ?? '',
                songId: entry['songId'] as String? ?? '',
                name: entry['name'] as String? ?? '未知歌曲',
                artist: entry['artist'] as String? ?? '未知歌手',
                filePath: filePath,
                fileSize: size,
              ));
            }
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('获取缓存列表失败: $e');
      return [];
    }
  }

  /// 读取缓存上限（字节）。未设置默认 2GB；0 = 不限制
  static Future<int> getCacheLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('cache_limit_bytes');
      if (v != null) return v;
    } catch (_) {}
    return 2 * 1024 * 1024 * 1024;
  }

  /// 设置缓存上限（字节），0 = 不限制。设置页调用
  static Future<void> setCacheLimit(int bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cache_limit_bytes', bytes);
    // 上限调小后立即触发一次清理
    if (bytes > 0) {
      await _enforceLimit();
    }
  }

  /// 缓存超出上限时，按最近播放时间从旧到新自动删除（LRU）。
  /// [excludeKey] 用于跳过正在播放/刚下载的歌曲。
  static Future<void> _enforceLimit({String? excludeKey}) async {
    try {
      final limit = await getCacheLimit();
      if (limit <= 0) return; // 不限制
      final index = await _loadIndex();

      // 统计仍有效的缓存文件
      final sizes = <String, int>{};
      int total = 0;
      for (final e in index.entries) {
        final filePath = e.value['filePath'] as String?;
        if (filePath == null) continue;
        try {
          final file = File(filePath);
          if (!await file.exists()) continue;
          final size = await file.length();
          sizes[e.key] = size;
          total += size;
        } catch (_) {}
      }
      if (total <= limit) return;

      int lastPlayedOf(String key) {
        final v = index[key]?['lastPlayed'];
        return v is int ? v : 0;
      }

      final keys = sizes.keys.toList()
        ..sort((a, b) => lastPlayedOf(a).compareTo(lastPlayedOf(b)));

      var removed = 0;
      for (final key in keys) {
        if (total <= limit) break;
        if (key == excludeKey) continue;
        final filePath = index[key]?['filePath'] as String?;
        try {
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) await file.delete();
          }
        } catch (_) {}
        total -= sizes[key] ?? 0;
        index.remove(key);
        removed++;
      }
      if (removed > 0) {
        _index = index;
        await _saveIndex();
        debugPrint('缓存超限，已自动清理 $removed 首');
      }
    } catch (e) {
      debugPrint('自动清理缓存失败: $e');
    }
  }

  /// 清除全部缓存
  static Future<void> clearCache() async {
    try {
      final dir = await _getCacheDir();
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          await entity.delete();
        }
      }
      _index = {};
      await _saveIndex();
      debugPrint('缓存已清除');
    } catch (e) {
      debugPrint('清除缓存失败: $e');
    }
  }

  /// 删除指定歌曲的缓存
  static Future<void> removeCache(String platformCode, String songId) async {
    try {
      final index = await _loadIndex();
      final key = _cacheKey(platformCode, songId);
      final entry = index[key];
      if (entry != null) {
        final filePath = entry['filePath'] as String?;
        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        index.remove(key);
        _index = index;
        await _saveIndex();
      }
    } catch (e) {
      debugPrint('删除缓存失败: $e');
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
/// 缓存目录: getApplicationCacheDirectory()/audio_cache/
/// 文件命名: 歌曲名-歌手.ext（特殊字符替换）
/// 元数据索引: audio_cache/_index.json
class AudioCacheService {
  static Directory? _cacheDir;
  static Map<String, Map<String, dynamic>>? _index;

  /// 获取缓存目录（延迟初始化）
  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
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
      final dir = await _getCacheDir();
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
      final path = '${dir.path}/$fileName';

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
            finalPath = '${dir.path}/${_sanitizeName(name)}-${_sanitizeName(artist)}_${songId}.$ext';
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
          };
          _index = index;
          await _saveIndex();
          debugPrint('缓存成功: $finalPath ($size bytes)');
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
      final dir = await _getCacheDir();
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
      final dir = await _getCacheDir();
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

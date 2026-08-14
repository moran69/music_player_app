import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 音频缓存服务
/// 播放过的歌曲缓存到本地，下次播放不重新联网下载。
///
/// 缓存目录: getApplicationCacheDirectory()/audio_cache/
/// 文件命名: {平台code}_{歌曲id}.{ext}
class AudioCacheService {
  static Directory? _cacheDir;

  /// 获取缓存目录（延迟初始化）
  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/audio_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// 从 URL 中提取文件扩展名
  static String _extractExt(String url) {
    // 去掉 query 参数
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot >= 0 && dot < clean.length - 1) {
      final ext = clean.substring(dot + 1).toLowerCase();
      // 只保留合理的音频扩展名
      if (['mp3', 'flac', 'm4a', 'aac', 'ogg', 'wav', 'ape'].contains(ext)) {
        return ext;
      }
    }
    return 'mp3'; // 默认
  }

  /// 生成缓存文件路径
  static Future<String> _cachePath(String platformCode, String songId, String url) async {
    final dir = await _getCacheDir();
    final ext = _extractExt(url);
    return '${dir.path}/${platformCode}_$songId.$ext';
  }

  /// 检查指定歌曲是否已有缓存
  /// [platformCode] 平台代码: 163 / qq / kugou
  /// [songId] 歌曲 ID
  /// [url] 播放地址（用于推断扩展名）
  static Future<String?> getCachedPath({
    required String platformCode,
    required String songId,
    required String url,
  }) async {
    try {
      final path = await _cachePath(platformCode, songId, url);
      final file = File(path);
      if (await file.exists()) {
        // 验证文件大小 > 10KB（防止空文件/损坏文件）
        final size = await file.length();
        if (size > 10240) {
          return path;
        }
      }
    } catch (e) {
      debugPrint('检查缓存失败: $e');
    }
    return null;
  }

  /// 下载音频并缓存到本地
  /// 返回本地文件路径；下载失败返回 null（不影响播放流程）
  static Future<String?> cacheAudio({
    required String platformCode,
    required String songId,
    required String url,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final path = await _cachePath(platformCode, songId, url);
      final file = File(path);

      // 已有缓存且有效，直接返回
      if (await file.exists()) {
        final size = await file.length();
        if (size > 10240) return path;
      }

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
          await tempFile.rename(path);
          debugPrint('缓存成功: $path ($size bytes)');
          return path;
        } else {
          // 文件太小，可能是错误响应
          await tempFile.delete();
        }
      }
    } catch (e) {
      debugPrint('缓存下载失败: $e');
      // 清理可能残留的临时文件
      try {
        final path = await _cachePath(platformCode, songId, url);
        final tempFile = File('$path.tmp');
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
        if (entity is File) {
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
      final dir = await _getCacheDir();
      int count = 0;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
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
      debugPrint('缓存已清除');
    } catch (e) {
      debugPrint('清除缓存失败: $e');
    }
  }

  /// 删除指定歌曲的缓存
  static Future<void> removeCache(String platformCode, String songId) async {
    try {
      final dir = await _getCacheDir();
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('${platformCode}_$songId.')) {
            await entity.delete();
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('删除缓存失败: $e');
    }
  }
}

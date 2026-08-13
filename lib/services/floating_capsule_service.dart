import 'package:flutter/services.dart';

/// 系统悬浮窗胶囊（类灵动岛/华为流体云）原生桥接。
/// 通过 MethodChannel 与 Android 原生悬浮窗通信。
class FloatingCapsuleService {
  static const MethodChannel _channel =
      MethodChannel('music_player/floating_capsule');

  /// 功能开关（设置页控制，持久化在 shared_preferences）
  static bool _enabled = false;

  static bool get enabled => _enabled;

  static void setEnabled(bool value) => _enabled = value;

  /// 原生回调（由 main.dart 注入实现）
  static void Function()? onPlayPauseTap;
  static void Function()? onCapsuleTap;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlayPauseTap':
          onPlayPauseTap?.call();
          break;
        case 'onCapsuleTap':
          onCapsuleTap?.call();
          break;
      }
      return null;
    });
  }

  /// 是否有悬浮窗权限
  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统设置开启悬浮窗权限
  static Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod('openPermissionSettings');
    } catch (_) {}
  }

  /// 显示悬浮胶囊（已显示则更新）
  static Future<void> show({
    required String title,
    required String artist,
    String? coverUrl,
    required bool isPlaying,
  }) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('show', {
        'title': title,
        'artist': artist,
        'coverUrl': coverUrl,
        'isPlaying': isPlaying,
      });
    } catch (_) {}
  }

  /// 更新悬浮胶囊信息
  static Future<void> update({
    required String title,
    required String artist,
    String? coverUrl,
    required bool isPlaying,
  }) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'artist': artist,
        'coverUrl': coverUrl,
        'isPlaying': isPlaying,
      });
    } catch (_) {}
  }

  /// 仅更新播放/暂停状态
  static Future<void> updatePlayState(bool isPlaying) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod('updatePlayState', {'isPlaying': isPlaying});
    } catch (_) {}
  }

  /// 隐藏悬浮胶囊
  static Future<void> hide() async {
    try {
      await _channel.invokeMethod('hide');
    } catch (_) {}
  }
}

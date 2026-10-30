import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使用统计数据（对应服务器 /music-stats/stats 返回）。
class UsageStats {
  final int totalUsers;
  final int todayActive;
  final int onlineNow;

  UsageStats({
    required this.totalUsers,
    required this.todayActive,
    required this.onlineNow,
  });

  factory UsageStats.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }
    return UsageStats(
      totalUsers: toInt(json['total_users']),
      todayActive: toInt(json['today_active']),
      onlineNow: toInt(json['online_now']),
    );
  }
}

/// 使用统计服务：匿名心跳上报 + 拉取统计数据。
///
/// 心跳仅含随机设备 ID + App 版本号，不含任何隐私信息。
/// 全程静默失败：统计服务不可用不影响 App 任何功能。
class UsageStatsService {
  static const String _baseUrl = 'https://momo.7998888.xyz/music-stats';
  static const String _deviceIdKey = 'stats_device_id';

  /// 获取或生成匿名设备 ID（首次运行生成随机 hex 串，持久化）。
  static Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      final rand = Random();
      final hex = List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
      id = 'd-$hex';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// 上报心跳（App 打开/回前台时调用）。
  static Future<void> reportHeartbeat() async {
    try {
      final deviceId = await _getDeviceId();
      final pkg = await PackageInfo.fromPlatform();
      await Dio().post(
        '$_baseUrl/heartbeat',
        data: json.encode({
          'device_id': deviceId,
          'app_version': '${pkg.version}+${pkg.buildNumber}',
        }),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
    } catch (e) {
      debugPrint('统计心跳上报失败（不影响使用）: $e');
    }
  }

  /// 拉取统计数据。失败返回 null（静默失败）。
  static Future<UsageStats?> fetchStats() async {
    try {
      final resp = await Dio().get<Map<String, dynamic>>('$_baseUrl/stats');
      if (resp.statusCode != 200 || resp.data == null) return null;
      return UsageStats.fromJson(resp.data!);
    } catch (e) {
      debugPrint('拉取统计失败: $e');
      return null;
    }
  }
}

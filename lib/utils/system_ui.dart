import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 统一管理系统栏样式（状态栏/底部导航栏）。
/// - 背景透明：露出 App 自身背景（主题背景色 / 播放页封面渐变），避免黑条
/// - 图标亮度：按当前明暗场景切换（深色背景用浅色图标，浅色背景用深色图标）
void applySystemUi({required bool dark}) {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
}

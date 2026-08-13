import 'package:flutter/material.dart';
import '../models/song.dart';

/// 全局配色与主题 —— 简洁标准 Material 风格（支持亮/暗双模式）
class AppColors {
  /// 全局亮暗标志（由 AppTheme.light()/dark() 同步），颜色常量随主题变化
  static bool isDark = false;

  // 主色：标准蓝（Material 默认蓝系），亮暗通用
  static const primary = Color(0xFF2196F3);
  static const primaryDark = Color(0xFF1976D2);

  // 动态色（随 isDark 切换）
  static Color get primarySoft =>
      isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE3F2FD);
  static Color get background =>
      isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
  static Color get surface =>
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get surfaceSoft =>
      isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F6F7);
  static Color get textPrimary =>
      isDark ? const Color(0xFFE8EAED) : const Color(0xFF1F2329);
  static Color get textSecondary =>
      isDark ? const Color(0xFF9AA0A8) : const Color(0xFF646A73);
  static Color get textHint =>
      isDark ? const Color(0xFF6B7075) : const Color(0xFF9AA0A8);
  static Color get cardShadow =>
      isDark ? const Color(0x40000000) : const Color(0x0F000000);
}

/// 平台品牌色
class PlatformColors {
  static const netease = Color(0xFFE84D3D);   // 网易云红
  static const qq = Color(0xFF31C27C);        // QQ 绿
  static const kugou = Color(0xFF2CA2F9);     // 酷狗蓝

  static Color of(MusicPlatform p) {
    switch (p) {
      case MusicPlatform.netease:
        return netease;
      case MusicPlatform.qq:
        return qq;
      case MusicPlatform.kugou:
        return kugou;
    }
  }
}

/// 应用主题（亮/暗双主题；实际生效主题的亮暗标志由 MaterialApp.builder 同步到 AppColors.isDark）
class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: AppColors.primary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'PingFang SC',
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : AppColors.textSecondary,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: TextStyle(color: AppColors.textHint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.surfaceSoft,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}

/// 通用卡片装饰（供各页面复用，颜色随主题动态）
class CardStyle {
  static BoxDecoration softCard() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );
}

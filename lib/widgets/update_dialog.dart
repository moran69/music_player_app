import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// 弹出更新提示对话框（美化版）。
/// [info] 为服务器返回的新版本信息。
void showUpdateDialog(BuildContext context, UpdateInfo info) {
  showDialog(
    context: context,
    barrierDismissible: !info.forceUpdate,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with SingleTickerProviderStateMixin {
  double _progress = 0;
  bool _downloading = false;
  bool _done = false;
  String? _error;

  late final AnimationController _badgeSpin;

  @override
  void initState() {
    super.initState();
    _badgeSpin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _badgeSpin.dispose();
    super.dispose();
  }

  String get _sizeText {
    final mb = widget.info.apkSize / (1024 * 1024);
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${widget.info.apkSize} B';
  }

  /// 把更新日志文本拆成列表项
  List<String> get _changelog {
    final raw = widget.info.updateLog
        .split(RegExp(r'\n|\\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (raw.isNotEmpty) return raw;
    // 若整体是一段没有换行的文本，原样返回
    return widget.info.updateLog.isEmpty
        ? []
        : [widget.info.updateLog];
  }

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final path = await UpdateService.downloadApk(widget.info, (received, total) {
        if (mounted && total > 0) {
          setState(() => _progress = received / total);
        }
      });
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _done = true;
        _progress = 1;
      });
      await UpdateService.installApk(path);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ===== 顶部渐变头部 =====
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2196F3), Color(0xFF1976D2), Color(0xFF42A5F5)],
                    ),
                  ),
                  child: Column(
                    children: [
                      // 旋转徽章图标
                      RotationTransition(
                        turns: _badgeSpin,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.45), width: 2),
                          ),
                          child: const Icon(Icons.system_update_alt_rounded,
                              color: Colors.white, size: 34),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '发现新版本',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 版本号胶囊
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'v${info.versionName} · $_sizeText',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ===== 内容区 =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (info.publishTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.schedule,
                                  size: 14,
                                  color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                info.publishTime,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // 更新日志卡片
                      if (_changelog.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              '更新内容',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: _changelog.map((line) {
                              final text = line.replaceFirst(
                                  RegExp(r'^[\d]+\.\s*'), '');
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 7),
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        text,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          height: 1.5,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      // 下载进度
                      if (_downloading || _done) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 8,
                            backgroundColor:
                                AppColors.primarySoft.withValues(alpha: 0.4),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _done ? '下载完成，正在安装…' : '下载中…',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              '${(_progress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],

                      // 错误
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ===== 底部按钮 =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Row(
                    children: [
                      if (!info.forceUpdate)
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.4)),
                              ),
                              onPressed: _downloading
                                  ? null
                                  : () => Navigator.of(context,
                                          rootNavigator: true)
                                      .pop(),
                              child: Text(
                                '稍后',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      if (!info.forceUpdate) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 46,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: (_downloading || _done) ? null : _start,
                            child: _downloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Text(
                                    '立即更新',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

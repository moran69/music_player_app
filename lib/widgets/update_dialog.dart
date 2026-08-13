import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// 弹出更新提示对话框（仿 momo 的更新体验）。
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

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;

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
    return AlertDialog(
      title: Text('发现新版本 v${info.versionName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.updateLog.isNotEmpty) ...[
                const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(info.updateLog),
                const SizedBox(height: 12),
              ],
              if (_downloading) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text('下载中 ${(_progress * 100).toInt()}%'),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!info.forceUpdate)
          TextButton(
            onPressed: _downloading ? null : () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('稍后'),
          ),
        ElevatedButton(
          onPressed: _downloading ? null : _start,
          child: Text(_downloading ? '下载中…' : '立即更新'),
        ),
      ],
    );
  }
}

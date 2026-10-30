import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 图形化目录选择器
///
/// 从手机存储根目录（/storage/emulated/0）开始逐级浏览，
/// 用户选定一个目录后返回其绝对路径（[String]），取消则返回 null。
///
/// 不依赖第三方包，直接用 dart:io 遍历真实文件系统，
/// 返回的路径可直接用于 Directory/File 写入。
class DirPicker {
  /// 弹出目录选择对话框，返回选中目录的绝对路径或 null
  static Future<String?> pick(BuildContext context,
      {String? initialPath}) async {
    String start;
    try {
      if (initialPath != null && await Directory(initialPath).exists()) {
        start = initialPath;
      } else {
        // getExternalStorageDirectory 在 Android 上指向
        // /storage/emulated/0/Android/data/<pkg>/files
        // 取其 /storage/emulated/0 段作为存储根
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          // 截到第 3 个斜杠：/storage/emulated/0
          final segs = ext.path.split('/');
          start = segs.length >= 4 ? segs.sublist(0, 4).join('/') : ext.path;
        } else {
          start = '/';
        }
      }
    } catch (_) {
      start = '/';
    }

    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DirPickerDialog(initialPath: start),
    );
  }
}

class _DirPickerDialog extends StatefulWidget {
  final String initialPath;
  const _DirPickerDialog({required this.initialPath});

  @override
  State<_DirPickerDialog> createState() => _DirPickerDialogState();
}

class _DirPickerDialogState extends State<_DirPickerDialog> {
  late String _current;
  List<FileSystemEntity> _dirs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPath;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(_current);
      if (!await dir.exists()) {
        setState(() {
          _error = '目录不存在';
          _loading = false;
        });
        return;
      }
      final entities = await dir.list().toList();
      entities.sort((a, b) {
        final an = _baseName(a.path).toLowerCase();
        final bn = _baseName(b.path).toLowerCase();
        return an.compareTo(bn);
      });
      // 仅显示子目录（隐藏 Android 系统约定俗成的点开头目录）
      final onlyDirs =
          entities.whereType<Directory>().toList();
      setState(() {
        _dirs = onlyDirs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '无法读取：$e';
        _loading = false;
      });
    }
  }

  String _baseName(String p) => p.split('/').last;

  Future<void> _enter(String sub) async {
    _current = sub;
    await _load();
  }

  Future<void> _up() async {
    final segs = _current.split('/');
    if (segs.length <= 1) return;
    // 不越过存储根 /storage/emulated/0（保持 4 段）
    if (segs.length <= 4) return;
    segs.removeLast();
    _current = segs.join('/');
    if (!_current.startsWith('/')) _current = '/$_current';
    await _load();
  }

  Future<void> _newFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final newDir = Directory('$_current/$name');
      await newDir.create(recursive: true);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, size: 22),
                  const SizedBox(width: 8),
                  const Text('选择缓存目录',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 当前路径 + 返回上级
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    tooltip: '返回上级',
                    onPressed: _loading ? null : _up,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _current,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 目录列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _dirs.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('此目录下没有子文件夹',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _dirs.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final d = _dirs[i];
                                final name = _baseName(d.path);
                                return ListTile(
                                  leading:
                                      const Icon(Icons.folder, color: Colors.amber),
                                  title: Text(name),
                                  dense: true,
                                  trailing: const Icon(
                                      Icons.chevron_right, size: 20),
                                  onTap: () => _enter(d.path),
                                );
                              },
                            ),
            ),
            // 底部操作栏
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _newFolder,
                    icon: const Icon(Icons.create_new_folder, size: 20),
                    label: const Text('新建文件夹'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _current),
                    icon: const Icon(Icons.check),
                    label: const Text('选此目录'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

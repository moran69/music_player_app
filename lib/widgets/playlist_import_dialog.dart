import 'package:flutter/material.dart';
import '../models/song.dart';

/// 歌单导入对话框（支持网易云 / QQ音乐）
class PlaylistImportDialog extends StatefulWidget {
  final void Function(MusicPlatform platform, String id) onImport;

  const PlaylistImportDialog({super.key, required this.onImport});

  @override
  State<PlaylistImportDialog> createState() => _PlaylistImportDialogState();
}

class _PlaylistImportDialogState extends State<PlaylistImportDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  MusicPlatform _platform = MusicPlatform.netease;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 从链接或纯 ID 中提取歌单 ID
  String _extractId(String input) {
    final t = input.trim();
    final m = RegExp(r'\d{5,}').firstMatch(t);
    return m?.group(0) ?? t;
  }

  @override
  Widget build(BuildContext context) {
    final isQQ = _platform == MusicPlatform.qq;
    return AlertDialog(
      title: const Text('导入歌单'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<MusicPlatform>(
              segments: const [
                ButtonSegment(
                  value: MusicPlatform.netease,
                  label: Text('网易云'),
                  icon: Icon(Icons.music_note),
                ),
                ButtonSegment(
                  value: MusicPlatform.qq,
                  label: Text('QQ音乐'),
                  icon: Icon(Icons.headphones),
                ),
              ],
              selected: {_platform},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _platform = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isQQ
                  ? '输入 QQ 歌单链接或 ID\n如: https://y.qq.com/n/ryqq/playlist/8912082986'
                  : '输入网易云歌单 ID\n如: 5202687076',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: isQQ ? 'QQ 歌单链接 / ID' : '歌单 ID',
                border: const OutlineInputBorder(),
                hintText: isQQ ? '粘贴链接或输入 ID' : '例如: 5202687076',
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入歌单 ID 或链接';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final id = _extractId(_controller.text);
              if (id.isEmpty) return;
              Navigator.pop(context);
              widget.onImport(_platform, id);
            }
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}

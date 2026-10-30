import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/audio_cache_service.dart' show AudioCacheService;
import '../services/local_music_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dir_picker.dart';

/// 本地音乐页：扫描手机存储中的音频文件（目录可自定义），点击即播
class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  List<LocalSong> _songs = [];
  List<String> _dirs = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final dirs = await LocalMusicService.getScanDirs();
      final songs = await LocalMusicService.scan(dirs: dirs);
      if (mounted) {
        setState(() {
          _dirs = dirs;
          _songs = songs;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '扫描失败：请确认已授予「所有文件访问」权限（设置 → 缓存位置）');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// 添加自定义扫描目录（可视化目录选择器）
  Future<void> _addDir() async {
    if (_dirs.length >= LocalMusicService.maxDirs) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('最多添加 ${LocalMusicService.maxDirs} 个目录'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final picked = await DirPicker.pick(
      context,
      initialPath: _dirs.isNotEmpty ? _dirs.first : '/storage/emulated/0',
    );
    if (picked == null) return;
    if (_dirs.contains(picked)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该目录已在扫描列表中'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    await LocalMusicService.setScanDirs([..._dirs, picked]);
    _scan();
  }

  /// 删除扫描目录（默认目录删除后恢复出厂列表时也可用「恢复默认」）
  Future<void> _removeDir(String dir) async {
    final dirs = _dirs.where((d) => d != dir).toList();
    if (dirs.isEmpty) {
      await LocalMusicService.resetScanDirs();
    } else {
      await LocalMusicService.setScanDirs(dirs);
    }
    _scan();
  }

  /// 恢复默认扫描目录（Music + Download）
  Future<void> _resetDirs() async {
    await LocalMusicService.resetScanDirs();
    _scan();
  }

  void _play(int index) {
    final results = _songs.map((s) => s.toSearchResult()).toList();
    context.read<PlayerProvider>().playFromSearchResults(results, index);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地音乐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在扫描 ${_dirs.isEmpty ? 'Music / Download' : '${_dirs.length} 个目录'}…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_outlined, size: 48, color: AppColors.textHint),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh),
                label: const Text('重新扫描'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        // 扫描目录管理
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_open, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('扫描目录（${_dirs.length}）',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  const Spacer(),
                  if (_dirs.isNotEmpty)
                    TextButton(
                      onPressed: _resetDirs,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: [
                  for (final dir in _dirs)
                    InputChip(
                      label: Text(
                        dir.split('/').last,
                        style: const TextStyle(fontSize: 12),
                      ),
                      tooltip: dir,
                      onDeleted: () => _removeDir(dir),
                      deleteIconColor: AppColors.textHint,
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('添加目录', style: TextStyle(fontSize: 12)),
                    onPressed: _addDir,
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
        if (_songs.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_off_outlined, size: 48, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    Text('所选目录中未找到音频文件（MP3/FLAC/M4A 等）\n点「添加目录」选择存放音乐的文件夹',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新扫描'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          // 摘要 + 全部播放
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '共 ${_songs.length} 首 · ${AudioCacheService.formatSize(_songs.fold<int>(0, (s, x) => s + x.fileSize))}',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _play(0),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('全部播放'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _songs.length,
              itemBuilder: (context, i) {
                final song = _songs[i];
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.music_note, color: AppColors.primary),
                  ),
                  title: Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${song.artist} · ${song.path.split('.').last.toUpperCase()} · ${AudioCacheService.formatSize(song.fileSize)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => _play(i),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

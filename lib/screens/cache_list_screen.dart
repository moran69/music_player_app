import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../services/audio_cache_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';

class CacheListScreen extends StatefulWidget {
  const CacheListScreen({super.key});

  @override
  State<CacheListScreen> createState() => _CacheListScreenState();
}

class _CacheListScreenState extends State<CacheListScreen> {
  List<CachedSongInfo> _cacheList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheList();
  }

  Future<void> _loadCacheList() async {
    setState(() => _loading = true);
    try {
      final list = await AudioCacheService.getCacheList();
      if (mounted) setState(() => _cacheList = list);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _removeCache(CachedSongInfo info) async {
    await AudioCacheService.removeCache(info.platformCode, info.songId);
    _loadCacheList();
  }

  Future<void> _playFromCache(CachedSongInfo info) async {
    final player = context.read<PlayerProvider>();
    // 通过平台和 ID 搜索歌曲后播放
    final platform = MusicPlatform.values.firstWhere(
      (e) => e.code == info.platformCode,
      orElse: () => MusicPlatform.netease,
    );
    // 直接用缓存文件路径播放
    final item = PlayQueueItem(
      platform: platform,
      id: info.songId,
      name: info.name,
      artist: info.artist,
      album: '',
    );
    player.playSingle(SongSearchResult(
      platform: platform,
      id: info.songId,
      name: info.name,
      artist: info.artist,
      album: '',
    ));
  }

  Future<void> _clearAllCache() async {
    final totalSize = await AudioCacheService.getCacheSize();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部缓存'),
        content: Text(
          '将删除 ${_cacheList.length} 首已缓存歌曲'
          '（${AudioCacheService.formatSize(totalSize)}），'
          '下次播放需重新联网。是否继续？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true) return;

    await AudioCacheService.clearCache();
    _loadCacheList();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清除'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = _cacheList.fold<int>(0, (sum, e) => sum + e.fileSize);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
                    ),
                  ),
                  Text(
                    '已缓存歌曲',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (_cacheList.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAllCache,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      label: const Text('清除'),
                    ),
                ],
              ),
            ),
            // 统计信息
            if (_cacheList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_cacheList.length} 首 · ${AudioCacheService.formatSize(totalSize)}',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ),
            // 歌曲列表
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    )
                  : _cacheList.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _cacheList.length,
                          itemBuilder: (ctx, i) {
                            final info = _cacheList[i];
                            final platform = MusicPlatform.values.firstWhere(
                              (e) => e.code == info.platformCode,
                              orElse: () => MusicPlatform.netease,
                            );
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  color: PlatformColors.of(platform).withOpacity(0.12),
                                  child: Icon(
                                    Icons.music_note,
                                    size: 24,
                                    color: PlatformColors.of(platform),
                                  ),
                                ),
                              ),
                              title: Text(
                                info.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '${platform.label} · ${info.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    AudioCacheService.formatSize(info.fileSize),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 20, color: AppColors.textHint),
                                    onPressed: () => _removeCache(info),
                                  ),
                                ],
                              ),
                              onTap: () => _playFromCache(info),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      // 底部迷你播放器
      bottomNavigationBar: const SafeArea(
        top: false,
        child: MiniPlayer(),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cached, size: 36, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有缓存歌曲',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '播放过的歌曲会自动缓存到本地',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

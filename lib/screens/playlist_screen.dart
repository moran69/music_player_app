import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/playlist_import_dialog.dart';
import '../widgets/smart_cover.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _loadPlaylist(MusicPlatform platform, String id) async {
    // QQ 歌单走 jsososo 代理，无需 API Key；网易云歌单解析需要 ChKSz Key
    if (platform == MusicPlatform.netease &&
        context.read<PlayerProvider>().apiKey.isEmpty) {
      setState(() => _error = '导入网易云歌单需要先在设置中配置 API Key');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final playlist = platform == MusicPlatform.qq
          ? await context.read<PlayerProvider>().api.qqPlaylist(id)
          : await context.read<PlayerProvider>().api.neteasePlaylist(id);
      // 导入成功：保存到本地歌单列表（同平台同 ID 自动覆盖旧版）
      await context.read<PlaylistService>().add(playlist);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmRemove(BuildContext ctx, int index) async {
    final service = ctx.read<PlaylistService>();
    final playlist = service.playlists[index];
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除「${playlist.name}」吗？\n（不会删除已收藏的歌曲）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.removeAt(index);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('歌单已删除'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题 + 导入按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '我的歌单',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => PlaylistImportDialog(
                          onImport: (platform, id) => _loadPlaylist(platform, id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('导入'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    )
                  : Consumer<PlaylistService>(
                      builder: (context, service, _) {
                        if (service.playlists.isEmpty) {
                          return _buildEmpty();
                        }
                        return _buildPlaylistList(service);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistList(PlaylistService service) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: service.playlists.length,
      itemBuilder: (ctx, i) {
        final p = service.playlists[i];
        return _buildPlaylistCard(ctx, service, i, p);
      },
    );
  }

  Widget _buildPlaylistCard(
      BuildContext ctx, PlaylistService service, int index, PlaylistInfo p) {
    final platformLabel = p.platformCode == 'qq' ? 'QQ' : '网易云';
    final platformColor =
        p.platformCode == 'qq' ? PlatformColors.qq : PlatformColors.netease;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: CardStyle.softCard(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: () => _openPlaylistDetail(ctx, p),
        onLongPress: () => _confirmRemove(ctx, index),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: p.coverUrl != null && p.coverUrl!.isNotEmpty
                ? SmartCover(
                    url: p.coverUrl,
                    fit: BoxFit.cover,
                    placeholder: () => _coverPlaceholder(),
                  )
                : _coverPlaceholder(),
          ),
        ),
        title: Text(
          p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  platformLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: platformColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${p.tracks.length} 首',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline,
              size: 20, color: AppColors.textSecondary),
          tooltip: '删除歌单',
          onPressed: () => _confirmRemove(ctx, index),
        ),
      ),
    );
  }

  void _openPlaylistDetail(BuildContext ctx, PlaylistInfo playlist) {
    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: playlist)),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: AppColors.primarySoft,
      child: const Icon(Icons.playlist_play, size: 28, color: AppColors.primary),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.playlist_play, size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            '导入网易云 / QQ 音乐歌单',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '支持粘贴歌单链接或输入 ID，一键导入全部歌曲\n导入后的歌单保存在本地，长按可删除',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 歌单详情页：展示歌单内歌曲，支持播放全部 / 加入队列
class PlaylistDetailPage extends StatelessWidget {
  final PlaylistInfo playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildTrackList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: CardStyle.softCard(),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 92,
              height: 92,
              child: playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty
                  ? SmartCover(
                      url: playlist.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: () => _coverPlaceholder(),
                    )
                  : _coverPlaceholder(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (playlist.creator != null) ...[
                  Text(
                    'by ${playlist.creator}',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${playlist.tracks.length} 首',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () {
              if (playlist.tracks.isNotEmpty) {
                context.read<PlayerProvider>().playFromPlaylist(playlist.tracks, 0);
              }
            },
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            tooltip: '播放全部',
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: playlist.tracks.length,
      itemBuilder: (ctx, i) {
        final track = playlist.tracks[i];
        return SongTile(
          song: track,
          onTap: () {
            context.read<PlayerProvider>().playFromPlaylist(playlist.tracks, i);
          },
          onAddToQueue: () {
            context.read<PlayerProvider>().addToQueue(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已添加: ${track.name}'), duration: const Duration(seconds: 1)),
            );
          },
        );
      },
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: AppColors.primarySoft,
      child: const Icon(Icons.playlist_play, size: 40, color: AppColors.primary),
    );
  }
}

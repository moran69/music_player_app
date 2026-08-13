import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
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
  PlaylistInfo? _playlist;
  bool _loading = false;
  String? _error;
  MusicPlatform _platform = MusicPlatform.netease;

  Future<void> _loadPlaylist(MusicPlatform platform, String id) async {
    final player = context.read<PlayerProvider>();
    if (player.apiKey.isEmpty) {
      setState(() {
        _error = '请先在设置中配置 API Key';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _platform = platform;
    });

    try {
      final playlist = platform == MusicPlatform.qq
          ? await player.api.qqPlaylist(id)
          : await player.api.neteasePlaylist(id);
      setState(() {
        _playlist = playlist;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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

            // 歌单信息
            if (_playlist != null) _buildPlaylistHeader(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
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
                  : _playlist == null
                      ? _buildEmpty()
                      : _buildTrackList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistHeader() {
    final p = _playlist!;
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
              child: p.coverUrl != null && p.coverUrl!.isNotEmpty
                  ? SmartCover(
                      url: p.coverUrl,
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
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (p.creator != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'by ${p.creator}',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${p.trackCount} 首',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () {
              if (_playlist!.tracks.isNotEmpty) {
                context.read<PlayerProvider>().playFromPlaylist(_playlist!.tracks, 0);
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

  Widget _coverPlaceholder() {
    return Container(
      color: AppColors.primarySoft,
      child: Icon(Icons.playlist_play, size: 40, color: AppColors.primary),
    );
  }

  Widget _buildTrackList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _playlist!.tracks.length,
      itemBuilder: (ctx, i) {
        final track = _playlist!.tracks[i];
        return SongTile(
          song: track,
          onTap: () {
            context.read<PlayerProvider>().playFromPlaylist(_playlist!.tracks, i);
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
            child: Icon(Icons.playlist_play, size: 44, color: AppColors.primary),
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
            '支持粘贴歌单链接或输入 ID，一键导入全部歌曲',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

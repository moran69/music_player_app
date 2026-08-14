import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import '../widgets/smart_cover.dart';

/// 歌单详情页（支持网易云 / QQ音乐）
class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistInfo playlist;
  final MusicPlatform platform;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.platform,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  PlaylistInfo? _detail;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<PlayerProvider>().api;
      PlaylistInfo result;
      if (widget.platform == MusicPlatform.netease) {
        result = await api.neteasePlaylist(widget.playlist.id);
      } else if (widget.platform == MusicPlatform.qq) {
        result = await api.qqPlaylist(widget.playlist.id);
      } else if (widget.platform == MusicPlatform.kugou) {
        final detail = await api.kugouPlaylist(widget.playlist.id);
        // 酷狗详情接口不带歌单名/封面，用传入的信息补齐
        result = PlaylistInfo(
          id: widget.playlist.id,
          name: widget.playlist.name,
          coverUrl: widget.playlist.coverUrl,
          creator: widget.playlist.creator,
          trackCount: detail.trackCount,
          tracks: detail.tracks,
        );
      } else {
        result = widget.playlist;
      }
      if (mounted) setState(() => _detail = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _detail ?? widget.playlist;
    final platformColor = PlatformColors.of(widget.platform);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 头部渐变区
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    platformColor.withOpacity(0.15),
                    AppColors.background,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: p.coverUrl != null && p.coverUrl!.isNotEmpty
                            ? SmartCover(
                                url: p.coverUrl,
                                fit: BoxFit.cover,
                                placeholder: () => _coverPlaceholder(platformColor),
                              )
                            : _coverPlaceholder(platformColor),
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
                              fontSize: 17,
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
                    if (_detail != null && _detail!.tracks.isNotEmpty)
                      IconButton.filled(
                        onPressed: () {
                          context
                              .read<PlayerProvider>()
                              .playFromPlaylist(_detail!.tracks, 0);
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 28),
                        tooltip: '播放全部',
                      ),
                  ],
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
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('加载失败: $_error',
                                  style: const TextStyle(color: Colors.redAccent)),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadDetail,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : _detail == null || _detail!.tracks.isEmpty
                          ? Center(
                              child: Text(
                                '暂无歌曲',
                                style: TextStyle(color: AppColors.textHint),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: _detail!.tracks.length,
                              itemBuilder: (ctx, i) {
                                final track = _detail!.tracks[i];
                                return SongTile(
                                  song: track,
                                  onTap: () {
                                    context
                                        .read<PlayerProvider>()
                                        .playFromPlaylist(_detail!.tracks, i);
                                  },
                                  onAddToQueue: () {
                                    context
                                        .read<PlayerProvider>()
                                        .addToQueue(track);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('已添加: ${track.name}'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      // 底部迷你播放器（与主页面一致，避免子页面播放时无横幅）
      bottomNavigationBar: const SafeArea(
        top: false,
        child: MiniPlayer(),
      ),
    );
  }

  Widget _coverPlaceholder(Color platformColor) {
    return Container(
      color: platformColor.withOpacity(0.12),
      child: Icon(Icons.playlist_play, size: 40, color: platformColor),
    );
  }
}

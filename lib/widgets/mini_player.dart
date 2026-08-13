import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../screens/player_screen.dart';
import '../theme/app_theme.dart';
import 'smart_cover.dart';

/// 迷你播放器（底部悬浮圆角卡片）
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (ctx, player, _) {
        final song = player.currentSong;
        if (song == null) return const SizedBox.shrink();

        final progress = player.duration.inMilliseconds > 0
            ? player.position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        final platformColor = PlatformColors.of(song.platform);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            ).then((_) {
              // 返回时强制刷新
              if (mounted) setState(() {});
            });
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cardShadow,
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: AppColors.primarySoft,
                    valueColor: AlwaysStoppedAnimation<Color>(platformColor),
                  ),
                ),
                // 内容区
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      // 封面
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: song.coverUrl != null && song.coverUrl!.isNotEmpty
                              ? SmartCover(
                                  url: song.coverUrl,
                                  fit: BoxFit.cover,
                                  placeholder: () => _defaultCover(song, platformColor),
                                )
                              : _defaultCover(song, platformColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 歌曲信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${song.platform.label} · ${song.artist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 播放控制
                      if (song.loading)
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      else ...[
                        IconButton(
                          icon: Icon(
                            player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            size: 34,
                            color: AppColors.primary,
                          ),
                          onPressed: player.playPause,
                        ),
                        IconButton(
                          icon: Icon(Icons.skip_next_rounded, size: 26, color: AppColors.textPrimary),
                          onPressed: player.playNext,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _defaultCover(PlayQueueItem song, Color platformColor) {
    return Container(
      color: platformColor.withOpacity(0.12),
      child: Icon(Icons.music_note, size: 20, color: platformColor),
    );
  }
}

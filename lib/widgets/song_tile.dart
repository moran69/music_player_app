import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'smart_cover.dart';

/// 歌曲列表项 Widget（清新风格：圆形封面 + 平台胶囊）
class SongTile extends StatelessWidget {
  final SongSearchResult song;
  final VoidCallback onTap;
  final VoidCallback? onAddToQueue;
  final bool isPlaying;
  final bool showPlatformTag;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onAddToQueue,
    this.isPlaying = false,
    this.showPlatformTag = true,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isCurrent = player.currentSong?.id == song.id && player.currentSong?.platform == song.platform;
    final platformColor = PlatformColors.of(song.platform);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: song.coverUrl != null && song.coverUrl!.isNotEmpty
              ? SmartCover(
                  url: song.coverUrl,
                  fit: BoxFit.cover,
                  placeholder: () => _placeholder(platformColor),
                )
              : _placeholder(platformColor),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? AppColors.primary : AppColors.textPrimary,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
          if (isCurrent && player.isPlaying) ...[
            const SizedBox(width: 8),
            _PlayingIndicator(color: AppColors.primary),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${song.artist} · ${song.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isCurrent ? AppColors.primary.withOpacity(0.7) : AppColors.textSecondary,
          ),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPlatformTag)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: platformColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                song.platform.label,
                style: TextStyle(
                  fontSize: 10,
                  color: platformColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (onAddToQueue != null) ...[
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              iconSize: 20,
              color: AppColors.surface,
              onSelected: (val) {
                if (val == 'add_queue') onAddToQueue!();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'add_queue', child: Text('添加到队列')),
              ],
            ),
          ] else
            Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _placeholder(Color platformColor) {
    return Container(
      color: platformColor.withOpacity(0.12),
      child: Icon(Icons.music_note, color: platformColor, size: 22),
    );
  }
}

/// 播放中的音波动画指示器
class _PlayingIndicator extends StatefulWidget {
  final Color color;
  const _PlayingIndicator({required this.color});

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator> with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final value = ((_controller.value + delay) % 1.0);
            final height = 3.0 + (value * 9);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../services/favorite_service.dart';
import '../theme/app_theme.dart';
import '../utils/color_extractor.dart';
import '../utils/lyric_parser.dart';
import '../utils/system_ui.dart';
import '../widgets/smart_cover.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Color? _dominantColor;
  bool _lyricsAutoScroll = true;
  final ScrollController _lyricScrollController = ScrollController();
  String? _lastColorSongId;

  /// 歌词每行固定高度（与 _buildLyricView 的 SizedBox 保持一致），
  /// 保证滚动偏移计算精确，不会越滚越偏。
  static const double _kLyricLineHeight = 56.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateColor(context.read<PlayerProvider>().currentSong);
    });
  }

  @override
  void dispose() {
    // 离开播放页后恢复全局状态栏样式（跟随主题）
    applySystemUi(dark: AppColors.isDark);
    _lyricScrollController.dispose();
    super.dispose();
  }

  // 仅在歌曲切换时提取一次封面主色（防抖），避免每次重建都跑图像处理
  void _updateColor(PlayQueueItem? song) {
    if (song == null) return;
    final id = '${song.platform}_${song.id}';
    if (id == _lastColorSongId) return;
    _lastColorSongId = id;
    final cover = song.coverUrl;
    if (cover == null || cover.isEmpty) {
      if (_dominantColor != null) setState(() => _dominantColor = null);
      return;
    }
    extractDominantColor(cover).then((color) {
      if (mounted && color != null && id == _lastColorSongId) {
        setState(() => _dominantColor = color);
      }
    });
  }

  void _scrollToLyric(int index) {
    if (!_lyricsAutoScroll) return;
    if (!_lyricScrollController.hasClients) return;
    final position = _lyricScrollController.position;
    // 第 index 行顶部在内容坐标 = topPadding + index*行高；
    // 让它滚到与首行初始位置（topPadding 处）重合，offset = index*行高。
    // 用 jumpTo 瞬时定位，避免 animateTo 300ms 动画在快歌下“追不上”当前行。
    final target =
        (index * _kLyricLineHeight).clamp(0.0, position.maxScrollExtent);
    position.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    // 外层只监听 currentSong：切歌/空态才整体重建；
    // position 每 200ms 的更新不会触发这里，避免整页卡顿。
    return Selector<PlayerProvider, PlayQueueItem?>(
      selector: (_, p) => p.currentSong,
      builder: (ctx, song, _) {
        if (song == null) {
          return _buildEmptyPlayer(ctx);
        }

        final player = context.read<PlayerProvider>();

        // 歌曲切换时更新背景主色（内部已防抖，只处理一次）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateColor(song);
        });

        final baseColor = _dominantColor ?? AppColors.primary;
        final isDark = baseColor.computeLuminance() < 0.5;
        // 状态栏图标跟随播放页背景明暗（深色封面用白色图标，避免状态栏发黑看不清）
        applySystemUi(dark: isDark);
        // 文字颜色：深色背景用白色，浅色背景用深色
        final textColor = isDark ? Colors.white : AppColors.textPrimary;
        final subTextColor = (isDark ? Colors.white : AppColors.textPrimary).withOpacity(0.6);

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  baseColor.withOpacity(0.55),
                  baseColor.withOpacity(0.18),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // 顶部导航
                  _buildTopBar(ctx, player, textColor, subTextColor),
                  // 主内容区：仅监听 showLyric + 当前歌词行，换行才重建
                  Expanded(
                    child: Selector<PlayerProvider, (bool, int)>(
                      selector: (_, p) => (p.showLyric, p.currentLyricIndex),
                      builder: (ctx, sel, _) {
                        if (sel.$1) {
                          // 歌词换行后滚动到当前行
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToLyric(sel.$2);
                          });
                          return _buildLyricView(ctx, player, textColor);
                        }
                        return _buildCoverArt(ctx, player, song, baseColor);
                      },
                    ),
                  ),
                  // 歌曲信息
                  _buildSongInfo(ctx, player, song, textColor, subTextColor),
                  // 进度条
                  _buildProgressBar(ctx, player, textColor, subTextColor),
                  // 播放控制
                  _buildControls(ctx, player, textColor),
                  // 底部功能区
                  _buildBottomActions(ctx, player, subTextColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyPlayer(BuildContext ctx) {
    return Scaffold(
      body: Center(
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
              child: Icon(Icons.music_note, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有播放任何歌曲',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '去搜索你喜欢的音乐吧',
              style: TextStyle(color: AppColors.textHint, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext ctx, PlayerProvider player, Color textColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: textColor),
            onPressed: () => Navigator.pop(ctx),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '正在播放',
                  style: TextStyle(color: subColor, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  player.queue.length > 1
                      ? '播放列表 (${player.currentIndex + 1}/${player.queue.length})'
                      : '单曲播放',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.queue_music, color: textColor),
            onPressed: () => _showQueueSheet(ctx, player),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(BuildContext ctx, PlayerProvider player, PlayQueueItem song, Color baseColor) {
    return GestureDetector(
      onTap: () => player.toggleShowLyric(),
      child: Center(
        child: Container(
          width: 300,
          height: 300,
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: baseColor.withOpacity(0.35),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: song.coverUrl != null && song.coverUrl!.isNotEmpty
                ? SmartCover(
                    url: song.coverUrl,
                    fit: BoxFit.cover,
                    placeholder: () => Container(
                      color: AppColors.primarySoft,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  )
                : _buildDefaultCover(song),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCover(PlayQueueItem song) {
    final color = PlatformColors.of(song.platform);
    return Container(
      color: color.withOpacity(0.15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 80, color: color),
            const SizedBox(height: 12),
            Text(
              song.platform.label,
              style: TextStyle(color: color, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricView(BuildContext ctx, PlayerProvider player, Color textColor) {
    if (player.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_outlined, size: 64, color: textColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              '暂无歌词',
              style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => player.toggleShowLyric(),
      onVerticalDragUpdate: (_) => setState(() => _lyricsAutoScroll = false),
      child: ListView.builder(
        controller: _lyricScrollController,
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(ctx).size.height * 0.35,
          horizontal: 32,
        ),
        itemCount: player.lyrics.length,
        itemBuilder: (ctx, i) {
          final lyric = player.lyrics[i];
          final isCurrent = i == player.currentLyricIndex;
          return GestureDetector(
            onTap: () {
              player.seekTo(lyric.time);
              setState(() => _lyricsAutoScroll = true);
            },
            // 固定行高：保证滚动偏移计算精确，当前行高亮时不改变占位高度
            child: SizedBox(
              height: _kLyricLineHeight,
              child: Center(
                child: Text(
                  lyric.text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? textColor : textColor.withOpacity(0.4),
                    fontSize: isCurrent ? 17 : 14,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongInfo(
    BuildContext ctx,
    PlayerProvider player,
    PlayQueueItem song,
    Color textColor,
    Color subColor,
  ) {
    // 仅监听加载状态与错误信息，避免随播放进度频繁重建
    return Selector<PlayerProvider, (bool, String?)>(
      selector: (_, p) => (p.isLoading, p.errorMessage),
      builder: (ctx, sel, _) {
        final isLoading = sel.$1;
        final errorMessage = sel.$2;
        if (isLoading) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Column(
            children: [
              Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${song.artist} - ${song.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subColor, fontSize: 13),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(BuildContext ctx, PlayerProvider player, Color textColor, Color subColor) {
    // 进度条独立监听 position/duration，只有时间变化才重建这一小块
    return Selector<PlayerProvider, (Duration, Duration)>(
      selector: (_, p) => (p.position, p.duration),
      builder: (ctx, sel, _) {
        final position = sel.$1;
        final duration = sel.$2;
        final total = duration.inMilliseconds.toDouble();
        final pos = position.inMilliseconds.toDouble().clamp(0, total > 0 ? total : 1);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: subColor.withOpacity(0.25),
                  thumbColor: AppColors.primary,
                ),
                child: Slider(
                  value: total > 0 ? pos / total : 0,
                  onChanged: total > 0
                      ? (v) {
                          player.seekTo(Duration(milliseconds: (v * total).toInt()));
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: TextStyle(color: subColor, fontSize: 11),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(color: subColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls(BuildContext ctx, PlayerProvider player, Color textColor) {
    // 仅监听播放状态/模式/歌词开关，避免随播放进度重建
    return Selector<PlayerProvider, (bool, PlayMode, bool)>(
      selector: (_, p) => (p.isPlaying, p.playMode, p.showLyric),
      builder: (ctx, sel, _) {
        final isPlaying = sel.$1;
        final playMode = sel.$2;
        final showLyric = sel.$3;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 播放模式
              IconButton(
                icon: Icon(
                  playMode == PlayMode.sequence
                      ? Icons.repeat_rounded
                      : playMode == PlayMode.repeat
                          ? Icons.repeat_one_rounded
                          : Icons.shuffle_rounded,
                  color: textColor,
                  size: 24,
                ),
                onPressed: player.togglePlayMode,
              ),
              // 上一首
              IconButton(
                icon: Icon(Icons.skip_previous_rounded, color: textColor, size: 42),
                onPressed: player.playPrevious,
              ),
              // 播放/暂停
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                  onPressed: player.playPause,
                ),
              ),
              // 下一首
              IconButton(
                icon: Icon(Icons.skip_next_rounded, color: textColor, size: 42),
                onPressed: player.playNext,
              ),
              // 歌词
              IconButton(
                icon: Icon(
                  Icons.lyrics_rounded,
                  color: showLyric ? AppColors.primary : textColor.withOpacity(0.5),
                  size: 24,
                ),
                onPressed: player.toggleShowLyric,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomActions(BuildContext ctx, PlayerProvider player, Color subColor) {
    // 收藏状态跟随 FavoriteService（点击收藏/取消收藏实时刷新）
    final fav = ctx.watch<FavoriteService>();
    final song = player.currentSong;
    final isFav = song != null && fav.isFavorite(song.platform, song.id);
    return Selector<PlayerProvider, bool>(
      selector: (_, p) => p.showLyric,
      builder: (ctx, showLyric, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () => player.toggleShowLyric(),
                icon: Icon(
                  Icons.text_snippet_rounded,
                  color: showLyric ? AppColors.primary : subColor,
                  size: 20,
                ),
                label: Text(
                  '歌词',
                  style: TextStyle(
                    color: showLyric ? AppColors.primary : subColor,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  if (song == null) return;
                  final added = await fav.toggle(song);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(added ? '已收藏 ♥' : '已取消收藏'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.redAccent : subColor,
                  size: 20,
                ),
                label: Text(
                  isFav ? '已收藏' : '收藏',
                  style: TextStyle(
                    color: isFav ? Colors.redAccent : subColor,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showQueueSheet(ctx, player),
                icon: Icon(Icons.queue_music_rounded, color: subColor, size: 20),
                label: Text('队列', style: TextStyle(color: subColor)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQueueSheet(BuildContext ctx, PlayerProvider player) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                // 拖拽指示条
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '播放队列 (${player.queue.length})',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (player.queue.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            player.clearQueue();
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            '清空',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: player.queue.length,
                    itemBuilder: (ctx, i) {
                      final item = player.queue[i];
                      final isCurrent = i == player.currentIndex;
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                                ? SmartCover(
                                    url: item.coverUrl,
                                    fit: BoxFit.cover,
                                    placeholder: () => Container(
                                      color: AppColors.primarySoft,
                                      child: Icon(Icons.music_note, size: 20, color: AppColors.primary),
                                    ),
                                  )
                                : Container(
                                    color: AppColors.primarySoft,
                                    child: Icon(Icons.music_note, size: 20, color: AppColors.primary),
                                  ),
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? AppColors.primary : AppColors.textPrimary,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${item.platform.label} · ${item.artist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.equalizer_rounded, color: AppColors.primary)
                            : item.loading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                                    onPressed: () => player.removeFromQueue(i),
                                  ),
                        onTap: () => player.playQueueItem(i),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

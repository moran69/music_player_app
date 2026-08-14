import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/favorite_service.dart';
import '../theme/app_theme.dart';
import '../widgets/song_tile.dart';

/// 我的收藏页（本地收藏的歌曲列表）
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    // 确保收藏已加载（幂等）
    context.read<FavoriteService>().load();
  }

  @override
  Widget build(BuildContext context) {
    final fav = context.watch<FavoriteService>();
    final songs = fav.favorites;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        centerTitle: true,
      ),
      body: songs.isEmpty
          ? _buildEmpty()
          : Column(
              children: [
                // 播放全部
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        context
                            .read<PlayerProvider>()
                            .playFromPlaylist(songs, 0);
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('播放全部 (${songs.length})'),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: songs.length,
                    itemBuilder: (ctx, i) {
                      final song = songs[i];
                      return SongTile(
                        song: song,
                        showPlatformTag: false,
                        showFavorite: true,
                        onTap: () {
                          context
                              .read<PlayerProvider>()
                              .playFromPlaylist(songs, i);
                        },
                        onAddToQueue: () {
                          context.read<PlayerProvider>().addToQueue(song);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已添加: ${song.name}'),
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
            child: Icon(
              Icons.favorite_border,
              size: 44,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有收藏任何歌曲',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在播放页点击 ♥ 即可收藏喜欢的音乐',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

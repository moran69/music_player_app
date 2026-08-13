import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/smart_cover.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late TabController _tabController;
  bool _searching = false;
  String _lastKeyword = '';
  bool _playlistMode = false; // true=歌单模式, false=歌曲模式
  List<String> _hotKeywords = ['周杰伦', '海阔天空', '晴天', '邓紫棋', 'Beyond', '告白气球'];

  final Map<MusicPlatform, List<SongSearchResult>> _results = {
    MusicPlatform.netease: [],
    MusicPlatform.qq: [],
    MusicPlatform.kugou: [],
  };

  final Map<MusicPlatform, List<PlaylistInfo>> _playlistResults = {
    MusicPlatform.netease: [],
    MusicPlatform.qq: [],
    MusicPlatform.kugou: [],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final provider = context.read<PlayerProvider>();

    setState(() {
      _searching = true;
      _lastKeyword = keyword;
    });

    if (_playlistMode) {
      // 歌单模式：三平台并行搜索歌单
      setState(() {
        _playlistResults[MusicPlatform.netease] = [];
        _playlistResults[MusicPlatform.qq] = [];
        _playlistResults[MusicPlatform.kugou] = [];
      });
      final futures = <Future>[];
      futures.add(provider.api.neteaseSearchPlaylists(keyword).then((list) {
        if (mounted) setState(() => _playlistResults[MusicPlatform.netease] = list);
      }).catchError((e) => debugPrint('搜索网易云歌单失败: $e')));
      futures.add(provider.api.qqSearchPlaylists(keyword).then((list) {
        if (mounted) setState(() => _playlistResults[MusicPlatform.qq] = list);
      }).catchError((e) => debugPrint('搜索QQ歌单失败: $e')));
      futures.add(provider.api.kugouSearchPlaylists(keyword).then((list) {
        if (mounted) setState(() => _playlistResults[MusicPlatform.kugou] = list);
      }).catchError((e) => debugPrint('搜索酷狗歌单失败: $e')));
      await Future.wait(futures);
    } else {
      // 歌曲模式：并行搜索三平台歌曲 + 相关歌单（混合展示，歌单默认可见）
      setState(() {
        _results[MusicPlatform.netease] = [];
        _results[MusicPlatform.qq] = [];
        _results[MusicPlatform.kugou] = [];
        _playlistResults[MusicPlatform.netease] = [];
        _playlistResults[MusicPlatform.qq] = [];
        _playlistResults[MusicPlatform.kugou] = [];
      });
      final futures = <Future>[];
      for (final platform in MusicPlatform.values) {
        futures.add(
          provider.api.search(platform, keyword).then((list) {
            if (mounted) {
              setState(() {
                _results[platform] = list;
              });
            }
          }).catchError((e) {
            debugPrint('搜索 ${platform.label} 失败: $e');
          }),
        );
      }
      // 相关歌单（默认与单曲一起展示）
      futures.add(provider.api.neteaseSearchPlaylists(keyword).then((list) {
        if (mounted) setState(() => _playlistResults[MusicPlatform.netease] = list);
      }).catchError((e) => debugPrint('搜索网易云歌单失败: $e')));
      futures.add(provider.api.qqSearchPlaylists(keyword).then((list) {
        if (mounted) setState(() => _playlistResults[MusicPlatform.qq] = list);
      }).catchError((e) => debugPrint('搜索QQ歌单失败: $e')));
      futures.add(provider.api.kugouSearchPlaylists(keyword).then((list) {
        if (mounted) setState(() => _playlistResults[MusicPlatform.kugou] = list);
      }).catchError((e) => debugPrint('搜索酷狗歌单失败: $e')));
      await Future.wait(futures);
    }
    if (mounted) setState(() => _searching = false);
  }

  void _switchMode(bool playlistMode) {
    if (_playlistMode == playlistMode) return;
    setState(() => _playlistMode = playlistMode);
    // 已有关键词时立即按新模式搜索
    if (_lastKeyword.isNotEmpty) {
      _search(_lastKeyword);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSearched = _lastKeyword.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text(
                    '搜索',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            // 搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: '搜索歌曲、歌手...',
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 20, color: AppColors.textSecondary),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  hintStyle: TextStyle(color: AppColors.textHint),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                onChanged: (_) => setState(() {}),
              ),
            ),

            // 平台 Tab
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '网易云'),
                Tab(text: 'QQ音乐'),
                Tab(text: '酷狗'),
              ],
            ),
            const SizedBox(height: 4),

            // 搜索结果
            Expanded(
              child: !hasSearched
                  ? _buildWelcome()
                  : _searching && _allResultsEmpty()
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: MusicPlatform.values
                              .map((platform) => _buildPlatformPage(platform))
                              .toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  bool _allResultsEmpty() {
    if (_playlistMode) {
      return _playlistResults.values.every((l) => l.isEmpty);
    }
    return _results.values.every((l) => l.isEmpty);
  }

  /// 单个平台的结果页：歌曲/歌单切换 + 结果列表
  Widget _buildPlatformPage(MusicPlatform platform) {
    return Column(
      children: [
        // 歌曲 / 歌单 切换
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('歌曲')),
                ButtonSegment(value: true, label: Text('歌单')),
              ],
              selected: {_playlistMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _switchMode(s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _playlistMode
              ? _buildPlaylistResults(platform)
              : _buildSongResults(platform),
        ),
      ],
    );
  }

  Widget _buildSongResults(MusicPlatform platform) {
    final list = _results[platform] ?? [];
    final playlists = _playlistResults[platform] ?? [];
    if (list.isEmpty && playlists.isEmpty && _lastKeyword.isNotEmpty && !_searching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              '没有找到结果',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final hasPlaylists = playlists.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: list.length + (hasPlaylists ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (hasPlaylists && i == 0) {
          return _buildRelatedPlaylists(platform, playlists);
        }
        final song = list[i - (hasPlaylists ? 1 : 0)];
        return SongTile(
          song: song,
          onTap: () {
            context.read<PlayerProvider>().playSingle(song);
          },
          onAddToQueue: () {
            context.read<PlayerProvider>().addToQueue(song);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已添加到队列: ${song.name}'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );
      },
    );
  }

  /// 搜索结果顶部的「相关歌单」横滑卡片
  Widget _buildRelatedPlaylists(MusicPlatform platform, List<PlaylistInfo> playlists) {
    final platformColor = PlatformColors.of(platform);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                '相关歌单',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${playlists.length} 个',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                '点击查看 >',
                style: TextStyle(fontSize: 12, color: platformColor),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 124,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            itemBuilder: (ctx, i) {
              final p = playlists[i];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlist: p, platform: platform),
                    ),
                  );
                },
                child: Container(
                  width: 96,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: p.coverUrl != null && p.coverUrl!.isNotEmpty
                              ? SmartCover(
                                  url: p.coverUrl,
                                  fit: BoxFit.cover,
                                  placeholder: () => Container(
                                    color: platformColor.withOpacity(0.12),
                                    child: Icon(Icons.queue_music, size: 30, color: platformColor),
                                  ),
                                )
                              : Container(
                                  color: platformColor.withOpacity(0.12),
                                  child: Icon(Icons.queue_music, size: 30, color: platformColor),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPlaylistResults(MusicPlatform platform) {
    final list = _playlistResults[platform] ?? [];
    if (list.isEmpty && _lastKeyword.isNotEmpty && !_searching) {
      return _buildEmptyHint(Icons.playlist_remove, '没有找到相关歌单');
    }
    final platformColor = PlatformColors.of(platform);
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final p = list[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: p.coverUrl != null && p.coverUrl!.isNotEmpty
                  ? SmartCover(
                      url: p.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: () => Container(
                        color: platformColor.withOpacity(0.12),
                        child: Icon(Icons.queue_music, size: 24, color: platformColor),
                      ),
                    )
                  : Container(
                      color: platformColor.withOpacity(0.12),
                      child: Icon(Icons.queue_music, size: 24, color: platformColor),
                    ),
            ),
          ),
          title: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
          subtitle: Text(
            p.creator != null && p.creator!.isNotEmpty
                ? '${p.creator} · ${p.trackCount} 首'
                : '${p.trackCount} 首',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(playlist: p, platform: platform),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyHint(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 未搜索时的欢迎页 + 热门关键词
  Widget _buildWelcome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            Text(
              '热门搜索',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.local_fire_department, size: 18, color: PlatformColors.netease),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _hotKeywords.map((kw) {
            return GestureDetector(
              onTap: () {
                _controller.text = kw;
                _search(kw);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  kw,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.search, size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                '搜索全网音乐',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '网易云 · QQ音乐 · 酷狗 三大平台同步搜索',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

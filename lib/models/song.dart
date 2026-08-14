/// 音乐平台枚举
enum MusicPlatform {
  netease('网易云', '163'),
  qq('QQ音乐', 'qq'),
  kugou('酷狗', 'kugou');

  final String label;
  final String code;
  const MusicPlatform(this.label, this.code);
}

/// 封面 URL 工具
class CoverHelper {
  /// 网易云封面 URL 统一转 https（接口有时返回 http://）
  static String? normalize(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://')) {
      return 'https://${url.substring(7)}';
    }
    return url;
  }

  /// QQ音乐 albummid -> 专辑封面 CDN URL
  static String? fromQQAlbumMid(String? albummid) {
    if (albummid == null || albummid.isEmpty) return null;
    return 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albummid.jpg';
  }

  /// 酷狗图片模板（含 {size} 占位符）-> 替换为指定尺寸
  static String? fromKugouTemplate(String? template, {int size = 500}) {
    if (template == null || template.isEmpty) return null;
    return template.replaceAll('{size}', '$size');
  }
}

/// 网易云音质等级
enum NeteaseLevel {
  standard('标准', 'standard'),
  exhigh('极高', 'exhigh'),
  lossless('无损', 'lossless'),
  hires('Hi-Res', 'hires'),
  jyeffect('高清环绕', 'jyeffect'),
  sky('超清母带', 'sky'),
  jymaster('高清母带', 'jymaster');

  final String label;
  final String value;
  const NeteaseLevel(this.label, this.value);
}

/// QQ/酷狗音质等级
enum CommonLevel {
  k128('128k', '128k'),
  k320('320k', '320k'),
  flac('无损 FLAC', 'flac'),
  hires('Hi-Res', 'hires'),
  master('母带', 'master');

  final String label;
  final String value;
  const CommonLevel(this.label, this.value);
}

/// 统一歌曲模型（搜索结果）
class SongSearchResult {
  final MusicPlatform platform;
  final String id;       // 网易云: 歌曲ID; QQ: mid; 酷狗: hash id
  final String name;
  final String artist;
  final String album;
  final String? coverUrl;
  final int? duration;   // 秒

  SongSearchResult({
    required this.platform,
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    this.coverUrl,
    this.duration,
  });

  factory SongSearchResult.fromNetease(Map<String, dynamic> json) {
    // API 返回 artists 为字符串或数组，ar 为数组，兼容两种格式
    String artistName = '未知歌手';
    final artistsRaw = json['artists'] ?? json['ar'];
    if (artistsRaw is List && artistsRaw.isNotEmpty) {
      artistName = artistsRaw.map((a) => a is Map ? a['name'] : a.toString()).join(' / ');
    } else if (artistsRaw is String && artistsRaw.isNotEmpty) {
      artistName = artistsRaw;
    }
    // album 可能是 Map 或 String
    String albumName = '';
    final albumRaw = json['album'];
    if (albumRaw is Map) {
      albumName = albumRaw['name'] ?? '';
    } else if (albumRaw is String) {
      albumName = albumRaw;
    }
    final alRaw = json['al'];
    if (albumName.isEmpty && alRaw is Map) {
      albumName = alRaw['name'] ?? '';
    }
    // 封面
    String? coverUrl;
    if (albumRaw is Map) {
      coverUrl = albumRaw['picUrl'];
    }
    if (coverUrl == null && alRaw is Map) {
      coverUrl = alRaw['picUrl'];
    }
    if (coverUrl == null) {
      coverUrl = json['picUrl'];
    }
    return SongSearchResult(
      platform: MusicPlatform.netease,
      id: json['id'].toString(),
      name: json['name'] ?? '未知歌曲',
      artist: artistName,
      album: albumName,
      coverUrl: CoverHelper.normalize(coverUrl),
      duration: json['dt'] ?? json['duration'],
    );
  }

  factory SongSearchResult.fromQQ(Map<String, dynamic> json) {
    return SongSearchResult(
      platform: MusicPlatform.qq,
      id: json['mid'] ?? '',
      name: json['name'] ?? '未知歌曲',
      artist: json['singer'] ?? '未知歌手',
      album: json['album'] ?? '',
      duration: null,
    );
  }

  /// QQ音乐直连API搜索结果 (jsososo /search)
  factory SongSearchResult.fromQQDirect(Map<String, dynamic> json) {
    // singer 可能是数组 [{id, mid, name}] 或字符串
    String artistName = '未知歌手';
    final singer = json['singer'];
    if (singer is List && singer.isNotEmpty) {
      artistName = singer.map((s) => s is Map ? s['name'] : s.toString()).join(' / ');
    } else if (singer is String && singer.isNotEmpty) {
      artistName = singer;
    }
    return SongSearchResult(
      platform: MusicPlatform.qq,
      id: json['songmid'] ?? '',
      name: json['songname'] ?? '未知歌曲',
      artist: artistName,
      album: json['albumname'] ?? '',
      coverUrl: CoverHelper.fromQQAlbumMid(json['albummid']),
      duration: json['interval'] is int ? json['interval'] as int : null,
    );
  }

  factory SongSearchResult.fromKugou(Map<String, dynamic> json) {
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['id'] ?? '',
      name: json['name'] ?? '未知歌曲',
      artist: json['singer'] ?? '未知歌手',
      album: json['album'] ?? '',
      duration: json['duration'] != null
          ? (json['duration'] is int ? json['duration'] as int : int.tryParse(json['duration'].toString()))
          : null,
    );
  }

  /// 酷狗直连API搜索结果 (mixdown /search)
  factory SongSearchResult.fromKugouDirect(Map<String, dynamic> json) {
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['FileHash'] ?? '',
      name: json['SongName'] ?? json['OriSongName'] ?? '未知歌曲',
      artist: json['SingerName'] ?? '未知歌手',
      album: json['AlbumName'] ?? '',
      coverUrl: CoverHelper.fromKugouTemplate(json['Image']),
      duration: json['Duration'] is int ? json['Duration'] as int : null,
    );
  }

  /// 酷狗歌单详情歌曲 (mobilecdn /api/v3/special/song)
  factory SongSearchResult.fromKugouSpecialSong(Map<String, dynamic> json) {
    final filename = (json['filename'] as String?) ?? '';
    // filename 格式: "歌手 - 歌名"（歌名可能含 -，取首个分隔符）
    final sep = filename.indexOf(' - ');
    final name = sep >= 0 ? filename.substring(sep + 3) : filename;
    final artist = sep >= 0 ? filename.substring(0, sep) : '未知歌手';
    // 封面：优先 album_sizable_cover，备选 trans_param.union_cover
    String? coverUrl = CoverHelper.fromKugouTemplate(json['album_sizable_cover']);
    if (coverUrl == null) {
      final transParam = json['trans_param'];
      if (transParam is Map) {
        coverUrl = CoverHelper.fromKugouTemplate(transParam['union_cover']);
      }
    }
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['hash'] ?? '',
      name: name,
      artist: artist,
      album: json['album_name'] ?? '',
      coverUrl: coverUrl,
      duration: json['duration'] is int ? json['duration'] as int : null,
    );
  }

  /// 酷狗新歌速递 (mixdown /top/song)
  factory SongSearchResult.fromKugouNewSong(Map<String, dynamic> json) {
    String artistName = '未知歌手';
    final authors = json['authors'];
    if (authors is List && authors.isNotEmpty) {
      artistName = authors.map((a) => a is Map ? a['author_name'] : a.toString()).join(' / ');
    }
    int? duration;
    final tl = json['timelength'];
    if (tl is int) {
      duration = tl ~/ 1000;
    } else if (tl != null) {
      duration = (int.tryParse(tl.toString()) ?? 0) ~/ 1000;
    }
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['hash'] ?? '',
      name: json['songname'] ?? '未知歌曲',
      artist: artistName,
      album: json['album_name'] ?? '',
      coverUrl: CoverHelper.fromKugouTemplate(json['album_sizable_cover']),
      duration: duration,
    );
  }

  /// 酷狗每日推荐 (mixdown /everyday/recommend)
  factory SongSearchResult.fromKugouRecommend(Map<String, dynamic> json) {
    int? duration;
    final tl = json['timelength'];
    if (tl is int) {
      duration = tl ~/ 1000;
    } else if (tl != null) {
      duration = (int.tryParse(tl.toString()) ?? 0) ~/ 1000;
    }
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['hash'] ?? '',
      name: json['songname'] ?? json['ori_audio_name'] ?? '未知歌曲',
      artist: json['author_name'] ?? '未知歌手',
      album: json['album_name'] ?? json['remark'] ?? '',
      coverUrl: CoverHelper.fromKugouTemplate(json['sizable_cover']),
      duration: duration,
    );
  }

  /// 酷狗官方 mobilecdn 歌曲搜索 (search/song)
  factory SongSearchResult.fromKugouSearchSong(Map<String, dynamic> json) {
    // 封面：搜索接口的封面在 trans_param.union_cover
    String? coverUrl;
    final transParam = json['trans_param'];
    if (transParam is Map) {
      coverUrl = CoverHelper.fromKugouTemplate(transParam['union_cover']);
    }
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['hash'] ?? '',
      name: json['songname'] ?? '未知歌曲',
      artist: json['singername'] ?? '未知歌手',
      album: json['album_name'] ?? '',
      coverUrl: coverUrl,
      duration: json['duration'] is int ? json['duration'] as int : null,
    );
  }

  /// 酷狗官方 mobilecdn 排行榜歌曲 (rank/song)
  factory SongSearchResult.fromKugouRankSong(Map<String, dynamic> json) {
    String artistName = '未知歌手';
    final authors = json['authors'];
    if (authors is List && authors.isNotEmpty) {
      artistName = authors
          .map((a) => a is Map ? a['author_name'] : a.toString())
          .join(' / ');
    }
    if (artistName == '未知歌手' && json['singername'] != null) {
      artistName = json['singername'].toString();
    }
    // 封面：优先 album_sizable_cover，备选 trans_param.union_cover
    String? coverUrl = CoverHelper.fromKugouTemplate(json['album_sizable_cover']);
    if (coverUrl == null) {
      final transParam = json['trans_param'];
      if (transParam is Map) {
        coverUrl = CoverHelper.fromKugouTemplate(transParam['union_cover']);
      }
    }
    return SongSearchResult(
      platform: MusicPlatform.kugou,
      id: json['hash'] ?? '',
      name: json['songname'] ?? '未知歌曲',
      artist: artistName,
      album: json['album_name'] ?? '',
      coverUrl: coverUrl,
      duration: json['duration'] is int ? json['duration'] as int : null,
    );
  }

  /// 从播放队列项构造（收藏用）
  factory SongSearchResult.fromQueueItem(PlayQueueItem item) {
    return SongSearchResult(
      platform: item.platform,
      id: item.id,
      name: item.name,
      artist: item.artist,
      album: item.album,
      coverUrl: item.coverUrl,
      duration: item.duration,
    );
  }

  /// 序列化（收藏本地持久化用）
  Map<String, dynamic> toJson() => {
        'platform': platform.code,
        'id': id,
        'name': name,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'duration': duration,
      };

  /// 反序列化（收藏本地持久化用）
  factory SongSearchResult.fromJson(Map<String, dynamic> json) {
    final platform = MusicPlatform.values.firstWhere(
      (e) => e.code == json['platform'],
      orElse: () => MusicPlatform.netease,
    );
    return SongSearchResult(
      platform: platform,
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未知歌曲',
      artist: json['artist']?.toString() ?? '未知歌手',
      album: json['album']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString(),
      duration: json['duration'] as int?,
    );
  }
}

/// 歌曲详情（含播放地址）
class SongDetail {
  final String name;
  final String artist;
  final String album;
  final String url;
  final String? coverUrl;
  final String? lyric;
  final int? duration; // 秒
  final String? bitrate;
  final String? format;

  SongDetail({
    required this.name,
    required this.artist,
    required this.album,
    required this.url,
    this.coverUrl,
    this.lyric,
    this.duration,
    this.bitrate,
    this.format,
  });

  /// ChKSz 网易云解析结果
  factory SongDetail.fromNetease(Map<String, dynamic> data) {
    return SongDetail(
      name: data['name'] ?? '未知歌曲',
      artist: data['artist'] ?? '未知歌手',
      album: data['album'] ?? '',
      url: data['url'] ?? '',
      coverUrl: data['picUrl'],
      duration: data['size'] != null ? null : null,
      bitrate: data['br']?.toString(),
      format: data['url']?.split('.').last,
    );
  }

  /// 网易云直连API /song/url/v1 返回结果
  factory SongDetail.fromNeteaseUrl(Map<String, dynamic> data) {
    final url = data['url']?.toString() ?? '';
    String? fmt;
    if (url.isNotEmpty) {
      final dot = url.lastIndexOf('.');
      if (dot >= 0 && dot < url.length - 1) fmt = url.substring(dot + 1);
    }
    return SongDetail(
      name: '',
      artist: '',
      album: '',
      url: url,
      coverUrl: null,
      duration: null,
      bitrate: data['br']?.toString(),
      format: fmt,
    );
  }

  factory SongDetail.fromQQ(Map<String, dynamic> json) {
    final interval = json['interval'] as String?;
    int? duration;
    if (interval != null) {
      final parts = interval.split(':');
      if (parts.length == 2) {
        duration = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      }
    }
    return SongDetail(
      name: json['name'] ?? '未知歌曲',
      artist: json['singer'] ?? '未知歌手',
      album: json['album'] ?? '',
      url: json['url'] ?? '',
      coverUrl: json['cover'],
      lyric: json['lrc'],
      duration: duration,
      bitrate: json['bitrate'],
      format: json['format'],
    );
  }

  factory SongDetail.fromKugou(Map<String, dynamic> json) {
    final interval = json['interval'] as String?;
    int? duration;
    if (interval != null) {
      final parts = interval.split(':');
      if (parts.length == 2) {
        duration = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      }
    }
    return SongDetail(
      name: json['name'] ?? '未知歌曲',
      artist: json['singer'] ?? '未知歌手',
      album: json['album'] ?? '',
      url: json['url'] ?? '',
      coverUrl: json['cover'],
      lyric: json['lrc'],
      duration: duration,
      bitrate: json['bitrate'],
      format: json['format'],
    );
  }
}

/// 歌词模型
class LyricData {
  final String? original;   // 原文歌词
  final String? translated; // 翻译歌词
  final String? romaji;     // 罗马音歌词

  LyricData({this.original, this.translated, this.romaji});
}

/// 歌单模型
class PlaylistInfo {
  final String id;
  final String name;
  final String? coverUrl;
  final String? creator;
  final int trackCount;
  final String? description;
  final List<SongSearchResult> tracks;

  PlaylistInfo({
    required this.id,
    required this.name,
    this.coverUrl,
    this.creator,
    required this.trackCount,
    this.description,
    required this.tracks,
  });

  factory PlaylistInfo.fromJson(Map<String, dynamic> data) {
    final tracks = <SongSearchResult>[];
    final trackList = data['tracks'] as List? ?? [];
    for (final t in trackList) {
      tracks.add(SongSearchResult.fromNetease(t));
    }
    return PlaylistInfo(
      id: data['id']?.toString() ?? '',
      name: data['name'] ?? '未知歌单',
      coverUrl: CoverHelper.normalize(data['coverImgUrl'] ?? data['picUrl']),
      creator: data['creator']?['nickname'],
      trackCount: data['trackCount'] ?? tracks.length,
      description: data['description'],
      tracks: tracks,
    );
  }

  /// 网易云热门歌单列表项 (/top/playlist)
  factory PlaylistInfo.fromNeteaseList(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '未知歌单',
      coverUrl: CoverHelper.normalize(json['coverImgUrl']),
      creator: json['creator']?['nickname'],
      trackCount: json['trackCount'] ?? 0,
      tracks: [],
    );
  }

  /// QQ音乐推荐歌单列表项 (/recommend/playlist)
  factory PlaylistInfo.fromQQList(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: json['tid']?.toString() ?? '',
      name: json['title'] ?? '未知歌单',
      coverUrl: json['cover_url_big'] ?? json['cover_url_medium'],
      creator: json['creator_info']?['nick'],
      trackCount: 0,
      tracks: [],
    );
  }

  /// QQ音乐歌单搜索结果 (jsososo /search?t=2)
  factory PlaylistInfo.fromQQSearchList(Map<String, dynamic> json) {
    final creator = json['creator'];
    return PlaylistInfo(
      id: json['dissid']?.toString() ?? '',
      name: json['dissname'] ?? 'QQ歌单',
      coverUrl: CoverHelper.normalize(json['imgurl']),
      creator: creator is Map ? creator['name']?.toString() : null,
      trackCount: json['song_count'] ?? 0,
      tracks: [],
    );
  }

  /// 酷狗歌单搜索结果 (mobilecdn /api/v3/search/special)
  factory PlaylistInfo.fromKugouSearchList(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: json['specialid']?.toString() ?? '',
      name: json['specialname'] ?? '酷狗歌单',
      coverUrl: CoverHelper.normalize(
          CoverHelper.fromKugouTemplate(json['imgurl'], size: 500)),
      creator: json['nickname'],
      trackCount: json['songcount'] ?? 0,
      tracks: [],
    );
  }

  /// QQ音乐歌单详情 (jsososo /songlist)
  factory PlaylistInfo.fromQQDetail(Map<String, dynamic> data) {
    final tracks = <SongSearchResult>[];
    final songlist = data['songlist'] as List? ?? [];
    for (final s in songlist) {
      tracks.add(SongSearchResult.fromQQDirect(s as Map<String, dynamic>));
    }
    return PlaylistInfo(
      id: data['dissid']?.toString() ?? data['dirid']?.toString() ?? '',
      name: data['dissname'] ?? 'QQ歌单',
      coverUrl: data['logo'] ?? data['picurl'],
      creator: data['nick'] ?? data['nickname'],
      trackCount: data['songnum'] ?? tracks.length,
      tracks: tracks,
    );
  }
}

/// 播放队列中的歌曲（包含元信息 + 运行时信息）
class PlayQueueItem {
  final MusicPlatform platform;
  final String id;
  final String name;
  final String artist;
  final String album;
  final String? coverUrl;

  String? playUrl;    // 解析后填充
  String? lyric;      // 歌词
  int? duration;      // 秒
  bool loading;       // 正在解析中
  String? error;      // 解析失败信息

  PlayQueueItem({
    required this.platform,
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    this.coverUrl,
    this.playUrl,
    this.lyric,
    this.duration,
    this.loading = false,
    this.error,
  });

  factory PlayQueueItem.fromSearchResult(SongSearchResult r) {
    return PlayQueueItem(
      platform: r.platform,
      id: r.id,
      name: r.name,
      artist: r.artist,
      album: r.album,
      coverUrl: r.coverUrl,
      duration: r.duration,
    );
  }

  PlayQueueItem copyWith({
    String? playUrl,
    String? lyric,
    int? duration,
    bool? loading,
    String? error,
    String? coverUrl,
  }) {
    return PlayQueueItem(
      platform: platform,
      id: id,
      name: name,
      artist: artist,
      album: album,
      coverUrl: coverUrl ?? this.coverUrl,
      playUrl: playUrl ?? this.playUrl,
      lyric: lyric ?? this.lyric,
      duration: duration ?? this.duration,
      loading: loading ?? this.loading,
      error: error ?? this.error,
    );
  }
}

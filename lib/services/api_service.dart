import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';

/// 音乐 API 服务层
/// - 网易云: http://60.204.152.87:3000 (NeteaseCloudMusicApi)
/// - 酷狗: https://mp3.mixdown.cn (KuGouMusicApi) 搜索/推荐
/// - QQ音乐: http://101.34.65.200:3500 (jsososo) 搜索/推荐
/// - 酷狗/QQ 播放地址解析: ChKSz API 兜底
///
/// 说明：上述直连域名在部分手机网络下不稳定（如 music.126.net 封面、
/// mobilecdn.kugou.com 歌单），故统一经服务器 161.118.252.183 的 nginx
/// 反代中转（/api-netease /api-qq /api-kugou-search /api-kugou）。
class ApiService {
  // ChKSz API (酷狗/QQ 播放地址解析)
  static const String _chkszUrl = 'https://api.chksz.com';
  // API 中转入口（服务器反代到各平台，规避手机直连不稳定）
  static const String neteaseBaseUrl = 'http://161.118.252.183/api-netease';
  static const String kugouBaseUrl = 'http://161.118.252.183/api-kugou';
  static const String kugouSearchBase = 'http://161.118.252.183/api-kugou-search';
  static const String qqBaseUrl = 'http://161.118.252.183/api-qq';

  String apiKey;

  ApiService({required this.apiKey});

  void setApiKey(String key) {
    apiKey = key;
  }

  // ---- ChKSz 请求 ----
  Map<String, String> _chkszQuery(Map<String, dynamic> params) {
    return {
      ...params.map((k, v) => MapEntry(k, v.toString())),
      'apikey': apiKey,
    };
  }

  Future<Map<String, dynamic>> _chkszGet(
      String path, Map<String, dynamic> params) async {
    final uri =
        Uri.parse('$_chkszUrl$path').replace(queryParameters: _chkszQuery(params));
    final res = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    final body = json.decode(res.body);
    if (body is Map<String, dynamic>) {
      if (body['code'] != null && body['code'] != 200) {
        throw ApiException(
            body['code'].toString(), body['msg']?.toString() ?? '请求失败');
      }
      return body;
    }
    return {'data': body};
  }

  // ---- 通用 HTTP GET ----
  Future<Map<String, dynamic>> _httpGet(
      String baseUrl, String path, Map<String, dynamic> params) async {
    final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters:
            params.map((k, v) => MapEntry(k, v.toString())));
    final res = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    return json.decode(res.body) as Map<String, dynamic>;
  }

  // ======================== 网易云 (直连) ========================

  /// 搜索网易云歌曲
  Future<List<SongSearchResult>> neteaseSearch(String keyword,
      {int limit = 30}) async {
    final json =
        await _httpGet(neteaseBaseUrl, '/search', {'keywords': keyword, 'limit': limit});
    final list = json['result']?['songs'] as List? ?? [];
    final songs = list
        .map((e) => SongSearchResult.fromNetease(e as Map<String, dynamic>))
        .toList();
    // 搜索接口不带封面，用 /song/detail 批量补充
    await _fillNeteaseCovers(songs);
    return songs;
  }

  /// 网易云歌单搜索 (/search?type=1000)
  Future<List<PlaylistInfo>> neteaseSearchPlaylists(String keyword,
      {int limit = 20}) async {
    final json = await _httpGet(neteaseBaseUrl, '/search',
        {'keywords': keyword, 'type': 1000, 'limit': limit});
    final list = json['result']?['playlists'] as List? ?? [];
    return list
        .map((e) => PlaylistInfo.fromNeteaseList(e as Map<String, dynamic>))
        .toList();
  }

  /// 批量补充网易云歌曲封面（失败不影响主流程）
  Future<void> _fillNeteaseCovers(List<SongSearchResult> songs) async {
    if (songs.isEmpty) return;
    final missing = songs.where((s) => s.coverUrl == null || s.coverUrl!.isEmpty).toList();
    if (missing.isEmpty) return;
    try {
      final ids = missing.map((s) => s.id).join(',');
      final json = await _httpGet(neteaseBaseUrl, '/song/detail', {'ids': ids});
      final details = json['songs'] as List? ?? [];
      for (final d in details) {
        if (d is! Map<String, dynamic>) continue;
        final id = d['id']?.toString();
        final picUrl = CoverHelper.normalize(d['al']?['picUrl']?.toString());
        if (id == null || picUrl == null) continue;
        final idx = songs.indexWhere((s) => s.id == id);
        if (idx >= 0) {
          songs[idx] = SongSearchResult(
            platform: songs[idx].platform,
            id: songs[idx].id,
            name: songs[idx].name,
            artist: songs[idx].artist,
            album: songs[idx].album,
            coverUrl: picUrl,
            duration: songs[idx].duration,
          );
        }
      }
    } catch (e) {
      // 封面补充失败不影响列表展示
      debugPrint('补网易云封面失败: $e');
    }
  }

  /// 解析网易云歌曲播放地址 (直连 /song/url/v1)，附带专辑封面
  Future<SongDetail> neteaseMusic(String id, {String level = 'exhigh'}) async {
    final json = await _httpGet(
        neteaseBaseUrl, '/song/url/v1', {'id': id, 'level': level});
    final dataArr = json['data'] as List?;
    final data =
        (dataArr != null && dataArr.isNotEmpty) ? dataArr[0] : <String, dynamic>{};
    var detail = SongDetail.fromNeteaseUrl(data as Map<String, dynamic>);
    // 播放时顺便补充封面（保证播放页/迷你播放器有封面）
    if (detail.coverUrl == null || detail.coverUrl!.isEmpty) {
      try {
        final d = await _httpGet(neteaseBaseUrl, '/song/detail', {'ids': id});
        final songsArr = d['songs'] as List? ?? [];
        if (songsArr.isNotEmpty) {
          final cover = CoverHelper.normalize(songsArr[0]['al']?['picUrl']?.toString());
          if (cover != null) {
            detail = SongDetail(
              name: detail.name,
              artist: detail.artist,
              album: detail.album,
              url: detail.url,
              coverUrl: cover,
              duration: detail.duration,
              bitrate: detail.bitrate,
              format: detail.format,
            );
          }
        }
      } catch (e) {
        debugPrint('播放时补封面失败: $e');
      }
    }
    return detail;
  }

  /// 获取网易云歌词
  Future<LyricData> neteaseLyric(String id) async {
    final json = await _httpGet(neteaseBaseUrl, '/lyric', {'id': id});
    return LyricData(
      original: json['lrc']?['lyric'],
      translated: json['tlyric']?['lyric'],
      romaji: json['romalrc']?['lyric'],
    );
  }

  /// 网易云热门歌单
  Future<List<PlaylistInfo>> neteaseHotPlaylists({int limit = 20}) async {
    final json = await _httpGet(
        neteaseBaseUrl, '/top/playlist', {'limit': limit, 'order': 'hot'});
    final list = json['playlists'] as List? ?? [];
    return list
        .map((e) => PlaylistInfo.fromNeteaseList(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取网易云歌单详情
  Future<PlaylistInfo> neteasePlaylist(String id) async {
    final json =
        await _httpGet(neteaseBaseUrl, '/playlist/detail', {'id': id});
    final data = json['playlist'] ?? json;
    final result = PlaylistInfo.fromJson(data as Map<String, dynamic>);
    // 歌单详情曲目也补充封面（部分场景接口可能不带 al.picUrl）
    await _fillNeteaseCovers(result.tracks);
    return result;
  }

  // ======================== 酷狗 (直连搜索/推荐, ChKSz解析) ========================

  /// 搜索酷狗音乐 (mixdown)
  Future<List<SongSearchResult>> kugouSearch(String keyword,
      {int page = 1, int pagesize = 30}) async {
    final json = await _httpGet(kugouBaseUrl, '/search',
        {'keywords': keyword, 'page': page, 'pagesize': pagesize});
    final list = json['data']?['lists'] as List? ?? [];
    return list
        .map((e) => SongSearchResult.fromKugouDirect(e as Map<String, dynamic>))
        .toList();
  }

  /// 酷狗新歌速递
  Future<List<SongSearchResult>> kugouNewSongs(
      {int page = 1, int pagesize = 30}) async {
    final json = await _httpGet(
        kugouBaseUrl, '/top/song', {'page': page, 'pagesize': pagesize});
    final list = json['data'] as List? ?? [];
    return list
        .map((e) => SongSearchResult.fromKugouNewSong(e as Map<String, dynamic>))
        .toList();
  }

  /// 酷狗每日推荐
  Future<List<SongSearchResult>> kugouDailyRecommend() async {
    final json = await _httpGet(kugouBaseUrl, '/everyday/recommend', {});
    final list = json['data']?['song_list'] as List? ?? [];
    return list
        .map((e) => SongSearchResult.fromKugouRecommend(e as Map<String, dynamic>))
        .toList();
  }

  /// 解析酷狗播放地址 (ChKSz 兜底)
  Future<SongDetail> kugouMusic(String hash, {String size = 'flac'}) async {
    final json = await _chkszGet('/api/kugou_music',
        {'id': hash, 'size': size, 'type': 'json'});
    return SongDetail.fromKugou(json);
  }

  // ======================== QQ音乐 (直连搜索/推荐, ChKSz解析) ========================

  /// 搜索QQ音乐 (jsososo)
  Future<List<SongSearchResult>> qqSearch(String keyword) async {
    final json = await _httpGet(qqBaseUrl, '/search', {'key': keyword});
    final list = json['data']?['list'] as List? ?? [];
    return list
        .map((e) => SongSearchResult.fromQQDirect(e as Map<String, dynamic>))
        .toList();
  }

  /// QQ推荐歌单
  Future<List<PlaylistInfo>> qqRecommendPlaylists() async {
    final json = await _httpGet(qqBaseUrl, '/recommend/playlist', {});
    final list = json['data']?['list'] as List? ?? [];
    return list
        .map((e) => PlaylistInfo.fromQQList(e as Map<String, dynamic>))
        .toList();
  }

  /// QQ音乐歌单搜索 (jsososo /search?t=2)
  Future<List<PlaylistInfo>> qqSearchPlaylists(String keyword) async {
    final json = await _httpGet(qqBaseUrl, '/search', {'key': keyword, 't': 2});
    final list = json['data']?['list'] as List? ?? [];
    return list
        .map((e) => PlaylistInfo.fromQQSearchList(e as Map<String, dynamic>))
        .toList();
  }

  /// 酷狗歌单搜索 (mobilecdn /api/v3/search/special)
  Future<List<PlaylistInfo>> kugouSearchPlaylists(String keyword,
      {int page = 1, int pagesize = 20}) async {
    final json = await _httpGet(kugouSearchBase, '/api/v3/search/special',
        {'keyword': keyword, 'page': page, 'pagesize': pagesize});
    final list = json['data']?['info'] as List? ?? [];
    return list
        .map((e) => PlaylistInfo.fromKugouSearchList(e as Map<String, dynamic>))
        .toList();
  }

  /// 酷狗歌单详情 (mobilecdn /api/v3/special/song)
  Future<PlaylistInfo> kugouPlaylist(String specialid,
      {int page = 1, int pagesize = 200}) async {
    final json = await _httpGet(kugouSearchBase, '/api/v3/special/song',
        {'specialid': specialid, 'page': page, 'pagesize': pagesize});
    final list = json['data']?['info'] as List? ?? [];
    final tracks = list
        .map((e) => SongSearchResult.fromKugouSpecialSong(e as Map<String, dynamic>))
        .toList();
    return PlaylistInfo(
      id: specialid,
      name: '酷狗歌单',
      trackCount: tracks.length,
      tracks: tracks,
    );
  }

  /// QQ歌单详情
  Future<PlaylistInfo> qqPlaylist(String tid) async {
    final json = await _httpGet(qqBaseUrl, '/songlist', {'id': tid});
    final data = json['data'] ?? json;
    return PlaylistInfo.fromQQDetail(data as Map<String, dynamic>);
  }

  /// QQ歌词
  Future<LyricData> qqLyric(String songmid) async {
    final json = await _httpGet(qqBaseUrl, '/lyric', {'songmid': songmid});
    final data = json['data'] ?? json;
    return LyricData(
      original: data['lyric'],
      translated: data['trans'],
    );
  }

  /// 解析QQ音乐播放地址 (ChKSz 兜底)
  Future<SongDetail> qqMusic(String mid, {String size = 'flac'}) async {
    final json = await _chkszGet(
        '/api/qq_music', {'mid': mid, 'size': size, 'type': 'json'});
    return SongDetail.fromQQ(json);
  }

  // ======================== 统一接口 ========================

  /// 搜索指定平台歌曲
  Future<List<SongSearchResult>> search(
      MusicPlatform platform, String keyword) {
    switch (platform) {
      case MusicPlatform.netease:
        return neteaseSearch(keyword);
      case MusicPlatform.qq:
        return qqSearch(keyword);
      case MusicPlatform.kugou:
        return kugouSearch(keyword);
    }
  }

  /// 解析播放地址
  Future<SongDetail> resolve(MusicPlatform platform, String id) {
    switch (platform) {
      case MusicPlatform.netease:
        return neteaseMusic(id);
      case MusicPlatform.qq:
        return qqMusic(id);
      case MusicPlatform.kugou:
        return kugouMusic(id);
    }
  }

  /// 获取歌词
  Future<LyricData?> getLyric(MusicPlatform platform, String id) async {
    if (platform == MusicPlatform.netease) {
      return neteaseLyric(id);
    } else if (platform == MusicPlatform.qq) {
      return qqLyric(id);
    }
    // 酷狗歌词随解析接口返回
    return null;
  }
}

class ApiException implements Exception {
  final String code;
  final String message;
  ApiException(this.code, this.message);

  @override
  String toString() => '[$code] $message';
}

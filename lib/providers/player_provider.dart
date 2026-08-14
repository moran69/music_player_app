import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/floating_capsule_service.dart';
import '../utils/lyric_parser.dart';

/// 播放模式
enum PlayMode { sequence, repeat, shuffle }

/// 全局播放器状态管理
class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late ApiService _api;

  // ---- 状态 ----
  List<PlayQueueItem> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  PlayMode _playMode = PlayMode.sequence;
  String? _errorMessage;

  /// 最近一次播放错误（供 UI 弹提示；消费后清空，避免重复弹）
  String? _lastError;

  // 歌词
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = 0;
  bool _showLyric = false;

  // 音质
  NeteaseLevel _neteaseLevel = NeteaseLevel.jymaster;
  CommonLevel _commonLevel = CommonLevel.flac;

  // API Key
  String _apiKey = '';

  // 流订阅
  StreamSubscription? _playerSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _errorSub;

  PlayerProvider() {
    _api = ApiService(apiKey: '');
    _initAudioPlayer();
    _loadSettings();
  }

  // ==================== Getters ====================

  List<PlayQueueItem> get queue => _queue;
  int get currentIndex => _currentIndex;
  PlayQueueItem? get currentSong => _currentIndex >= 0 && _currentIndex < _queue.length ? _queue[_currentIndex] : null;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffered => _buffered;
  PlayMode get playMode => _playMode;
  String? get errorMessage => _errorMessage;
  String? get lastError => _lastError;
  List<LyricLine> get lyrics => _lyrics;
  int get currentLyricIndex => _currentLyricIndex;
  bool get showLyric => _showLyric;
  NeteaseLevel get neteaseLevel => _neteaseLevel;
  CommonLevel get commonLevel => _commonLevel;
  String get apiKey => _apiKey;
  AudioPlayer get audioPlayer => _audioPlayer;
  ApiService get api => _api;

  // ==================== 初始化 ====================

  void _initAudioPlayer() {
    _playerSub = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      // 系统悬浮胶囊同步播放状态
      if (FloatingCapsuleService.enabled) {
        FloatingCapsuleService.updatePlayState(state.playing);
      }
      // 空音频/加载失败保护：加载或解码失败（如 404、空文件、格式不支持）
      // 会触发 playbackEventStream 的 onError（下方 _errorSub 统一处理：停止 + 提示）
      if (state.processingState == ProcessingState.completed) {
        _onSongComplete();
      }
      notifyListeners();
    });

    _durationSub = _audioPlayer.durationStream.listen((d) {
      _duration = d ?? Duration.zero;
      notifyListeners();
    });

    _positionSub = _audioPlayer.positionStream.listen((p) {
      _position = p;
      _updateLyricIndex();
      notifyListeners();
    });

    _bufferSub = _audioPlayer.bufferedPositionStream.listen((b) {
      _buffered = b;
      notifyListeners();
    });

    _errorSub = _audioPlayer.playbackEventStream.listen(
      (_) {},
      onError: (e) {
        // 播放中途出错（解码失败/数据流中断）：停止并提示，避免静默
        _isLoading = false;
        _errorMessage = '播放错误: $e';
        _lastError = '播放出错：音源可能已失效，已停止播放';
        _audioPlayer.stop();
        notifyListeners();
      },
    );
  }

  /// UI 消费完错误后调用，防止重复弹提示
  void consumeError() {
    if (_lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key') ?? '';
    _api.setApiKey(_apiKey);
    final levelStr = prefs.getString('netease_level');
    if (levelStr != null) {
      _neteaseLevel = NeteaseLevel.values.firstWhere(
        (e) => e.value == levelStr,
        orElse: () => NeteaseLevel.jymaster,
      );
    }
    final commonStr = prefs.getString('common_level');
    if (commonStr != null) {
      _commonLevel = CommonLevel.values.firstWhere(
        (e) => e.value == commonStr,
        orElse: () => CommonLevel.flac,
      );
    }
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    _api.setApiKey(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', key);
    notifyListeners();
  }

  Future<void> setNeteaseLevel(NeteaseLevel level) async {
    _neteaseLevel = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('netease_level', level.value);
    notifyListeners();
  }

  Future<void> setCommonLevel(CommonLevel level) async {
    _commonLevel = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('common_level', level.value);
    notifyListeners();
  }

  // ==================== 播放控制 ====================

  /// 从搜索结果播放（替换整个队列）
  Future<void> playFromSearchResults(List<SongSearchResult> results, int index) async {
    _queue = results.map((e) => PlayQueueItem.fromSearchResult(e)).toList();
    _currentIndex = index;
    notifyListeners();
    await _playCurrent();
  }

  /// 添加到队列并播放
  Future<void> playSingle(SongSearchResult result) async {
    _queue = [PlayQueueItem.fromSearchResult(result)];
    _currentIndex = 0;
    notifyListeners();
    await _playCurrent();
  }

  /// 添加到队列末尾（不立即播放）
  void addToQueue(SongSearchResult result) {
    _queue.add(PlayQueueItem.fromSearchResult(result));
    notifyListeners();
  }

  /// 从歌单播放
  Future<void> playFromPlaylist(List<SongSearchResult> tracks, int index) async {
    _queue = tracks.map((e) => PlayQueueItem.fromSearchResult(e)).toList();
    _currentIndex = index;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final item = _queue[_currentIndex];

    // 网易云直连不需要 API Key；酷狗/QQ 解析播放地址需要
    if (item.platform != MusicPlatform.netease && _apiKey.isEmpty) {
      _errorMessage = '酷狗/QQ音乐播放需要配置 API Key';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _lyrics = [];
    _currentLyricIndex = 0;
    _position = Duration.zero;

    // 标记 loading
    _queue[_currentIndex] = item.copyWith(loading: true);
    notifyListeners();

    try {
      // 解析播放地址
      SongDetail detail;
      if (item.platform == MusicPlatform.netease) {
        detail = await _api.neteaseMusic(item.id, level: _neteaseLevel.value);
      } else if (item.platform == MusicPlatform.qq) {
        detail = await _api.qqMusic(item.id, size: _commonLevel.value);
      } else {
        detail = await _api.kugouMusic(item.id, size: _commonLevel.value);
      }

      if (detail.url.isEmpty) {
        throw ApiException('404', '无法获取播放地址，可能是版权限制');
      }

      // 获取歌词
      String? lyricText;
      if (item.platform == MusicPlatform.netease) {
        final lyricData = await _api.neteaseLyric(item.id);
        lyricText = lyricData.original;
        final transLyric = LyricParser.parse(lyricData.translated);
        _lyrics = LyricParser.mergeTranslation(LyricParser.parse(lyricText), transLyric);
      } else if (item.platform == MusicPlatform.qq) {
        // QQ音乐: 优先直连歌词 API，失败则用解析返回的歌词
        try {
          final lyricData = await _api.qqLyric(item.id);
          lyricText = lyricData.original;
          _lyrics = LyricParser.parse(lyricText);
        } catch (_) {
          lyricText = detail.lyric;
          _lyrics = LyricParser.parse(lyricText);
        }
      } else {
        lyricText = detail.lyric;
        _lyrics = LyricParser.parse(lyricText);
      }

      // 更新队列项
      _queue[_currentIndex] = _queue[_currentIndex].copyWith(
        playUrl: detail.url,
        lyric: lyricText,
        duration: detail.duration,
        coverUrl: detail.coverUrl ?? item.coverUrl,
        loading: false,
      );

      // 设置音频源并播放（tag: MediaItem 用于系统媒体通知显示歌曲信息）
      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(detail.url),
          tag: MediaItem(
            id: '${item.platform.code}_${item.id}',
            title: item.name,
            artist: item.artist,
            album: item.album,
            artUri: detail.coverUrl != null && detail.coverUrl!.isNotEmpty
                ? Uri.parse(detail.coverUrl!)
                : null,
          ),
        ),
        preload: true,
      );
      await _audioPlayer.play();

      // 系统悬浮胶囊：显示/更新当前歌曲
      if (FloatingCapsuleService.enabled) {
        FloatingCapsuleService.show(
          title: item.name,
          artist: item.artist,
          coverUrl: detail.coverUrl ?? item.coverUrl,
          isPlaying: true,
        );
      }

      // 歌词索引由 positionStream 驱动更新（无需额外定时器）
    } catch (e) {
      _queue[_currentIndex] = _queue[_currentIndex].copyWith(loading: false, error: e.toString());
      _errorMessage = e.toString();
      _lastError = _friendlyError(e);
      _isLoading = false;
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 把底层异常翻译成用户可读的提示
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('404') || s.contains('版权') || s.contains('无法获取播放地址')) {
      return '音源获取失败：可能是版权限制或无资源，换一首试试';
    }
    if (s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('Failed host lookup') ||
        s.contains('timeout') ||
        s.contains('网络')) {
      return '网络异常：音源下载失败，请检查网络后重试';
    }
    return '播放失败：音源可能失效，请重试或切换音质';
  }

  void _onSongComplete() {
    switch (_playMode) {
      case PlayMode.sequence:
        playNext();
        break;
      case PlayMode.repeat:
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.play();
        break;
      case PlayMode.shuffle:
        if (_queue.length > 1) {
          final random = DateTime.now().millisecondsSinceEpoch % _queue.length;
          _currentIndex = random;
          _playCurrent();
        }
        break;
    }
  }

  Future<void> playPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    if (_playMode == PlayMode.shuffle) {
      _currentIndex = DateTime.now().millisecondsSinceEpoch % _queue.length;
    } else {
      _currentIndex = (_currentIndex + 1) % _queue.length;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + _queue.length) % _queue.length;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> seekTo(Duration position) async {
    await _audioPlayer.seek(position);
    _position = position;
    _updateLyricIndex();
    notifyListeners();
  }

  void togglePlayMode() {
    switch (_playMode) {
      case PlayMode.sequence:
        _playMode = PlayMode.repeat;
        break;
      case PlayMode.repeat:
        _playMode = PlayMode.shuffle;
        break;
      case PlayMode.shuffle:
        _playMode = PlayMode.sequence;
        break;
    }
    notifyListeners();
  }

  void toggleShowLyric() {
    _showLyric = !_showLyric;
    notifyListeners();
  }

  void playQueueItem(int index) {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    notifyListeners();
    _playCurrent();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _queue.length) _currentIndex = _queue.length - 1;
      if (_currentIndex >= 0) {
        _playCurrent();
      } else {
        _audioPlayer.stop();
      }
    }
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _lyrics.clear();
    _audioPlayer.stop();
    notifyListeners();
  }

  // ==================== 歌词同步 ====================

  void _updateLyricIndex() {
    if (_lyrics.isEmpty) return;
    final newIndex = LyricParser.findCurrentIndex(_lyrics, _position);
    if (newIndex != _currentLyricIndex) {
      _currentLyricIndex = newIndex;
      notifyListeners();
    }
  }

  // ==================== 清理 ====================

  @override
  void dispose() {
    _playerSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _bufferSub?.cancel();
    _errorSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

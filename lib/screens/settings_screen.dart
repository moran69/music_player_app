import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import '../screens/cache_list_screen.dart';
import '../providers/player_provider.dart';
import '../providers/theme_controller.dart';
import '../services/audio_cache_service.dart';
import '../services/favorite_service.dart';
import '../services/floating_capsule_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dir_picker.dart';
import '../widgets/update_dialog.dart';
import 'favorites_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscureKey = true;

  String _versionName = '';
  String _versionCode = '';
  bool _checking = false;

  // 缓存
  String _cacheSizeText = '';
  int _cacheCount = 0;

  // 缓存上限（字节，0 = 不限制；默认 2GB）
  int _cacheLimitBytes = 2 * 1024 * 1024 * 1024;

  // 缓存位置
  String _cacheLocationPath = '';
  bool _storagePerm = false;
  final _cachePathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerProvider>();
    _apiKeyController.text = player.apiKey;
    _loadVersion();
    _loadCacheInfo();
    _loadCacheLocation();
    _loadCacheLimit();
  }

  Future<void> _loadCacheLimit() async {
    try {
      final limit = await AudioCacheService.getCacheLimit();
      if (mounted) setState(() => _cacheLimitBytes = limit);
    } catch (_) {}
  }

  Future<void> _pickCacheLimit() async {
    const options = <int, String>{
      0: '不限制',
      1 * 1024 * 1024 * 1024: '1 GB',
      2 * 1024 * 1024 * 1024: '2 GB（默认）',
      4 * 1024 * 1024 * 1024: '4 GB',
      8 * 1024 * 1024 * 1024: '8 GB',
    };
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('缓存自动清理上限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map((e) => RadioListTile<int>(
                    value: e.key,
                    groupValue: _cacheLimitBytes,
                    title: Text(e.value),
                    dense: true,
                    onChanged: (v) => Navigator.pop(ctx, v),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
    if (picked == null || picked == _cacheLimitBytes) return;
    await AudioCacheService.setCacheLimit(picked);
    await _loadCacheLimit();
    await _loadCacheInfo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(picked == 0 ? '已取消上限，不再自动清理' : '缓存超过 ${options[picked]} 时将自动删除最久未播的歌曲'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _versionName = pkg.version;
          _versionCode = pkg.buildNumber;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCacheInfo() async {
    try {
      final size = await AudioCacheService.getCacheSize();
      final count = await AudioCacheService.getCacheCount();
      if (mounted) {
        setState(() {
          _cacheSizeText = AudioCacheService.formatSize(size);
          _cacheCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCacheLocation() async {
    try {
      final path = await AudioCacheService.getCacheDirPath();
      final perm = await AudioCacheService.hasStoragePermission();
      final prefs = await SharedPreferences.getInstance();
      final rel = prefs.getString('cache_base_path') ?? 'Music/momo';
      if (mounted) {
        setState(() {
          _cacheLocationPath = path;
          _storagePerm = perm;
          _cachePathController.text = rel;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCachePath() async {
    final rel = _cachePathController.text.trim();
    if (rel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('路径不能为空'), duration: Duration(seconds: 1)),
      );
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_base_path', rel);
      AudioCacheService.resetCacheDir();
      await _loadCacheLocation();
      await _loadCacheInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('缓存路径已保存，新缓存将写入该位置'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _pickDir() async {
    // 未授权先提示
    final granted = await AudioCacheService.hasStoragePermission();
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先授予「所有文件访问」权限'),
          duration: Duration(seconds: 2),
        ),
      );
      _requestStoragePerm();
      return;
    }
    final picked = await DirPicker.pick(context, initialPath: _cacheLocationPath);
    if (picked == null) return;
    await AudioCacheService.setCacheDirPath(picked);
    await _loadCacheLocation();
    await _loadCacheInfo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已选择：$picked'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _requestStoragePerm() async {
    try {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        AudioCacheService.resetCacheDir();
        await _loadCacheLocation();
        await _loadCacheInfo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已授权，缓存将写入手机公共存储'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请在系统设置中开启「所有文件访问」，返回后刷新'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        await openAppSettings();
      }
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text('将删除 $_cacheCount 首已缓存歌曲（$_cacheSizeText），下次播放需重新联网。是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true) return;

    await AudioCacheService.clearCache();
    await _loadCacheInfo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清除'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _checkUpdate({bool manual = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final info =
          await UpdateService.checkUpdate(currentVersionCode: _versionCode);
      if (!mounted) return;
      if (info != null) {
        showUpdateDialog(context, info);
      } else if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本'), duration: Duration(seconds: 1)),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _cachePathController.dispose();
    super.dispose();
  }

  /// 系统悬浮胶囊开关
  Future<void> _toggleFloatingCapsule(bool value) async {
    if (value) {
      final hasPerm = await FloatingCapsuleService.hasPermission();
      if (!hasPerm) {
        FloatingCapsuleService.openPermissionSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请在系统设置中开启「悬浮窗」权限，返回后重新打开开关'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    } else {
      FloatingCapsuleService.hide();
    }
    FloatingCapsuleService.setEnabled(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('floating_capsule_enabled', value);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // 顶部标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '设置',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // ============ 外观 ============
            _buildCard(
              children: [
                _buildSectionHeader(
                  icon: Icons.dark_mode_outlined,
                  title: '外观',
                ),
                Consumer<ThemeController>(
                  builder: (ctx, themeCtrl, _) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '深色模式',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '夜间使用深色配色，保护眼睛',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('跟随系统'),
                                  icon: Icon(Icons.brightness_auto),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('浅色'),
                                  icon: Icon(Icons.light_mode_outlined),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('深色'),
                                  icon: Icon(Icons.dark_mode_outlined),
                                ),
                              ],
                              selected: {themeCtrl.mode},
                              showSelectedIcon: false,
                              onSelectionChanged: (s) =>
                                  themeCtrl.setMode(s.first),
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                          // 系统悬浮胶囊（跨 App 悬浮）
                          SwitchListTile(
                            secondary: const Icon(Icons.circle_notifications),
                            title: const Text('系统悬浮胶囊'),
                            subtitle: Text(
                              FloatingCapsuleService.enabled
                                  ? '播放时跨 App 悬浮显示（需悬浮窗权限）'
                                  : '在任意界面顶部显示播放胶囊',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: FloatingCapsuleService.enabled,
                            onChanged: _toggleFloatingCapsule,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),

            // ============ 我的收藏 ============
            _buildCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.redAccent),
                  title: const Text('我的收藏'),
                  subtitle: Consumer<FavoriteService>(
                    builder: (ctx, fav, _) =>
                        Text('${fav.favorites.length} 首已收藏歌曲'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FavoritesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),

            // ============ 播放缓存 ============
            _buildCard(
              children: [
                _buildSectionHeader(
                  icon: Icons.cached,
                  title: '播放缓存',
                ),
                ListTile(
                  leading: const Icon(Icons.download_done),
                  title: const Text('已缓存歌曲'),
                  subtitle: Text(
                    _cacheSizeText.isEmpty
                        ? '播放过的歌曲自动缓存，下次秒开'
                        : '$_cacheCount 首 · $_cacheSizeText',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_cacheCount > 0)
                        TextButton.icon(
                          onPressed: _clearCache,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('清除'),
                        ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CacheListScreen(),
                      ),
                    ).then((_) => _loadCacheInfo());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.auto_delete_outlined),
                  title: const Text('自动清理上限'),
                  subtitle: Text(
                    _cacheLimitBytes == 0
                        ? '不自动清理，可在上方手动清除'
                        : '缓存超过 ${AudioCacheService.formatSize(_cacheLimitBytes)} 时，自动删除最久未播的歌曲',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickCacheLimit,
                ),
              ],
            ),

            // ============ 缓存位置 ============
            _buildCard(
              children: [
                _buildSectionHeader(
                  icon: Icons.folder_open,
                  title: '缓存位置',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _storagePerm ? Icons.check_circle : Icons.warning_amber,
                            size: 18,
                            color: _storagePerm ? Colors.green : Colors.orange[700],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _storagePerm
                                  ? '已授权，缓存写入手机公共存储'
                                  : '未授权，目前写入应用私有目录（看不到）',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _cacheLocationPath.isEmpty ? '解析中…' : _cacheLocationPath,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '缓存路径（可手动输入相对路径，或点「选择目录」可视化浏览）',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '相对路径基于存储根，如 Music/momo；选择目录则用绝对路径',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cachePathController,
                        decoration: const InputDecoration(
                          hintText: 'Music/momo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _pickDir,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('选择目录'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _requestStoragePerm,
                            icon: const Icon(Icons.security),
                            label: const Text('授权存储'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saveCachePath,
                            icon: const Icon(Icons.save),
                            label: const Text('保存路径'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ============ 播放与音质 ============
            _buildCard(
              children: [
                _buildSectionHeader(
                  icon: Icons.graphic_eq,
                  title: '播放与音质',
                ),
                Consumer<PlayerProvider>(
                  builder: (ctx, player, _) {
                    return Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.audiotrack),
                          title: const Text('网易云音质'),
                          subtitle: Text(player.neteaseLevel.label),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showNeteaseLevelPicker(ctx, player),
                        ),
                        ListTile(
                          leading: const Icon(Icons.library_music),
                          title: const Text('QQ / 酷狗音质'),
                          subtitle: Text(player.commonLevel.label),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showCommonLevelPicker(ctx, player),
                        ),
                        ExpansionTile(
                          leading: const Icon(Icons.info_outline),
                          title: const Text('音质说明'),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          children: [
                            _buildQualityRow('网易云', NeteaseLevel.values),
                            const SizedBox(height: 6),
                            _buildQualityRow('QQ音乐', CommonLevel.values),
                            const SizedBox(height: 6),
                            _buildQualityRow('酷狗音乐', CommonLevel.values),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.warning_amber,
                                      color: Colors.orange[700], size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '高音质（无损/Hi-Res/母带）加载更慢，部分歌曲可能受版权限制无法播放。',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            // ============ API 配置 ============
            _buildCard(
              children: [
                _buildSectionHeader(icon: Icons.key, title: 'API 配置'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ChKSz API Key',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '用于所有平台播放地址解析（网易云/QQ/酷狗）',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureKey,
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              context
                                  .read<PlayerProvider>()
                                  .setApiKey(_apiKeyController.text.trim());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('API Key 已保存'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('保存'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _showApiKeyHelp(context),
                            icon: const Icon(Icons.help_outline),
                            label: const Text('如何获取？'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ============ 关于 ============
            _buildCard(
              children: [
                _buildSectionHeader(
                  icon: Icons.music_note,
                  title: '关于',
                ),
                const ListTile(
                  leading: Icon(Icons.link),
                  title: Text('API 文档'),
                  subtitle: Text('api.chksz.com'),
                ),
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('检查更新'),
                  subtitle: _checking
                      ? const Text('检查中…')
                      : const Text('点击检查是否有新版本'),
                  trailing: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _checking ? null : () => _checkUpdate(manual: true),
                ),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('版本'),
                  trailing: Text(
                    _versionName.isEmpty ? '—' : '$_versionName ($_versionCode)',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片分组容器
  Widget _buildCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: CardStyle.softCard(),
      child: Column(children: children),
    );
  }

  /// 分组标题（图标 + 文字）
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityRow(String platform, List values) {
    final labels = values.map((e) => e.label).join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            platform,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            labels,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  void _showNeteaseLevelPicker(BuildContext ctx, PlayerProvider player) {
    showDialog(
      context: ctx,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择网易云音质'),
        children: NeteaseLevel.values.map((level) {
          return RadioListTile<String>(
            value: level.value,
            groupValue: player.neteaseLevel.value,
            title: Text(level.label),
            onChanged: (v) {
              player.setNeteaseLevel(level);
              Navigator.pop(ctx);
            },
          );
        }).toList(),
      ),
    );
  }

  void _showCommonLevelPicker(BuildContext ctx, PlayerProvider player) {
    showDialog(
      context: ctx,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择 QQ/酷狗音质'),
        children: CommonLevel.values.map((level) {
          return RadioListTile<String>(
            value: level.value,
            groupValue: player.commonLevel.value,
            title: Text(level.label),
            onChanged: (v) {
              player.setCommonLevel(level);
              Navigator.pop(ctx);
            },
          );
        }).toList(),
      ),
    );
  }

  void _showApiKeyHelp(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('获取 API Key'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 访问 api.chksz.com'),
            SizedBox(height: 8),
            Text('2. 注册/登录账号'),
            SizedBox(height: 8),
            Text('3. 点击「查看密钥」获取个人 API Key'),
            SizedBox(height: 8),
            Text('4. 将 Key 复制到上方输入框并保存'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }
}

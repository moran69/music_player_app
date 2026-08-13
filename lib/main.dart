import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/player_provider.dart';
import 'providers/theme_controller.dart';
import 'screens/discover_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/settings_screen.dart';
import 'services/floating_capsule_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'utils/system_ui.dart';
import 'widgets/mini_player.dart';
import 'widgets/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 全面屏适配：内容延伸到状态栏/导航栏区域（各页面已用 SafeArea 保护内容）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 系统媒体通知：播放时通知栏/锁屏显示媒体控制（系统级胶囊体验）
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.music_player_app.audio',
    androidNotificationChannelName: '音乐播放',
    androidNotificationOngoing: true,
  );
  // Android 13+ 请求通知权限（否则系统媒体通知不显示）
  try {
    await Permission.notification.request();
  } catch (_) {}
  // 系统悬浮窗胶囊：初始化通道 + 恢复开关状态
  FloatingCapsuleService.init();
  try {
    final prefs = await SharedPreferences.getInstance();
    FloatingCapsuleService.setEnabled(
        prefs.getBool('floating_capsule_enabled') ?? false);
  } catch (_) {}
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeCtrl, _) {
          return MaterialApp(
            title: '音乐播放器',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeCtrl.mode,
            // 按实际生效的主题同步全局亮暗标志 + 系统栏样式（状态栏不黑条、图标跟随主题）
            builder: (context, child) {
              AppColors.isDark =
                  Theme.of(context).brightness == Brightness.dark;
              applySystemUi(dark: AppColors.isDark);
              // 注入系统悬浮窗胶囊回调（仅一次）
              if (FloatingCapsuleService.onPlayPauseTap == null) {
                FloatingCapsuleService.onPlayPauseTap = () {
                  context.read<PlayerProvider>().playPause();
                };
                FloatingCapsuleService.onCapsuleTap = () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.push(
                      MaterialPageRoute(builder: (_) => const PlayerScreen()),
                    );
                  }
                };
              }
              return child!;
            },
            home: const MainScreen(),
          );
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _screens = const [
    DiscoverScreen(),
    SearchScreen(),
    PlaylistScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 启动后静默检查一次更新（仿 momo：有新版本则弹窗）
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
  }

  Future<void> _autoCheckUpdate() async {
    final info = await UpdateService.checkUpdate();
    if (!mounted) return;
    if (info != null) showUpdateDialog(context, info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 迷你播放器（悬浮在导航栏上方）
          const MiniPlayer(),
          // 导航栏
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: '发现',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.playlist_play_outlined),
                selectedIcon: Icon(Icons.playlist_play),
                label: '歌单',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

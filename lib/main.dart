import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'comic_source/built_in/registrar.dart';
import 'comic_source/comic_source.dart';
import 'database/favorites_helper.dart';
import 'database/joy_database.dart';
import 'foundation/download_manager.dart';
import 'foundation/app_data.dart';
import 'foundation/log.dart';
import 'theme/app_theme.dart';
import 'views/auth/login_page.dart';
import 'views/common/source_content_page.dart';
import 'views/detail/detail_page.dart';
import 'views/download/download_page.dart';
import 'views/image_search/image_search_page.dart';
import 'views/main_scaffold.dart';
import 'views/ranking/ranking_page.dart';
import 'views/reader/providers/reader_provider.dart';
import 'views/reader/reader.dart';
import 'views/reader/state/comic_state.dart';
import 'views/search/search_page.dart';
import 'views/settings/reader_settings_page.dart';
import 'views/settings/settings_page.dart';
import 'views/settings/source_settings_page.dart';
import 'views/settings/webdav_settings_page.dart';
import 'views/settings/log_viewer_page.dart';
import 'views/video/video_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppData.instance.init();
  await Log.initialize();
  await JoyDatabase.instance.initialize();
  FavoriteNotifier.instance.loadFromDb();
  DownloadManager.instance.initialize();
  registerBuiltInSources();
  await ComicSource.init(AppData.instance.enabledSources);
  runApp(const JoyComicApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainScaffold(),
    ),
    GoRoute(
      path: '/search/:sourceKey',
      builder: (context, state) => SearchPage(
        sourceKey: state.pathParameters['sourceKey']!,
      ),
    ),
    GoRoute(
      path: '/content/:sourceKey',
      builder: (context, state) => SourceContentPage(
        key: ValueKey(state.uri.toString()),
        sourceKey: state.pathParameters['sourceKey']!,
        kind: state.uri.queryParameters['kind'] ?? 'category',
        category: state.uri.queryParameters['category'] ?? '',
        param: state.uri.queryParameters['param'],
        sort: state.uri.queryParameters['sort'],
      ),
    ),
    GoRoute(
      path: '/ranking',
      builder: (context, state) {
        final tab = state.uri.queryParameters['tab'];
        final i = const {'latest': 0, 'hot': 1, 'rating': 2}[tab] ?? 0;
        return RankingPage(initialTab: i);
      },
    ),
    GoRoute(
      path: '/image-search',
      builder: (context, state) => const ImageSearchPage(),
    ),
    GoRoute(
      path: '/video',
      builder: (context, state) => const VideoPage(),
    ),
    GoRoute(
      path: '/download',
      builder: (context, state) => const DownloadPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => LoginPage(
        initialSourceKey: state.uri.queryParameters['source'] ?? 'jm',
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/settings/source',
      builder: (context, state) => SourceSettingsPage(
        sourceKey: state.uri.queryParameters['source'] ?? 'jm',
      ),
    ),
    GoRoute(
      path: '/settings/reader',
      builder: (context, state) => const ReaderSettingsPage(),
    ),
    GoRoute(
      path: '/logs',
      builder: (context, state) => const LogViewerPage(),
    ),
    GoRoute(
      path: '/webdav',
      builder: (context, state) => const WebDavSettingsPage(),
    ),
    GoRoute(
      path: '/detail/:sourceKey/:comicId',
      builder: (context, state) {
        final sourceKey = state.pathParameters['sourceKey']!;
        final comicId = state.pathParameters['comicId']!;
        return DetailPage(sourceKey: sourceKey, comicId: comicId);
      },
    ),
    GoRoute(
      path: '/reader',
      builder: (context, state) {
        final comicState = state.extra as ComicState;
        // 自动匹配源对应的图片加载器
        ReaderImageLoader? imageLoader;
        final source = ComicSource.find(comicState.sourceKey);
        if (source?.loadComicPages != null) {
          imageLoader = (String comicId, String? ep) =>
              source!.loadComicPages!(comicId, ep);
        }
        return Reader(
          comicState: comicState,
          imageLoader: imageLoader,
        );
      },
    ),
  ],
  // 未匹配路由（历史/关于/WebDAV/分类结果等"留功能位置"页）落到占位页，
  // 避免崩溃。功能集成时替换为真实页面。
  errorBuilder: (context, state) =>
      _PlaceholderPage(title: state.uri.path),
);

/// 功能待集成占位页。
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('功能待集成'), backgroundColor: const Color(0xFF0E0B14)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_rounded, size: 48, color: Color(0xFF8A8298)),
            const SizedBox(height: 12),
            Text('该页面 UI 框架已留位，真实功能待集成',
                style: const TextStyle(color: Color(0xFF8A8298))),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF5A5466))),
          ],
        ),
      ),
    );
  }
}

class JoyComicApp extends StatelessWidget {
  const JoyComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppData.instance.themeNotifier,
      builder: (context, _) {
        final isDark = AppData.instance.enableDarkMode;
        return MaterialApp.router(
          title: 'JoyComic',
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        );
      },
    );
  }
}

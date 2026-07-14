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
import 'views/favorites/favorites_page.dart';
import 'views/history/history_page.dart';
import 'views/image_search/image_search_page.dart';
import 'views/main_scaffold.dart';
import 'views/ranking/ranking_page.dart';
import 'views/reader/reader.dart';
import 'views/reader/state/comic_state.dart';
import 'views/search/search_page.dart';
import 'views/settings/reader_settings_page.dart';
import 'views/settings/settings_page.dart';
import 'views/settings/about_page.dart';
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
  registerBuiltInSources();
  await ComicSource.init(AppData.instance.enabledSources);
  await DownloadManager.instance.initialize();
  runApp(const JoyComicApp());
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const MainScaffold()),
    GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
    GoRoute(
      path: '/search/:sourceKey',
      builder: (context, state) =>
          SearchPage(sourceKey: state.pathParameters['sourceKey']!),
    ),
    GoRoute(
      path: '/category/:sourceKey/:categoryKey',
      builder: (context, state) => SourceContentPage(
        key: ValueKey(state.uri.toString()),
        sourceKey: state.pathParameters['sourceKey']!,
        kind: 'category',
        category: state.pathParameters['categoryKey']!,
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
    GoRoute(path: '/video', builder: (context, state) => const VideoPage()),
    GoRoute(
      path: '/download',
      builder: (context, state) => const DownloadPage(),
    ),
    GoRoute(
      path: '/favorites',
      builder: (context, state) => const FavoritesPage(),
    ),
    GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
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
    GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
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
    GoRoute(path: '/logs', builder: (context, state) => const LogViewerPage()),
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
        final extra = state.extra;
        if (extra is! ComicState) {
          return NotFoundPage(uri: state.uri, message: '阅读器参数无效');
        }
        final comicState = extra;
        final source = ComicSource.find(comicState.sourceKey);
        final imageLoader = readerRouteNetworkLoader(comicState, source);
        return Reader(comicState: comicState, imageLoader: imageLoader);
      },
    ),
  ],
  errorBuilder: (context, state) => NotFoundPage(uri: state.uri),
);

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, required this.uri, this.message = '页面不存在'});

  final Uri uri;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('404')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(uri.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      if (router.canPop()) {
                        router.pop();
                      } else {
                        router.go('/');
                      }
                    },
                    child: const Text('返回上一页'),
                  ),
                  FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('返回首页'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JoyComicApp extends StatelessWidget {
  const JoyComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppData.instance.themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          title: 'JoyComic',
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'presentation/widgets/auth_wrapper.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/pages/settings/download_tasks_page.dart';
import 'presentation/pages/settings/ssh_settings_page.dart';
import 'presentation/pages/settings/server_settings_page.dart';
import 'presentation/pages/settings/source_settings_page.dart';
import 'presentation/pages/settings/tts_settings_page.dart';
import 'presentation/pages/settings/sponsor_page.dart';
import 'presentation/pages/now_playing_page.dart';
import 'presentation/pages/js_proxy_test_page.dart';
import 'presentation/pages/update_page.dart';
import 'presentation/pages/playback_mode_selection_page.dart';
import 'presentation/pages/login_page.dart';
import 'presentation/pages/direct_mode_login_page.dart';
import 'presentation/pages/playlist_page.dart'; // 🎯 新增：歌单页面
import 'presentation/pages/music_search_page.dart'; // 🎯 新增：搜索页面

final appRouterProvider = Provider<GoRouter>((ref) {
  // 直接从根路由开始，不使用额外的 Splash 页面
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'root',
        builder: (BuildContext context, GoRouterState state) {
          return const AuthWrapper();
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/downloads',
        name: 'download_tasks',
        builder: (context, state) => const DownloadTasksPage(),
      ),
      GoRoute(
        path: '/settings/ssh',
        name: 'ssh_settings',
        builder: (context, state) => const SshSettingsPage(),
      ),
      GoRoute(
        path: '/settings/server',
        name: 'server_settings',
        builder: (context, state) => const ServerSettingsPage(),
      ),
      GoRoute(
        path: '/settings/source',
        name: 'source_settings',
        builder: (context, state) => const SourceSettingsPage(),
      ),
      GoRoute(
        path: '/settings/tts',
        name: 'tts_settings',
        builder: (context, state) => const TtsSettingsPage(),
      ),
      GoRoute(
        path: '/settings/sponsor',
        name: 'sponsor',
        builder: (context, state) => const SponsorPage(),
      ),
      GoRoute(
        path: '/now-playing',
        name: 'now_playing',
        builder: (context, state) => const NowPlayingPage(),
      ),
      GoRoute(
        path: '/js-proxy-test',
        name: 'js_proxy_test',
        builder: (context, state) => const JSProxyTestPage(),
      ),
      GoRoute(
        path: '/update',
        name: 'update',
        builder: (context, state) {
          final title = state.uri.queryParameters['title'] ?? '发现新版本';
          final message = state.uri.queryParameters['message'] ?? '';
          final url = state.uri.queryParameters['url'] ?? '';
          final force = (state.uri.queryParameters['force'] ?? 'false') == 'true';
          final targetVersion = state.uri.queryParameters['targetVersion'] ?? '';
          return UpdatePage(
            title: title,
            message: message,
            downloadUrl: url,
            force: force,
            targetVersion: targetVersion,
          );
        },
      ),
      GoRoute(
        path: '/mode_selection',
        name: 'mode_selection',
        builder: (context, state) => const PlaybackModeSelectionPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/direct_login',
        name: 'direct_login',
        builder: (context, state) => const DirectModeLoginPage(),
      ),
      // 🎯 新增：歌单页面路由
      GoRoute(
        path: '/playlist',
        name: 'playlist',
        builder: (context, state) {
          // 支持 showCreate 参数，用于自动弹出创建对话框
          final showCreate = state.uri.queryParameters['showCreate'] == 'true';
          return PlaylistPage(showCreateDialog: showCreate);
        },
      ),
      // 🎯 新增：搜索页面路由
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) => const MusicSearchPage(),
      ),
    ],
    debugLogDiagnostics: false,
  );
});

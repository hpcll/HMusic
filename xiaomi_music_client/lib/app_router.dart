import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'presentation/widgets/auth_wrapper.dart';
import 'presentation/pages/settings/download_tasks_page.dart';
import 'presentation/pages/settings/ssh_settings_page.dart';
import 'presentation/pages/settings/server_settings_page.dart';
import 'presentation/pages/settings/source_settings_page.dart';
import 'presentation/pages/settings/tts_settings_page.dart';
import 'presentation/pages/now_playing_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // 使用一个简单的根路由，内部由 AuthWrapper 判定跳转
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
        path: '/now-playing',
        name: 'now_playing',
        builder: (context, state) => const NowPlayingPage(),
      ),
    ],
    debugLogDiagnostics: false,
  );
});

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/library/views/library_screen.dart';
import 'features/library/views/permission_denied_screen.dart';
import 'features/player/views/now_playing_screen.dart';
import 'features/player/views/queue_screen.dart';
import 'features/playlists/views/playlist_detail_screen.dart';
import 'features/playlists/views/playlists_screen.dart';
import 'features/settings/views/settings_screen.dart';
import 'features/stats/views/stats_screen.dart';
import 'shared/widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/library',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/playlists',
            builder: (context, state) => const PlaylistsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => PlaylistDetailScreen(
                  playlistId:
                      int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
                ),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/stats',
            builder: (context, state) => const StatsScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ]),
      ],
    ),
    // Full-screen pages above the shell (no bottom nav / mini player).
    GoRoute(
      path: '/now-playing',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const NowPlayingScreen(),
    ),
    GoRoute(
      path: '/queue',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const QueueScreen(),
    ),
    GoRoute(
      path: '/permission',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PermissionDeniedScreen(),
    ),
  ],
);

class ElectrowaveApp extends StatelessWidget {
  const ElectrowaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00E5CC),
      brightness: Brightness.dark,
    );
    return MaterialApp.router(
      title: 'Electrowave',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5CC),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}

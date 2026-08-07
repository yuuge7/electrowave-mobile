import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/library/providers/browse_providers.dart';
import 'features/player/providers/player_providers.dart';
import 'features/library/views/browse_views.dart';
import 'features/library/views/library_screen.dart';
import 'features/library/views/permission_denied_screen.dart';
import 'features/library/views/trash_screen.dart';
import 'features/settings/views/equalizer_screen.dart';
import 'features/player/views/now_playing_screen.dart';
import 'features/player/views/queue_screen.dart';
import 'features/playlists/views/playlist_detail_screen.dart';
import 'features/playlists/views/playlists_screen.dart';
import 'features/playlists/views/smart_playlist_detail_screen.dart';
import 'features/playlists/views/smart_playlist_editor_screen.dart';
import 'features/settings/providers/settings_providers.dart';
import 'features/settings/services/settings_persistence.dart';
import 'features/settings/views/settings_screen.dart';
import 'features/stats/views/stats_screen.dart';
import 'features/stats/views/year_review_screen.dart';
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
              // Ahead of ':id', which would otherwise swallow "smart".
              GoRoute(
                path: 'smart/new',
                builder: (context, state) => const SmartPlaylistEditorScreen(),
              ),
              GoRoute(
                path: 'smart/:id',
                builder: (context, state) => SmartPlaylistDetailScreen(
                  smartPlaylistId:
                      int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => SmartPlaylistEditorScreen(
                      smartPlaylistId:
                          int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
                    ),
                  ),
                ],
              ),
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
            routes: [
              GoRoute(
                path: 'year/:year',
                builder: (context, state) => YearReviewScreen(
                  year: int.tryParse(state.pathParameters['year'] ?? '') ??
                      DateTime.now().year,
                ),
              ),
            ],
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
    // Browse detail pages. Names travel URI-encoded in the path because
    // albums/artists/folders have no numeric ids.
    GoRoute(
      path: '/album/:name',
      builder: (context, state) => AlbumDetailScreen(
        album: Uri.decodeComponent(state.pathParameters['name'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/artist/:name',
      builder: (context, state) => ArtistDetailScreen(
        artist: Uri.decodeComponent(state.pathParameters['name'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/folder/:path',
      builder: (context, state) => FolderDetailScreen(
        folderPath: Uri.decodeComponent(state.pathParameters['path'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/smart/:list',
      builder: (context, state) {
        final name = state.pathParameters['list'];
        final list = SmartList.values.firstWhere(
          (value) => value.name == name,
          orElse: () => SmartList.favorites,
        );
        return SmartListScreen(list: list);
      },
    ),
    GoRoute(
      path: '/trash',
      builder: (context, state) => const TrashScreen(),
    ),
    GoRoute(
      path: '/equalizer',
      builder: (context, state) => const EqualizerScreen(),
    ),
  ],
);

const Color kBrandSeed = Color(0xFF00E5CC);

class ElectrowaveApp extends ConsumerWidget {
  const ElectrowaveApp({super.key});

  ThemeData _theme(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    // Every touch anywhere in the app feeds the audio handler's
    // "stop when unattended" timer (Settings → Playback). Sitting above
    // MaterialApp it sees the whole app's pointer events without any screen
    // having to opt in.
    return Listener(
      onPointerDown: (_) => ref.read(audioHandlerProvider).noteUserActivity(),
      child: _buildApp(settings),
    );
  }

  Widget _buildApp(AppSettings settings) {
    // DynamicColorBuilder yields the wallpaper palette on Android 12+, and
    // null everywhere else — fall back to the brand seed in that case.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.dynamicColor;
        final lightScheme = useDynamic && lightDynamic != null
            ? lightDynamic.harmonized()
            : ColorScheme.fromSeed(seedColor: kBrandSeed);
        final darkScheme = useDynamic && darkDynamic != null
            ? darkDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: kBrandSeed,
                brightness: Brightness.dark,
              );

        return MaterialApp.router(
          title: 'Electrowave',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: _theme(lightScheme),
          darkTheme: _theme(darkScheme),
          routerConfig: appRouter,
        );
      },
    );
  }
}

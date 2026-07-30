import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database_provider.dart';
import '../../features/library/providers/library_providers.dart';
import '../../features/player/providers/player_providers.dart';
import 'mini_player.dart';

/// Bottom-nav shell: Library, Playlists, Stats, Settings, with the mini
/// player docked above the navigation bar on every tab.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Playback-notification permission (Android 13+), best effort.
      ref.read(permissionServiceProvider).requestNotifications();

      if (ref.read(importAppliedProvider)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Backup imported successfully'),
          duration: Duration(seconds: 4),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Transient playback messages (missing files etc.) as snackbars.
    ref.listen(playerMessageProvider, (_, message) {
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        ref.read(playerMessageProvider.notifier).state = null;
      }
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: (index) => widget.navigationShell.goBranch(
              index,
              initialLocation: index == widget.navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Library'),
              NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music),
                  label: 'Playlists'),
              NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Stats'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings'),
            ],
          ),
        ],
      ),
    );
  }
}

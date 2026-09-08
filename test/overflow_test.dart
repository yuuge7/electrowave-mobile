import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/core/theme/theme.dart';
import 'package:electrowave_mobile/features/library/providers/browse_providers.dart';
import 'package:electrowave_mobile/features/library/providers/library_providers.dart';
import 'package:electrowave_mobile/features/library/views/browse_views.dart';
import 'package:electrowave_mobile/features/library/views/library_screen.dart';
import 'package:electrowave_mobile/features/library/views/track_list_screen.dart';
import 'package:electrowave_mobile/features/playlists/providers/playlist_providers.dart';
import 'package:electrowave_mobile/features/playlists/views/playlists_screen.dart';
import 'package:electrowave_mobile/features/playlists/views/smart_playlist_editor_screen.dart';
import 'package:electrowave_mobile/features/playlists/views/track_picker_screen.dart';
import 'package:electrowave_mobile/features/player/providers/player_providers.dart';
import 'package:electrowave_mobile/features/player/views/now_playing_screen.dart';
import 'package:electrowave_mobile/features/player/views/queue_screen.dart';
import 'package:electrowave_mobile/features/player/views/sleep_timer_sheet.dart';
import 'package:electrowave_mobile/features/settings/views/equalizer_screen.dart';
import 'package:electrowave_mobile/features/stats/providers/stats_providers.dart';
import 'package:electrowave_mobile/features/stats/providers/year_review_providers.dart';
import 'package:electrowave_mobile/features/stats/views/stats_screen.dart';
import 'package:electrowave_mobile/features/stats/views/year_review_screen.dart';
import 'package:electrowave_mobile/features/stats/widgets/listening_heatmap.dart';
import 'package:electrowave_mobile/features/settings/providers/settings_providers.dart';
import 'package:electrowave_mobile/features/settings/services/settings_persistence.dart';
import 'package:electrowave_mobile/shared/widgets/deck_nav_bar.dart';
import 'package:electrowave_mobile/shared/widgets/mini_player.dart';
import 'package:electrowave_mobile/shared/widgets/track_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Overflow regression tests.
///
/// A `RenderFlex` overflow raises a Flutter error, which fails the test that
/// pumped it — so pumping the dense screens and the sheets on a small screen
/// with large text is the whole check. Sizes are the ones that broke: a short
/// phone in landscape-ish height, and the accessibility text scales.
final _track = Track(
  id: 1,
  filePath: '/music/harbour.mp3',
  title: 'Harbour, 4am (extended late night mix)',
  artist: 'Various Artists With A Long Name',
  album: 'Night Tapes Volume Four',
  durationMs: 245000,
  dateAdded: DateTime(2024, 1, 1),
  totalPlayCount: 3,
  isDeleted: false,
  isFavorite: true,
);

final _queued = Track(
  id: 2,
  filePath: '/music/low-orbit.mp3',
  title: 'Low Orbit (a very long queued title to push the row)',
  artist: 'Aurora Drift',
  album: 'Night Tapes Volume Four',
  durationMs: 198000,
  dateAdded: DateTime(2024, 1, 2),
  totalPlayCount: 1,
  isDeleted: false,
  isFavorite: false,
);

final _year = DateTime.now().year;

/// The one day in the stubbed year with listening on it, so a test can open
/// its cell on the calendar.
final _busyDay = DateTime(_year, 3, 4);

class _StubPlayerController extends PlayerController {
  @override
  PlayerQueueState build() => PlayerQueueState(
        current: _track,
        context: [_track, _queued],
        contextName: 'Library',
        contextIndex: 0,
        manualQueue: [_queued],
      );
}

class _StubSettingsController extends SettingsController {
  @override
  AppSettings build() => const AppSettings(playbackRate: 1.5, eqEnabled: true);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith(_StubPlayerController.new),
        settingsControllerProvider.overrideWith(_StubSettingsController.new),
        trackStreamProvider(
          _track.id,
        ).overrideWith((ref) => Stream.value(_track)),
        playingProvider.overrideWith((ref) => Stream.value(true)),
        positionProvider.overrideWith(
          (ref) => Stream.value(const Duration(seconds: 61)),
        ),
        durationProvider.overrideWith(
          (ref) => Stream.value(const Duration(seconds: 245)),
        ),
        libraryTracksProvider.overrideWith((ref) => Stream.value([_track])),
        albumsProvider.overrideWith(
          (ref) => Stream.value([
            AlbumSummary(
              album: _track.album,
              artist: _track.artist,
              trackCount: 12,
              totalMs: 2400000,
            ),
          ]),
        ),
        artistsProvider.overrideWith(
          (ref) => Stream.value([
            ArtistSummary(
              artist: _track.artist,
              trackCount: 12,
              albumCount: 2,
              totalMs: 2400000,
            ),
          ]),
        ),
        missingFilesProvider.overrideWith((ref) async => <int>{}),
        playlistsProvider.overrideWith(
          (ref) => Stream.value([
            PlaylistWithCount(
              playlist: Playlist(
                id: 1,
                name: 'Long walks and longer drives',
                createdAt: DateTime(2024, 5, 5),
              ),
              trackCount: 128,
            ),
          ]),
        ),
        playlistProvider(1).overrideWith(
          (ref) => Stream.value(
            Playlist(
              id: 1,
              name: 'Long walks and longer drives',
              createdAt: DateTime(2024, 5, 5),
            ),
          ),
        ),
        playlistTracksProvider(1).overrideWith(
          (ref) => Stream.value([_queued]),
        ),
        // The picker opens on artist order.
        pickerLibraryProvider(
          LibrarySort.artist,
        ).overrideWith((ref) => Stream.value([_track, _queued])),
        smartPlaylistsProvider.overrideWith(
          (ref) => Stream.value([
            SmartPlaylist(
              id: 1,
              name: 'Recently added, unplayed',
              rulesJson: '{"match":"all","rules":[]}',
              createdAt: DateTime(2024, 5, 5),
            ),
          ]),
        ),
        totalListeningMsProvider.overrideWith((ref) => Stream.value(9000000)),
        totalListenedMsProvider.overrideWith((ref) => Stream.value(8400000)),
        topTracksProvider.overrideWith(
          (ref) => Stream.value([
            TopTrackStat(track: _track, playCount: 42),
          ]),
        ),
        topArtistsProvider.overrideWith(
          (ref) => Stream.value([
            TopArtistStat(
              artist: _track.artist,
              playCount: 42,
              totalMs: 9000000,
            ),
          ]),
        ),
        tracksByListeningTimeProvider.overrideWith(
          (ref) => Stream.value([
            TrackListeningStat(track: _track, listenedMs: 8400000),
          ]),
        ),
        yearDailyListeningProvider(_year).overrideWith(
          (ref) => Stream.value([
            DailyListening(day: _busyDay, listenedMs: 3600000),
            DailyListening(day: DateTime(_year, 3, 5), listenedMs: 1800000),
          ]),
        ),
        dayListenedMsProvider(_busyDay).overrideWith(
          (ref) => Stream.value(3600000),
        ),
        dayPlayCountProvider(_busyDay).overrideWith((ref) => Stream.value(14)),
        dayDistinctTracksProvider(_busyDay).overrideWith(
          (ref) => Stream.value(9),
        ),
        dayTopTracksProvider(_busyDay).overrideWith(
          (ref) => Stream.value([
            TrackListeningStat(track: _track, listenedMs: 3000000),
            TrackListeningStat(track: _queued, listenedMs: 600000),
          ]),
        ),
        yearListenedMsProvider(_year).overrideWith(
          (ref) => Stream.value(8400000),
        ),
        yearDistinctTracksProvider(_year).overrideWith(
          (ref) => Stream.value(37),
        ),
        yearTopTracksProvider(_year).overrideWith(
          (ref) => Stream.value([
            TrackListeningStat(track: _track, listenedMs: 8400000),
          ]),
        ),
        yearTopArtistsProvider(_year).overrideWith(
          (ref) => Stream.value([
            TopArtistStat(
              artist: _track.artist,
              playCount: 42,
              totalMs: 9000000,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: ElectrowaveTheme.build(ElectrowaveTheme.darkScheme),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drags the first scrollable to the end, so a lazy list also builds — and
/// so can overflow in — the rows that start below the fold.
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return;
  for (var i = 0; i < 8; i++) {
    await tester.drag(scrollable.first, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
}

/// Opens a sheet from a bare screen, so the sheet is what is under test.
Widget _sheetLauncher(void Function(BuildContext) open) {
  return Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => open(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

const _sizes = <String, Size>{
  'short phone': Size(360, 560),
  'small phone': Size(320, 480),
  'phone': Size(412, 892),
};

void main() {
  group('sheets fit', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('track menu — ${entry.key} at ${scale}x text',
            (tester) async {
          await _pump(
            tester,
            _sheetLauncher((context) => showTrackContextMenu(context, _track)),
            size: entry.value,
            textScale: scale,
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(find.text('Play next'), findsOneWidget);
        });

        testWidgets('sleep timer — ${entry.key} at ${scale}x text',
            (tester) async {
          await _pump(
            tester,
            _sheetLauncher(showSleepTimerSheet),
            size: entry.value,
            textScale: scale,
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(find.text('15 minutes'), findsOneWidget);
        });
      }
    }
  });

  group('queue fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const QueueScreen(),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text(_queued.title), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('equalizer fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const EqualizerScreen(),
            size: entry.value,
            textScale: scale,
          );

          // The band sliders sit below the fold on a short screen, and a
          // lazy list does not build — or overflow — what it has not
          // reached, so scroll them into view before checking.
          for (var i = 0; i < 8 && find.byType(Slider).evaluate().isEmpty;
              i++) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -160),
            );
            await tester.pumpAndSettle();
          }

          expect(find.byType(Slider), findsWidgets);
        });
      }
    }
  });

  group('docked bar fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            Scaffold(
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(),
                  DeckNavBar(
                    selectedIndex: 0,
                    onSelected: (_) {},
                    destinations: const [
                      DeckDestination(
                        icon: Icons.library_music_outlined,
                        selectedIcon: Icons.library_music,
                        label: 'Library',
                      ),
                      DeckDestination(
                        icon: Icons.queue_music_outlined,
                        selectedIcon: Icons.queue_music,
                        label: 'Lists',
                      ),
                      DeckDestination(
                        icon: Icons.insights_outlined,
                        selectedIcon: Icons.insights,
                        label: 'Stats',
                      ),
                      DeckDestination(
                        icon: Icons.tune_outlined,
                        selectedIcon: Icons.tune,
                        label: 'Setup',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            size: entry.value,
            textScale: scale,
          );
        });
      }
    }
  });

  group('library fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const LibraryScreen(),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text(_track.title), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('playlists fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const PlaylistsScreen(),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text('Long walks and longer drives'), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('track picker fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('new playlist — ${entry.key} at ${scale}x text',
            (tester) async {
          await _pump(
            tester,
            const TrackPickerScreen(),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text(_track.title), findsWidgets);

          // Picking one is what puts the counter in the tally bar, which is
          // the tallest thing on the screen at 2x text.
          await tester.tap(find.text(_track.title).first);
          await tester.pumpAndSettle();
          expect(find.text('1'), findsOneWidget);

          await _scrollThrough(tester);

          // Album and artist rows carry a second line and a fraction label,
          // so they need pumping too.
          for (final tab in const ['Albums', 'Artists']) {
            await tester.tap(find.text(tab));
            await tester.pumpAndSettle();
          }
        });

        testWidgets('adding to a playlist — ${entry.key} at ${scale}x text',
            (tester) async {
          await _pump(
            tester,
            const TrackPickerScreen(playlistId: 1),
            size: entry.value,
            textScale: scale,
          );

          // _queued is already on the playlist, so its row is the disabled one.
          expect(find.text(_track.title), findsWidgets);
          expect(find.text('IN LIST'), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('track list fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            TrackListScreen(
              title: _track.album,
              subtitle: _track.artist,
              tracks: AsyncValue.data([_track]),
            ),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text(_track.title), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('albums grid fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const Scaffold(body: AlbumsGrid()),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text(_track.album), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('artists list fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const Scaffold(body: ArtistsList()),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text(_track.artist), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('smart playlist editor fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const SmartPlaylistEditorScreen(),
            size: entry.value,
            textScale: scale,
          );

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('stats fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const StatsScreen(),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text('Listening'), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('year review fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            YearReviewScreen(year: _year),
            size: entry.value,
            textScale: scale,
          );

          expect(find.text('hours listened'), findsWidgets);

          await _scrollThrough(tester);
        });
      }
    }
  });

  group('now playing fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const NowPlayingScreen(),
            size: entry.value,
            textScale: scale,
          );

          expect(find.textContaining('UP NEXT'), findsOneWidget);
        });
      }
    }
  });

  group('speed sheet fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            const NowPlayingScreen(),
            size: entry.value,
            textScale: scale,
          );

          // The chip is always on the player now, whatever the rate is.
          await tester.tap(find.text('1.5×'));
          await tester.pumpAndSettle();

          expect(find.text('PLAYBACK SPEED'), findsOneWidget);
          // Every preset key, so the wrap is pumped at full width.
          expect(find.text('0.75×'), findsOneWidget);
          expect(find.text('2×'), findsOneWidget);
        });
      }
    }
  });

  group('calendar day panel fits', () {
    for (final entry in _sizes.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${entry.key} at ${scale}x text', (tester) async {
          await _pump(
            tester,
            YearReviewScreen(year: _year),
            size: entry.value,
            textScale: scale,
          );

          // The page scrolls vertically and each grid scrolls horizontally,
          // so the outer one has to be named.
          await tester.scrollUntilVisible(
            find.text('Listening calendar'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();

          // The share card carries a second, untappable copy of the grid, so
          // the tappable one is the later of the two.
          final cell = find.descendant(
            of: find.byType(ListeningHeatmap).last,
            matching: find.byTooltip(
              '${DateFormat.yMMMd().format(_busyDay)}\n60 min',
            ),
          );
          await tester.ensureVisible(cell);
          await tester.pumpAndSettle();
          await tester.tap(cell, warnIfMissed: false);
          await tester.pumpAndSettle();

          expect(find.text('PLAYS'), findsOneWidget);
          expect(find.text('MOST HEARD'), findsOneWidget);

          await _scrollThrough(tester);
        });
      }
    }
  });
}

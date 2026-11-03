import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path_provider/path_provider.dart';
import 'package:electrowave_mobile/app.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/core/database/database_provider.dart';
import 'package:electrowave_mobile/features/player/providers/player_providers.dart';
import 'package:electrowave_mobile/features/player/services/audio_handler.dart';
import 'package:electrowave_mobile/features/player/services/audio_analyzer.dart';
import 'package:electrowave_mobile/features/library/providers/library_providers.dart';
import 'package:electrowave_mobile/features/library/services/permission_service.dart';
import 'package:electrowave_mobile/features/library/services/library_scanner.dart';
import 'package:electrowave_mobile/features/library/services/tag_writer.dart';
import 'package:electrowave_mobile/features/settings/providers/settings_providers.dart';
import 'package:electrowave_mobile/features/settings/services/settings_persistence.dart';
import 'package:electrowave_mobile/shared/widgets/track_tile.dart';

class _TestPermissions extends PermissionService {
  @override
  Future<bool> requestNotifications() async => true;
}

class _MemorySettings extends SettingsPersistence {
  AppSettings value = const AppSettings();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

Future<File> tone(
  String path, {
  double amplitude = 0.12,
  int seconds = 5,
}) async {
  const rate = 44100, channels = 2;
  final frames = rate * seconds;
  final bytes = ByteData(44 + frames * 4);
  void text(int at, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(at + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + frames * 4, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 4, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, frames * 4, Endian.little);
  for (var i = 0; i < frames; i++) {
    final sample = (sin(2 * pi * 1000 * i / rate) * 32767 * amplitude).round();
    bytes.setInt16(44 + i * 4, sample, Endian.little);
    bytes.setInt16(46 + i * 4, sample, Endian.little);
  }
  return File(path).writeAsBytes(bytes.buffer.asUint8List());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '10k library, native analysis, private session, queue and gapless under sleep',
    (tester) async {
      MediaKit.ensureInitialized();
      final support = await getApplicationSupportDirectory();
      final preserved = <String, List<int>?>{};
      for (final name in [
        'settings.json',
        'playback_state.json',
        'library.json',
      ]) {
        final file = File('${support.path}/$name');
        preserved[name] = await file.exists() ? await file.readAsBytes() : null;
      }
      final temp = await Directory(
        '${(await getTemporaryDirectory()).path}/electrowave-integration-${DateTime.now().millisecondsSinceEpoch}',
      ).create();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final handler = await AudioService.init(
        builder: ElectrowaveAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.electrowave.playback',
          androidNotificationChannelName: 'Playback',
          androidNotificationIcon: 'drawable/ic_stat_electrowave',
          androidStopForegroundOnPause: false,
        ),
      );
      handler.player.stream.error.listen((e) => debugPrint('PLAYER_ERROR=$e'));
      final loggedErrors = <String>{};
      handler.player.stream.log.listen((e) {
        if ((e.level == 'error' || e.level == 'fatal') &&
            loggedErrors.add(e.text)) {
          debugPrint('MPV_LOG=$e');
        }
      });
      final settings = _MemorySettings();
      final tracks = <Track>[];
      for (var i = 0; i < 3; i++) {
        final file = await tone('${temp.path}/test-$i.wav');
        final id = await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                filePath: file.path,
                title: 'A Test $i',
                artist: 'Test artist',
                album: 'Test album',
                genre: const Value('Electronic'),
                year: const Value(2026),
                durationMs: 5000,
              ),
            );
        tracks.add((await db.trackById(id))!);
      }
      await db.batch(
        (b) => b.insertAll(db.tracks, [
          for (var i = 0; i < 10050; i++)
            TracksCompanion.insert(
              filePath: '${temp.path}/missing-$i.mp3',
              title: 'Song ${i.toString().padLeft(5, '0')}',
              artist: 'Artist ${i % 200}',
              album: 'Album ${i % 500}',
              genre: Value(i.isEven ? 'House' : 'Rock'),
              year: Value(1980 + i % 46),
              durationMs: 180000,
            ),
        ]),
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          permissionServiceProvider.overrideWithValue(_TestPermissions()),
          audioHandlerProvider.overrideWithValue(handler),
          settingsPersistenceProvider.overrideWithValue(settings),
          missingFilesProvider.overrideWith((_) async => {}),
        ],
      );
      addTearDown(() async {
        debugPrint('EMULATOR_CLEANUP_START');
        await handler.pause();
        if (container.exists(playerControllerProvider)) {
          await container.read(playerControllerProvider.notifier).flushState();
        }
        await handler.stop();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        container.dispose();
        await handler.dispose();
        await db.close();
        for (final entry in preserved.entries) {
          final file = File('${support.path}/${entry.key}');
          if (entry.value == null) {
            if (await file.exists()) await file.delete();
          } else {
            await file.writeAsBytes(entry.value!, flush: true);
          }
        }
        debugPrint('EMULATOR_CLEANUP_FINISHED');
      });
      Future<void> waitFor(bool Function() condition, {int seconds = 8}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        if (!condition()) {
          final native = handler.player.platform as NativePlayer;
          debugPrint(
            'WAIT_FAILURE current=${container.read(playerControllerProvider).current?.id} playlist=${await native.getProperty('playlist')} pos=${handler.position}',
          );
        }
        expect(condition(), true);
      }

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ElectrowaveApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Library').first, findsOneWidget);
        expect(
          find.byType(TrackTile).evaluate().length,
          lessThan(35),
          reason: '10k library must remain lazy',
        );
        final timer = Stopwatch()..start();
        expect(
          (await db.watchLibrary(search: 'Song 09999').first).single.title,
          'Song 09999',
        );
        timer.stop();
        debugPrint('EMULATOR_SEARCH_10053_MS=${timer.elapsedMilliseconds}');
        await tester.longPress(find.text('A Test 0').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('1 selected'), findsOneWidget);
        await tester.tap(find.textContaining('1 selected'));
        await tester.pumpAndSettle();
        for (final title in [
          'Albums',
          'Artists',
          'Folders',
          'Genres',
          'Years',
        ]) {
          await tester.ensureVisible(find.text(title).first);
          await tester.tap(find.text(title).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        appRouter.go('/stats');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Listening patterns'));
        await tester.pumpAndSettle();
        expect(find.text('Listening by hour'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        appRouter.go('/settings');
        await tester.pumpAndSettle();
        for (final title in [
          'Library',
          'Playback',
          'Audio',
          'Appearance',
          'Backup',
          'About',
        ]) {
          await tester.tap(find.text(title).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        final analysis = await AudioAnalyzer.analyze(tracks.first);
        expect(analysis.waveform, hasLength(256));
        expect(analysis.waveform.reduce(max), closeTo(0.12, 0.005));
        expect(analysis.gainDb.isFinite, true);
        expect(analysis.lufs, inInclusiveRange(-25.0, -12.0));
        debugPrint(
          'EMULATOR_ANALYSIS_LUFS=${analysis.lufs} GAIN=${analysis.gainDb}',
        );
        final scanDb = AppDatabase.forTesting(NativeDatabase.memory());
        final scanContainer = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(scanDb)],
        );
        try {
          final scanner = scanContainer.read(scanControllerProvider.notifier);
          await scanner.scanFolder(temp.path);
          expect(scanContainer.read(scanControllerProvider).processed, 3);
          await scanner.scanFolder(temp.path);
          expect(scanContainer.read(scanControllerProvider).skipped, 3);
          final scanning = scanner.scanFolder(temp.path);
          scanner.cancel();
          await scanning;
          expect(scanContainer.read(scanControllerProvider).cancelled, true);
        } finally {
          scanContainer.dispose();
          await scanDb.close();
        }
        final flacPath = await AudioAnalyzer.channel.invokeMethod<String>(
          'crossfeedFile',
          {'path': tracks.first.filePath, 'mix': false},
        );
        final rated = await File(flacPath!).copy('${temp.path}/rated.flac');
        expect(
          applyTagEditToFile(
            rated.path,
            const TagEdit(title: 'Rated FLAC', rating: 4),
          ),
          TagFileResult.written,
        );
        final ratedTags = parseTags(rated.path);
        expect(ratedTags.title, 'Rated FLAC');
        expect(ratedTags.rating, 4);
        final ratedAnalysis = await AudioAnalyzer.analyze(
          tracks.first.copyWith(filePath: rated.path),
        );
        expect(ratedAnalysis.waveform.reduce(max), closeTo(0.12, 0.005));
        debugPrint('EMULATOR_FLAC_TAG_DECODE_PASS');
        final controller = container.read(playerControllerProvider.notifier);
        final audioSettings = container.read(
          settingsControllerProvider.notifier,
        );
        debugPrint('TEST_AUDIO_BASELINE');
        await controller.playFromList(tracks[0], tracks, 'Baseline');
        await waitFor(() => handler.player.state.position.inMilliseconds > 500);
        await handler.pause();
        await db.setFavorite(tracks[0].id, true);
        await waitFor(
          () =>
              container.read(playerControllerProvider).current?.isFavorite ==
              true,
        );
        await db.setFavorite(tracks[0].id, false);
        await waitFor(
          () =>
              container.read(playerControllerProvider).current?.isFavorite ==
              false,
        );
        debugPrint('TEST_AUDIO_FILTERS');
        await audioSettings.setEqEnabled(true);
        await audioSettings.setEqCurve([1, 2, 1, 0, -1, 0, 1, 0, 0, 0]);
        await audioSettings.setMono(true);
        await audioSettings.setCrossfeed(true);
        await controller.playFromList(tracks[0], tracks, 'Test queue');
        final native = handler.player.platform as NativePlayer;
        debugPrint('AF_CHAIN=${await native.getProperty('af')}');
        await waitFor(() => handler.player.state.position.inMilliseconds > 500);
        expect(handler.playing, true);
        expect(handler.player.state.duration.inMilliseconds, greaterThan(4000));
        await audioSettings.setMono(false);
        await audioSettings.setCrossfeed(true);
        debugPrint('TEST_PRIVATE_SESSION');
        await controller.setPrivateSession(true);
        await controller.playFromList(tracks[1], tracks, 'Private');
        await tester.pump(const Duration(seconds: 2));
        await controller.flushState();
        expect((await db.trackById(tracks[1].id))!.totalPlayCount, 0);
        expect(
          await (db.select(
            db.listeningSessions,
          )..where((s) => s.trackId.equals(tracks[1].id))).get(),
          isEmpty,
        );
        await controller.setPrivateSession(false);
        await audioSettings.setCrossfeed(false);
        await audioSettings.setEqEnabled(false);
        debugPrint('TEST_GAPLESS');
        await audioSettings.setGapless(true);
        await controller.playFromList(tracks[0], tracks, 'Gapless');
        await waitFor(
          () =>
              container.read(playerControllerProvider).current?.id ==
              tracks[1].id,
        );
        expect(
          handler.player.state.playlist.medias.length,
          lessThanOrEqualTo(2),
        );
        expect(container.read(playerControllerProvider).contextIndex, 1);
        controller.addToQueue(tracks[0]);
        await waitFor(
          () =>
              container.read(playerControllerProvider).current?.id ==
              tracks[0].id,
        );
        expect(container.read(playerControllerProvider).manualQueue, isEmpty);
        controller.clearQueue();
        expect(
          container.read(playerControllerProvider).upcomingContext,
          isEmpty,
        );
        await handler.pause();
        // Repeated short transitions let an external ADB runner force screen-off/doze.
        await controller.playFromList(tracks[0], tracks, 'Sleep test');
        while (container.read(playerControllerProvider).repeat !=
            RepeatMode.all) {
          controller.cycleRepeat();
        }
        await tester.pump(const Duration(milliseconds: 300));
        debugPrint('SCREEN_OFF_TEST_READY');
        final firstPlays = (await db.watchPlayCount().first);
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          if (!handler.playing) {
            await waitFor(() => handler.playing, seconds: 2);
          }
          expect(
            handler.player.state.playlist.medias.length,
            lessThanOrEqualTo(2),
          );
        }
        await controller.flushState();
        expect(await db.watchPlayCount().first, greaterThan(firstPlays + 4));
        debugPrint('SCREEN_OFF_TEST_FINISHED');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await handler.pause();
        appRouter.go('/library');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Tracks').first);
        await tester.tap(find.text('Tracks').first);
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        final shot = await binding.takeScreenshot('library-10053');
        final imageBytes = shot;
        await File('${temp.path}/library-10053.png').writeAsBytes(imageBytes);
        debugPrint('EMULATOR_SCREENSHOT_PATH=${temp.path}/library-10053.png');
        appRouter.go('/equalizer');
        await tester.pumpAndSettle();
        await binding.takeScreenshot('equalizer');
        appRouter.go('/settings');
        await tester.pumpAndSettle();
        await tester.tap(find.text('About').last);
        await tester.pumpAndSettle();
        await binding.takeScreenshot('about');
        expect(tester.takeException(), isNull);
      } catch (e, s) {
        debugPrint('ORIGINAL_TEST_FAILURE=$e\n$s');
        rethrow;
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

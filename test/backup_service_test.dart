import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/features/settings/services/backup_service.dart';

void main() {
  late Directory dir, docs, support;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('electrowave_backup_');
    docs = await Directory('${dir.path}/docs').create();
    support = await Directory('${dir.path}/support').create();
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<AppDatabase> create(String path, String title) async {
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            filePath: '/music/$title.mp3',
            title: title,
            artist: 'Artist',
            album: 'Album',
            durationMs: 2000,
          ),
        );
    return db;
  }

  test(
    'complete backup restores settings, queue and artwork; safety copy can undo it',
    () async {
      final live = '${docs.path}/electrowave.db';
      var db = await create(live, 'Original');
      await File(
        '${support.path}/settings.json',
      ).writeAsString('{"themeMode":"light","eqEnabled":true}');
      await File(
        '${support.path}/playback_state.json',
      ).writeAsString('{"currentTrackId":1}');
      await File(
        '${support.path}/library.json',
      ).writeAsString('{"folders":["/Music"]}');
      await Directory('${docs.path}/albumart').create();
      await File('${docs.path}/albumart/test.jpg').writeAsBytes([1, 2, 3]);
      final backup = await BackupService(
        db,
        documents: docs,
        supportDirectory: support,
      ).createBackup();
      await (db.update(db.tracks)..where((t) => t.id.equals(1))).write(
        const TracksCompanion(title: Value('Changed')),
      );
      await File(
        '${support.path}/settings.json',
      ).writeAsString('{"themeMode":"dark"}');
      await db.close();
      await BackupService.stageBytes(backup, documents: docs);
      expect(
        await BackupService.applyStagedImportIfAny(
          documents: docs,
          supportDirectory: support,
        ),
        true,
      );
      db = AppDatabase.forTesting(NativeDatabase(File(live)));
      expect((await db.watchLibrary().first).single.title, 'Original');
      expect(
        jsonDecode(
          await File('${support.path}/settings.json').readAsString(),
        )['themeMode'],
        'light',
      );
      expect(await File('${support.path}/playback_state.json').exists(), true);
      await db.close();
      final safety = await File(
        '${docs.path}/restore-safety.ewbackup',
      ).readAsBytes();
      await BackupService.stageBytes(safety, documents: docs);
      await BackupService.applyStagedImportIfAny(
        documents: docs,
        supportDirectory: support,
      );
      db = AppDatabase.forTesting(NativeDatabase(File(live)));
      expect((await db.watchLibrary().first).single.title, 'Changed');
      expect(
        jsonDecode(
          await File('${support.path}/settings.json').readAsString(),
        )['themeMode'],
        'dark',
      );
      await db.close();
    },
  );
  test(
    'full exports include default settings, folders and an empty queue',
    () async {
      final db = await create('${docs.path}/electrowave.db', 'Default');
      final bytes = await BackupService(
        db,
        documents: docs,
        supportDirectory: support,
      ).createBackup();
      final bundle = BackupBundle.decode(bytes);
      expect(
        bundle.files.keys,
        containsAll([
          'database',
          'settings.json',
          'library.json',
          'playback_state.json',
        ]),
      );
      expect(
        jsonDecode(
          utf8.decode(bundle.files['playback_state.json']!),
        )['currentTrackId'],
        isNull,
      );
      await db.close();
    },
  );
  test(
    'rejects foreign SQLite, corruption, future versions and unsafe entries before staging',
    () async {
      final foreign = '${dir.path}/foreign.db';
      final raw = sqlite3.open(foreign);
      raw.execute('PRAGMA user_version=1');
      raw.execute('CREATE TABLE other(id INTEGER)');
      raw.close();
      expect(
        () => BackupService.validateDatabase(foreign),
        throwsFormatException,
      );
      final db = await create('${docs.path}/electrowave.db', 'Keep me');
      await db.close();
      final file = File('${docs.path}/electrowave.db');
      final valid = await file.readAsBytes();
      final newer = sqlite3.open(file.path);
      newer.execute('PRAGMA user_version=999');
      newer.close();
      await expectLater(
        BackupService.stageBytes(await file.readAsBytes(), documents: docs),
        throwsFormatException,
      );
      await file.writeAsBytes(valid);
      await expectLater(
        BackupService.stageBytes([1, 2, 3], documents: docs),
        throwsA(anything),
      );
      final bad = BackupBundle({
        'database': Uint8List.fromList(valid),
        'albumart/../../escape': Uint8List(0),
      }).encode();
      await expectLater(
        BackupService.stageBytes(bad, documents: docs),
        throwsFormatException,
      );
      expect(await File('${docs.path}/$kStagedImportFileName').exists(), false);
      BackupService.validateDatabase(file.path);
    },
  );
  test(
    'interrupted restore journal rolls back originals before reopening',
    () async {
      final live = '${docs.path}/electrowave.db';
      final db = await create(live, 'Original');
      await db.close();
      final journal = await Directory('${docs.path}/restore-journal').create();
      await File(live).copy('${journal.path}/0');
      await File(
        '${journal.path}/manifest.json',
      ).writeAsString(jsonEncode([live]));
      await File(live).writeAsBytes([0, 1, 2]);
      expect(
        await BackupService.applyStagedImportIfAny(
          documents: docs,
          supportDirectory: support,
        ),
        false,
      );
      final restored = AppDatabase.forTesting(NativeDatabase(File(live)));
      expect((await restored.watchLibrary().first).single.title, 'Original');
      await restored.close();
    },
  );
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/backup_service.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.error, required this.retry});
  final Object error;
  final Future<void> Function() retry;
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool busy = false;
  String? message;
  Future<void> restore({bool safety = false, bool pick = false}) async {
    setState(() => busy = true);
    try {
      List<int>? bytes;
      if (pick) {
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        final file = result?.files.singleOrNull;
        if (file != null) {
          bytes = file.bytes ?? await File(file.path!).readAsBytes();
        }
      } else {
        final dir = safety
            ? await getApplicationDocumentsDirectory()
            : await getApplicationSupportDirectory();
        final file = File(
          '${dir.path}/${safety ? 'restore-safety' : 'last_automatic'}.ewbackup',
        );
        if (!await file.exists()) {
          throw StateError(
            'No ${safety ? 'safety' : 'automatic'} backup is available. Choose a backup file.',
          );
        }
        bytes = await file.readAsBytes();
      }
      if (bytes == null) return;
      await BackupService.stageBytes(bytes);
      // Preserve the damaged original and sidecars; never delete user data to recover.
      final docs = await getApplicationDocumentsDirectory();
      final quarantine = Directory(
        '${docs.path}/damaged-${DateTime.now().millisecondsSinceEpoch}',
      );
      await quarantine.create();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('${docs.path}/electrowave.db$suffix');
        if (await f.exists()) {
          await f.rename('${quarantine.path}/electrowave.db$suffix');
        }
      }
      await widget.retry();
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recover your library')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.restore, size: 56),
        const SizedBox(height: 24),
        const Text(
          'Electrowave could not open the library safely.',
          style: TextStyle(fontSize: 22),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your original database will be kept on this phone. Restore a verified backup to continue.',
        ),
        const SizedBox(height: 16),
        if (message != null) Text(message!),
        Text('${widget.error}'),
        FilledButton(
          onPressed: busy ? null : () => restore(),
          child: const Text('Restore last automatic backup'),
        ),
        OutlinedButton(
          onPressed: busy ? null : () => restore(safety: true),
          child: const Text('Restore safety copy'),
        ),
        TextButton(
          onPressed: busy ? null : () => restore(pick: true),
          child: const Text('Choose backup file'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  final docs = await getApplicationDocumentsDirectory();
                  final staged = File('${docs.path}/$kStagedImportFileName');
                  if (await staged.exists()) {
                    await staged.rename(
                      '${staged.path}.rejected-${DateTime.now().millisecondsSinceEpoch}',
                    );
                  }
                  await widget.retry();
                },
          child: const Text('Retry current library'),
        ),
      ],
    ),
  );
}

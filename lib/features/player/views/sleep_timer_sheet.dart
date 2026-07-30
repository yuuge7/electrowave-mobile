import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/format.dart';
import '../../../shared/widgets/track_context_menu.dart' show promptForText;
import '../providers/sleep_timer_provider.dart';

Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Sleep timer',
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: timer == null
                ? const Text('Off')
                : Text(timer.endOfTrack
                    ? 'Stops at the end of the current track'
                    : 'Stops in ${formatDuration(timer.remaining)}'),
            trailing: timer != null
                ? TextButton(
                    onPressed: () {
                      notifier.cancel();
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel timer'),
                  )
                : null,
          ),
          const Divider(height: 1),
          for (final minutes in const [15, 30, 45, 60])
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$minutes minutes'),
              onTap: () {
                notifier.startDuration(Duration(minutes: minutes));
                Navigator.pop(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Custom duration'),
            onTap: () async {
              final navigator = Navigator.of(context);
              final input = await promptForText(
                context,
                title: 'Sleep timer (minutes)',
                hint: 'e.g. 20',
                keyboardType: TextInputType.number,
              );
              final minutes = int.tryParse(input ?? '');
              if (minutes != null && minutes > 0) {
                notifier.startDuration(Duration(minutes: minutes));
              }
              navigator.pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('End of current track'),
            onTap: () {
              notifier.startEndOfTrack();
              Navigator.pop(context);
            },
          ),
          if (timer != null)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Extend +15 minutes'),
              onTap: () {
                notifier.extend15();
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

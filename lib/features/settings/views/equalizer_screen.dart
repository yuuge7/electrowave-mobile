import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../services/settings_persistence.dart';

/// Named presets, in dB per band, parallel to [kEqBandFrequencies]
/// (60 / 230 / 910 / 3600 / 14000 Hz).
const Map<String, List<double>> kEqPresets = {
  'Flat': [0, 0, 0, 0, 0],
  'Bass boost': [9, 5, 0, 0, 0],
  'Treble boost': [0, 0, 0, 5, 8],
  'Vocal': [-2, 0, 4, 3, 0],
  'Electronic': [7, 2, -2, 3, 6],
  'Loudness': [6, 2, -1, 2, 5],
};

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  String _bandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          TextButton(
            onPressed: controller.resetEq,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Equalizer'),
            subtitle: const Text('Applies to all playback'),
            value: settings.eqEnabled,
            onChanged: controller.setEqEnabled,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Presets', style: theme.textTheme.labelLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in kEqPresets.entries)
                  ActionChip(
                    label: Text(entry.key),
                    onPressed: () async {
                      for (var i = 0; i < entry.value.length; i++) {
                        await controller.setEqBand(i, entry.value[i]);
                      }
                      if (!settings.eqEnabled) {
                        await controller.setEqEnabled(true);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          // Vertical sliders, one per band, laid out like a hardware EQ.
          Opacity(
            opacity: settings.eqEnabled ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < kEqBandFrequencies.length; i++)
                    Column(
                      children: [
                        Text(
                          '${settings.eqGainsDb[i] > 0 ? '+' : ''}'
                          '${settings.eqGainsDb[i].toStringAsFixed(0)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        SizedBox(
                          height: 200,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: settings.eqGainsDb[i],
                              min: -kEqMaxGainDb,
                              max: kEqMaxGainDb,
                              divisions: (kEqMaxGainDb * 2).round(),
                              onChanged: settings.eqEnabled
                                  ? (value) => controller.setEqBand(i, value)
                                  : null,
                            ),
                          ),
                        ),
                        Text(_bandLabel(kEqBandFrequencies[i]),
                            style: theme.textTheme.bodySmall),
                        Text('Hz',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Volume normalization',
                style: theme.textTheme.labelLarge),
          ),
          RadioGroup<ReplayGainMode>(
            groupValue: settings.replayGain,
            onChanged: (mode) {
              if (mode != null) controller.setReplayGain(mode);
            },
            child: const Column(
              children: [
                RadioListTile<ReplayGainMode>(
                  value: ReplayGainMode.off,
                  title: Text('Off'),
                ),
                RadioListTile<ReplayGainMode>(
                  value: ReplayGainMode.track,
                  title: Text('Per track'),
                  subtitle: Text('Every track plays at a similar loudness'),
                ),
                RadioListTile<ReplayGainMode>(
                  value: ReplayGainMode.album,
                  title: Text('Per album'),
                  subtitle:
                      Text('Keeps an album’s internal dynamics intact'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'Normalization uses ReplayGain tags written by tools like foobar2000 '
              'or MusicBrainz Picard. Files without those tags play unchanged.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../services/settings_persistence.dart';
import '../../../shared/widgets/track_context_menu.dart';

/// Named presets, in dB per band, parallel to [kEqBandFrequencies]
/// (60 / 230 / 910 / 3600 / 14000 Hz).
const Map<String, List<double>> kEqPresets = {
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass boost': [8, 7, 5, 3, 1, 0, 0, 0, 0, 0],
  'Treble boost': [0, 0, 0, 0, 0, 0, 2, 4, 6, 8],
  'Vocal': [-3, -2, -1, 0, 2, 4, 4, 3, 1, 0],
  'Electronic': [7, 6, 4, 2, -1, -2, 0, 3, 5, 6],
  'Loudness': [6, 5, 3, 2, 0, -1, 0, 2, 4, 5],
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
          TextButton(onPressed: controller.resetEq, child: const Text('Reset')),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey(settings.eqProfile),
              initialValue: settings.eqProfile,
              decoration: const InputDecoration(labelText: 'Output profile'),
              items: const [
                DropdownMenuItem(value: 'speaker', child: Text('Speaker')),
                DropdownMenuItem(
                  value: 'headphones',
                  child: Text('Headphones'),
                ),
                DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
              ],
              onChanged: (v) {
                if (v != null) controller.setEqProfile(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: const Text('Save custom preset'),
            onTap: () async {
              final name = await promptForText(
                context,
                title: 'Save EQ preset',
                hint: 'Preset name',
              );
              if (name != null && name.trim().isNotEmpty) {
                await controller.saveEqPreset(name.trim());
              }
            },
          ),
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
                for (final entry in {
                  ...kEqPresets,
                  ...settings.eqPresets,
                }.entries)
                  ActionChip(
                    label: Text(entry.key),
                    onPressed: () async {
                      await controller.setEqCurve(entry.value);
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
              // One equal column per band: at their natural width the gain
              // readouts push the row past the screen on a narrow phone at a
              // large text scale.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 640,
                  child: Row(
                    children: [
                      for (var i = 0; i < kEqBandFrequencies.length; i++)
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${settings.eqGainsDb[i] > 0 ? '+' : ''}'
                                '${settings.eqGainsDb[i].toStringAsFixed(0)}',
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                              ),
                              SizedBox(
                                height: 200,
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    semanticFormatterCallback: (v) =>
                                        '${kEqBandFrequencies[i]} Hz, ${v.round()} decibels',
                                    value: settings.eqGainsDb[i],
                                    min: -kEqMaxGainDb,
                                    max: kEqMaxGainDb,
                                    divisions: (kEqMaxGainDb * 2).round(),
                                    onChanged: settings.eqEnabled
                                        ? (value) =>
                                              controller.setEqBand(i, value)
                                        : null,
                                  ),
                                ),
                              ),
                              Text(
                                _bandLabel(kEqBandFrequencies[i]),
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                              ),
                              Text(
                                'Hz',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Volume normalization',
              style: theme.textTheme.labelLarge,
            ),
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
                  subtitle: Text('Keeps an album’s internal dynamics intact'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'Normalization uses ReplayGain tags first, then gains calculated '
              'on this phone. Use Audio settings to analyze files without tags.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

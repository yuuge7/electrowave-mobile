import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/database/database.dart';

class AudioAnalysisResult {
  const AudioAnalysisResult(this.waveform, this.gainDb, this.lufs);
  final List<double> waveform;
  final double gainDb, lufs;
  Map<String, dynamic> toJson() => {
    'waveform': waveform,
    'gainDb': gainDb,
    'lufs': lufs,
  };
  static AudioAnalysisResult fromJson(Map json) => AudioAnalysisResult(
    (json['waveform'] as List).map((v) => (v as num).toDouble()).toList(),
    (json['gainDb'] as num).toDouble(),
    (json['lufs'] as num).toDouble(),
  );
}

class AudioAnalyzer {
  static const channel = MethodChannel('electrowave/platform');
  static final Map<String, Future<AudioAnalysisResult>> _pending = {};
  static Future<AudioAnalysisResult> analyze(Track track) async {
    final stat = await File(track.filePath).stat();
    final key =
        '${track.id}-${stat.size}-${stat.modified.millisecondsSinceEpoch}';
    return _pending
        .putIfAbsent(key, () => _analyze(track, key))
        .whenComplete(() => _pending.remove(key));
  }

  static Future<AudioAnalysisResult> _analyze(Track track, String key) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/analysis');
    await dir.create(recursive: true);
    final cache = File('${dir.path}/$key.json');
    if (await cache.exists()) {
      return AudioAnalysisResult.fromJson(
        jsonDecode(await cache.readAsString()) as Map,
      );
    }
    final json = await channel.invokeMapMethod<String, dynamic>('analyze', {
      'path': track.filePath,
    });
    if (json == null) throw StateError('Audio analysis unavailable');
    final result = AudioAnalysisResult.fromJson(json);
    await cache.writeAsString(jsonEncode(result.toJson()), flush: true);
    return result;
  }
}

final waveformProvider = FutureProvider.autoDispose.family<List<double>, Track>(
  (ref, track) async => (await AudioAnalyzer.analyze(track)).waveform,
);

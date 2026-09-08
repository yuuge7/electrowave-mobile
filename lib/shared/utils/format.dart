String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatDurationMs(int ms) => formatDuration(Duration(milliseconds: ms));

/// Long-form listening time: "3h 24m" / "45m" / "12s".
String formatListeningTime(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  return '${d.inSeconds}s';
}

/// Playback rate as it is written on a control: "1×", "1.5×", "0.75×".
///
/// The stored value is a double, so `'$rate×'` prints "1.0×" and "2.0×" — a
/// trailing zero on a speed dial reads as precision that isn't there.
String formatPlaybackRate(double rate) {
  final text = rate.toStringAsFixed(2);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'\.?0+$'), '')
      : text;
}

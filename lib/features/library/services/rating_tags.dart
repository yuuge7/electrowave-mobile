import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

int _syncSize(List<int> bytes, int at) =>
    (bytes[at] << 21) |
    (bytes[at + 1] << 14) |
    (bytes[at + 2] << 7) |
    bytes[at + 3];
List<int> _sync(int n) => [
  (n >> 21) & 127,
  (n >> 14) & 127,
  (n >> 7) & 127,
  n & 127,
];

/// Preserve every frame and every audio byte; replace only our POPM frame.
Uint8List writeMp3Rating(Uint8List original, int stars) {
  if (stars < 0 || stars > 5) throw RangeError.range(stars, 0, 5);
  final tagged =
      original.length >= 10 &&
      ascii.decode(original.sublist(0, 3), allowInvalid: true) == 'ID3';
  final version = tagged ? original[3] : 4;
  if (version != 3 && version != 4) {
    throw const FormatException('Unsupported ID3 version');
  }
  if (tagged && original[5] != 0) {
    throw const FormatException('ID3 flags are not supported for rating edits');
  }
  final end = tagged ? 10 + _syncSize(original, 6) : 0;
  if (end > original.length) throw const FormatException('Truncated ID3 tag');
  final frames = BytesBuilder();
  var at = 10;
  while (tagged && at + 10 <= end && original[at] != 0) {
    final name = ascii.decode(original.sublist(at, at + 4), allowInvalid: true);
    final size = version == 4
        ? _syncSize(original, at + 4)
        : ByteData.sublistView(original).getUint32(at + 4);
    if (size < 0 || at + 10 + size > end) {
      throw const FormatException('Damaged ID3 frame');
    }
    final payload = original.sublist(at + 10, at + 10 + size);
    final ours =
        name == 'POPM' &&
        utf8.decode(
              payload.takeWhile((b) => b != 0).toList(),
              allowMalformed: true,
            ) ==
            'electrowave@local';
    if (!ours) frames.add(original.sublist(at, at + 10 + size));
    at += 10 + size;
  }
  final payload = [
    ...utf8.encode('electrowave@local'),
    0,
    [0, 1, 64, 128, 196, 255][stars],
    0,
    0,
    0,
    0,
  ];
  final size = version == 4 ? _sync(payload.length) : [0, 0, 0, payload.length];
  frames.add([...ascii.encode('POPM'), ...size, 0, 0, ...payload]);
  final body = frames.takeBytes();
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    version,
    0,
    0,
    ..._sync(body.length),
    ...body,
    ...original.sublist(end),
  ]);
}

int? readMp3Rating(Uint8List data) {
  if (data.length < 10 ||
      String.fromCharCodes(data.take(3)) != 'ID3' ||
      (data[3] != 3 && data[3] != 4) ||
      data[5] != 0) {
    return null;
  }
  final end = (10 + _syncSize(data, 6)).clamp(0, data.length);
  var at = 10;
  int? fallback;
  while (at + 10 <= end && data[at] != 0) {
    final size = data[3] == 4
        ? _syncSize(data, at + 4)
        : ByteData.sublistView(data).getUint32(at + 4);
    if (at + 10 + size > end) return null;
    if (String.fromCharCodes(data.sublist(at, at + 4)) == 'POPM') {
      final payload = data.sublist(at + 10, at + 10 + size);
      final zero = payload.indexOf(0);
      if (zero >= 0 && zero + 1 < payload.length) {
        final v = payload[zero + 1];
        final stars = v == 0
            ? 0
            : v < 32
            ? 1
            : v < 96
            ? 2
            : v < 160
            ? 3
            : v < 224
            ? 4
            : 5;
        if (utf8.decode(payload.sublist(0, zero), allowMalformed: true) ==
            'electrowave@local') {
          return stars;
        }
        fallback ??= stars;
      }
    }
    at += 10 + size;
  }
  return fallback;
}

/// Read only the ID3 prefix, rather than loading an entire music file to scan it.
int? readMp3FileRating(File file) {
  final input = file.openSync();
  try {
    final header = input.readSync(10);
    if (header.length < 10 || String.fromCharCodes(header.take(3)) != 'ID3') {
      return null;
    }
    final size = _syncSize(header, 6);
    if (size > 16 * 1024 * 1024) return null;
    return readMp3Rating(
      Uint8List.fromList([...header, ...input.readSync(size)]),
    );
  } finally {
    input.closeSync();
  }
}

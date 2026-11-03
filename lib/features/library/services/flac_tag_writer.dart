import 'dart:convert';
import 'dart:typed_data';

/// Rewrite only named Vorbis comments (RFC 9639 section 8.6). Preserve the
/// vendor, unedited comments, every other metadata block and all audio bytes.
Uint8List rewriteFlacComments(Uint8List source, Map<String, String?> edits) {
  if (source.length < 42 || String.fromCharCodes(source.take(4)) != 'fLaC') {
    throw const FormatException('Invalid FLAC header');
  }
  final updates = {for (final e in edits.entries) e.key.toUpperCase(): e.value};
  if (updates.isEmpty) return source;
  final blocks = <({int type, Uint8List bytes})>[];
  var at = 4, commentIndex = -1;
  var last = false;
  while (!last) {
    if (at + 4 > source.length) {
      throw const FormatException('Truncated FLAC metadata');
    }
    last = source[at] & 128 != 0;
    final type = source[at] & 127;
    final length =
        (source[at + 1] << 16) | (source[at + 2] << 8) | source[at + 3];
    at += 4;
    if (type == 127 ||
        at + length > source.length ||
        (blocks.isEmpty && (type != 0 || length != 34))) {
      throw const FormatException('Invalid FLAC metadata block');
    }
    if (type == 4) {
      if (commentIndex != -1) {
        throw const FormatException('Multiple FLAC comment blocks');
      }
      commentIndex = blocks.length;
    }
    blocks.add((
      type: type,
      bytes: Uint8List.sublistView(source, at, at + length),
    ));
    at += length;
  }
  final audioStart = at;
  Uint8List vendor = Uint8List.fromList(utf8.encode('Electrowave'));
  final comments = <Uint8List>[];
  if (commentIndex != -1) {
    final bytes = blocks[commentIndex].bytes;
    var offset = 0;
    int number() {
      if (offset + 4 > bytes.length) {
        throw const FormatException('Truncated FLAC comments');
      }
      final value = ByteData.sublistView(
        bytes,
      ).getUint32(offset, Endian.little);
      offset += 4;
      return value;
    }

    Uint8List string() {
      final size = number();
      if (offset + size > bytes.length) {
        throw const FormatException('Truncated FLAC comment value');
      }
      final value = Uint8List.sublistView(bytes, offset, offset + size);
      offset += size;
      return value;
    }

    vendor = string();
    final count = number();
    if (count > (bytes.length - offset) ~/ 4) {
      throw const FormatException('Invalid FLAC comment count');
    }
    for (var i = 0; i < count; i++) {
      final comment = string();
      final equal = comment.indexOf(61);
      final name = equal < 0
          ? ''
          : ascii
                .decode(comment.sublist(0, equal), allowInvalid: true)
                .toUpperCase();
      if (!updates.containsKey(name)) comments.add(comment);
    }
    if (offset != bytes.length) {
      throw const FormatException('Unexpected FLAC comment data');
    }
  }
  for (final entry in updates.entries) {
    if (entry.value != null && entry.value!.isNotEmpty) {
      comments.add(
        Uint8List.fromList(utf8.encode('${entry.key}=${entry.value}')),
      );
    }
  }
  final payload = BytesBuilder(copy: false);
  void number(int value) => payload.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  number(vendor.length);
  payload.add(vendor);
  number(comments.length);
  for (final comment in comments) {
    number(comment.length);
    payload.add(comment);
  }
  final replacement = (type: 4, bytes: payload.takeBytes());
  if (replacement.bytes.length > 0xffffff) {
    throw const FormatException(
      'FLAC comments exceed the metadata block limit',
    );
  }
  if (commentIndex == -1) {
    blocks.insert(1, replacement);
  } else {
    blocks[commentIndex] = replacement;
  }
  final result = BytesBuilder(copy: false)..add(source.sublist(0, 4));
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i], size = block.bytes.length;
    result.add([
      block.type | (i == blocks.length - 1 ? 128 : 0),
      (size >> 16) & 255,
      (size >> 8) & 255,
      size & 255,
    ]);
    result.add(block.bytes);
  }
  result.add(Uint8List.sublistView(source, audioStart));
  return result.takeBytes();
}

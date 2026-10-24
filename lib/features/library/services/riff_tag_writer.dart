import 'dart:convert';
import 'dart:typed_data';

/// Tag rewriting for RIFF/WAVE files that leaves every other byte alone.
///
/// Exists because audio_metadata_reader's RiffWriter (1.6.0 through 1.8.1)
/// corrupts the audio: its read buffer pre-fills 16 KB, then the writer
/// rewinds the file underneath it, so the `data` chunk is rebuilt from the
/// wrong offsets — the file header and the opening samples get spliced into
/// the audio after the first 16 KB.
///
/// Here the file is walked chunk by chunk and copied verbatim, except for
/// the `LIST`/`INFO` chunk (rebuilt with the edited fields) and an embedded
/// `id3 ` chunk (handed to [RiffTagEdit.rewriteId3], since readers prefer it
/// over INFO when both are present).
class RiffTagEdit {
  const RiffTagEdit({required this.info, this.rewriteId3});

  /// INFO fields to set, keyed by four-character id (`INAM`, `IART`, ...).
  /// An empty value removes the field. Fields not listed are kept as they are.
  final Map<String, String> info;

  /// Rewrites the payload of an `id3 `/`ID3 ` chunk (a complete ID3v2 tag).
  /// Null leaves such a chunk untouched.
  final Uint8List Function(Uint8List tag)? rewriteId3;
}

bool isRiffWave(Uint8List bytes) =>
    bytes.length >= 12 &&
    _fourCc(bytes, 0) == 'RIFF' &&
    _fourCc(bytes, 8) == 'WAVE';

/// Returns [bytes] with [edit] applied. Throws [FormatException] when [bytes]
/// is not a RIFF/WAVE file.
Uint8List rewriteRiffTags(Uint8List bytes, RiffTagEdit edit) {
  if (!isRiffWave(bytes)) {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  final view = ByteData.sublistView(bytes);
  final out = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(bytes, 0, 12));
  var infoWritten = false;
  var offset = 12;

  while (offset + 8 <= bytes.length) {
    final id = _fourCc(bytes, offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final dataStart = offset + 8;
    // A truncated last chunk keeps whatever is there.
    final dataEnd = _min(dataStart + size, bytes.length);
    final chunkEnd = _min(dataEnd + (size.isOdd ? 1 : 0), bytes.length);

    final isInfo =
        id == 'LIST' &&
        size >= 4 &&
        dataStart + 4 <= dataEnd &&
        _fourCc(bytes, dataStart) == 'INFO';
    if (isInfo) {
      // Duplicate INFO lists collapse into the first one.
      if (!infoWritten) {
        out.add(
          _infoChunk(
            Uint8List.sublistView(bytes, dataStart + 4, dataEnd),
            edit.info,
          ),
        );
        infoWritten = true;
      }
    } else if ((id == 'id3 ' || id == 'ID3 ') && edit.rewriteId3 != null) {
      final tag = edit.rewriteId3!(
        Uint8List.fromList(Uint8List.sublistView(bytes, dataStart, dataEnd)),
      );
      out.add(_chunk(id, tag));
    } else {
      if (id == 'data' && !infoWritten) {
        // No INFO list so far: put one ahead of the audio rather than after
        // it, where a data chunk with a stale size would swallow it.
        out.add(_infoChunk(Uint8List(0), edit.info));
        infoWritten = true;
      }
      out.add(Uint8List.sublistView(bytes, offset, chunkEnd));
    }
    offset = chunkEnd;
  }

  // Fewer than 8 trailing bytes: not a chunk, but not ours to drop either.
  if (offset < bytes.length) {
    out.add(Uint8List.sublistView(bytes, offset));
  }
  if (!infoWritten) {
    if (out.length.isOdd) out.addByte(0);
    out.add(_infoChunk(Uint8List(0), edit.info));
  }

  final result = out.toBytes();
  ByteData.sublistView(result).setUint32(4, result.length - 8, Endian.little);
  return result;
}

/// A `LIST`/`INFO` chunk: the fields already in [payload] in their original
/// order and encoding, with [updates] applied on top.
Uint8List _infoChunk(Uint8List payload, Map<String, String> updates) {
  final fields = <(String, Uint8List)>[];
  final view = ByteData.sublistView(payload);
  var offset = 0;
  while (offset + 8 <= payload.length) {
    final id = _fourCc(payload, offset);
    final size = view.getUint32(offset + 4, Endian.little);
    if (offset + 8 + size > payload.length) break;
    fields.add((
      id,
      Uint8List.sublistView(payload, offset + 8, offset + 8 + size),
    ));
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }

  updates.forEach((id, value) {
    final at = fields.indexWhere((field) => field.$1 == id);
    fields.removeWhere((field) => field.$1 == id);
    if (value.isEmpty) return;
    final field = (id, _encodeText(value));
    if (at < 0) {
      fields.add(field);
    } else {
      fields.insert(at, field);
    }
  });

  final body = BytesBuilder(copy: false)..add(ascii.encode('INFO'));
  for (final (id, data) in fields) {
    body.add(_chunk(id, data));
  }
  return _chunk('LIST', body.toBytes());
}

/// INFO strings are NUL-terminated. Latin-1 is what readers (including
/// audio_metadata_reader) decode them as; UTF-8 is the fallback for text
/// Latin-1 cannot hold.
Uint8List _encodeText(String value) {
  final fitsLatin1 = value.codeUnits.every((unit) => unit <= 0xFF);
  final encoded = fitsLatin1 ? latin1.encode(value) : utf8.encode(value);
  return Uint8List(encoded.length + 1)..setRange(0, encoded.length, encoded);
}

Uint8List _chunk(String id, Uint8List data) {
  final padded = data.length + (data.length.isOdd ? 1 : 0);
  final chunk = Uint8List(8 + padded)
    ..setRange(0, 4, ascii.encode(id))
    ..setRange(8, 8 + data.length, data);
  ByteData.sublistView(chunk).setUint32(4, data.length, Endian.little);
  return chunk;
}

String _fourCc(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes, offset, offset + 4);

int _min(int a, int b) => a < b ? a : b;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:electrowave_mobile/features/library/services/tag_writer.dart';
import 'package:electrowave_mobile/features/library/services/library_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Tag edits must change the tags and nothing else. WAV gets the closest
/// look: audio_metadata_reader's own RiffWriter splices the file header into
/// the samples past the first 16 KB, which is why the app has its own.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tag_writer');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> write(String name, List<int> bytes) =>
      File(p.join(dir.path, name)).writeAsBytes(bytes);

  const edit = TagEdit(
    title: 'Low Orbit (Edit)',
    artist: 'Aurora Drift',
    album: 'Nightfield',
    genre: 'Ambient',
    trackNumber: 2,
    year: 2024,
  );

  group('WAV', () {
    test(
      'rating round trips through the scanner without changing samples',
      () async {
        final audio = _noise(8000);
        final file = await write('rated.wav', _wav(audio));
        expect(
          applyTagEditToFile(file.path, const TagEdit(rating: 5)),
          TagFileResult.written,
        );
        expect(_chunkData(await file.readAsBytes(), 'data'), audio);
        expect(parseTags(file.path).rating, 5);
        applyTagEditToFile(file.path, const TagEdit(rating: 0));
        expect(parseTags(file.path).rating, 0);
      },
    );
    test('rewrites INFO and leaves the audio byte-identical', () async {
      final audio = _noise(200000);
      final file = await write(
        'a.wav',
        _wav(
          audio,
          info: {
            'INAM': 'Low Orbit',
            'IART': 'Someone',
            'IGNR': 'Test Tones',
            'ICMT': 'keep me',
          },
        ),
      );

      expect(applyTagEditToFile(file.path, edit), TagFileResult.written);

      final bytes = await file.readAsBytes();
      expect(_chunkData(bytes, 'data'), audio);
      expect(_info(bytes), {
        'INAM': 'Low Orbit (Edit)',
        'IART': 'Aurora Drift',
        'IGNR': 'Ambient',
        'ICMT': 'keep me',
        'IPRD': 'Nightfield',
        'ITRK': '2',
        'ICRD': '2024',
      });
      expect(
        ByteData.sublistView(bytes).getUint32(4, Endian.little),
        bytes.length - 8,
      );

      final meta = readMetadata(file);
      expect(meta.title, 'Low Orbit (Edit)');
      expect(meta.artist, 'Aurora Drift');
      expect(meta.album, 'Nightfield');
      expect(meta.genres, ['Ambient']);
      expect(meta.duration, const Duration(seconds: 25));
    });

    test('adds an INFO list ahead of the audio when there is none', () async {
      final audio = _noise(40001); // odd: exercises the pad byte
      final file = await write('b.wav', _wav(audio));

      expect(applyTagEditToFile(file.path, edit), TagFileResult.written);

      final bytes = await file.readAsBytes();
      expect(_chunkIds(bytes), ['fmt ', 'LIST', 'data']);
      expect(_chunkData(bytes, 'data'), audio);
      expect(readMetadata(file).title, 'Low Orbit (Edit)');
    });

    test('updates an embedded ID3 chunk, which readers prefer', () async {
      final audio = _noise(70000);
      final file = await write(
        'c.wav',
        _wav(audio, info: {'INAM': 'Old'}, id3: _id3({'TIT2': 'Old'})),
      );
      expect(readMetadata(file).title, 'Old');

      expect(applyTagEditToFile(file.path, edit), TagFileResult.written);

      final bytes = await file.readAsBytes();
      expect(_chunkData(bytes, 'data'), audio);
      final meta = readMetadata(file);
      expect(meta.title, 'Low Orbit (Edit)');
      expect(meta.artist, 'Aurora Drift');
    });

    test('keeps unknown chunks and non-Latin-1 text survives', () async {
      final audio = _noise(30000);
      final file = await write(
        'd.wav',
        _wav(audio, extra: {'bext': Uint8List.fromList(List.filled(33, 7))}),
      );

      applyTagEditToFile(file.path, const TagEdit(title: 'Beyoncé — 夜'));

      final bytes = await file.readAsBytes();
      expect(_chunkData(bytes, 'bext'), List.filled(33, 7));
      expect(_chunkData(bytes, 'data'), audio);
      expect(_info(bytes)['INAM'], 'Beyoncé — 夜');
    });

    test('an edit that changes nothing is reported as such', () async {
      final file = await write('e.wav', _wav(_noise(1000)));
      applyTagEditToFile(file.path, edit);
      expect(applyTagEditToFile(file.path, edit), TagFileResult.unchanged);
    });
  });

  test('FLAC rating metadata preserves the opaque audio payload', () async {
    // Metadata-only fixture: the tag writer must not interpret audio frames.
    final streamInfo = ByteData(34)
      ..setUint16(0, 16)
      ..setUint16(2, 4096)
      ..setUint64(10, (44100 << 44) | (1 << 41) | (15 << 36) | 44100);
    final audio = _noise(300);
    final comments = BytesBuilder();
    void number(int value) => comments.add(
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
    );
    final vendor = utf8.encode('Existing vendor');
    number(vendor.length);
    comments.add(vendor);
    number(2);
    for (final value in ['CUSTOM=keep this', 'REPLAYGAIN_TRACK_GAIN=-3.0 dB']) {
      final bytes = utf8.encode(value);
      number(bytes.length);
      comments.add(bytes);
    }
    final commentBytes = comments.takeBytes();
    final file = await write('rated.flac', [
      ...ascii.encode('fLaC'),
      0,
      0,
      0,
      34,
      ...streamInfo.buffer.asUint8List(),
      132,
      (commentBytes.length >> 16) & 255,
      (commentBytes.length >> 8) & 255,
      commentBytes.length & 255,
      ...commentBytes,
      ...audio,
    ]);
    expect(
      applyTagEditToFile(file.path, const TagEdit(rating: 4)),
      TagFileResult.written,
    );
    expect(parseTags(file.path).rating, 4);
    applyTagEditToFile(
      file.path,
      const TagEdit(title: 'Retitled', albumArtist: 'Compilation'),
    );
    expect(parseTags(file.path).rating, 4);
    expect(parseTags(file.path).title, 'Retitled');
    expect(parseTags(file.path).albumArtist, 'Compilation');
    final metadata = readAllMetadata(file) as VorbisMetadata;
    expect(metadata.unknowns['CUSTOM'], 'keep this');
    expect(metadata.replayGainTrackGain, ['-3.0 dB']);
    final result = await file.readAsBytes();
    expect(result.sublist(50, 50 + vendor.length), vendor);
    expect(result.sublist(result.length - audio.length), audio);
  });

  group('MP3', () {
    const fixtures = 'test_files/same_song';

    test('writes tags and keeps every audio frame', () async {
      final original = await File(
        '$fixtures/2-add-after/Night Drive.mp3',
      ).readAsBytes();
      final file = await write('a.mp3', original);
      final before = readMetadata(file);

      expect(applyTagEditToFile(file.path, edit), TagFileResult.written);

      final bytes = await file.readAsBytes();
      expect(_afterId3(bytes), _afterId3(original));
      final meta = readMetadata(file);
      expect(meta.title, 'Low Orbit (Edit)');
      expect(meta.artist, 'Aurora Drift');
      expect(meta.album, 'Nightfield');
      expect(meta.year?.year, 2024);
      // The writer adds a TLEN frame, which is millisecond precision.
      expect(meta.duration!.inMilliseconds, before.duration!.inMilliseconds);
    });

    test('an untagged MP3 has no writer and is left alone', () async {
      final original = await File(
        '$fixtures/2-add-after/Paper Moon.mp3',
      ).readAsBytes();
      final file = await write('b.mp3', original);

      expect(applyTagEditToFile(file.path, edit), TagFileResult.unsupported);
      expect(await file.readAsBytes(), original);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

Uint8List _noise(int length) {
  final random = Random(length);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// 8 kHz, 8-bit mono PCM: 8000 bytes per second.
Uint8List _wav(
  Uint8List audio, {
  Map<String, String>? info,
  Uint8List? id3,
  Map<String, Uint8List> extra = const {},
}) {
  final fmt = ByteData(16)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint32(4, 8000, Endian.little)
    ..setUint32(8, 8000, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 8, Endian.little);

  final body = BytesBuilder()
    ..add(ascii.encode('WAVE'))
    ..add(_chunk('fmt ', fmt.buffer.asUint8List()));
  if (info != null) {
    final list = BytesBuilder()..add(ascii.encode('INFO'));
    info.forEach(
      (id, value) => list.add(_chunk(id, [...latin1.encode(value), 0])),
    );
    body.add(_chunk('LIST', list.toBytes()));
  }
  extra.forEach((id, data) => body.add(_chunk(id, data)));
  if (id3 != null) body.add(_chunk('id3 ', id3));
  body.add(_chunk('data', audio));

  final payload = body.toBytes();
  return Uint8List.fromList([
    ...ascii.encode('RIFF'),
    ..._u32le(payload.length),
    ...payload,
  ]);
}

List<int> _chunk(String id, List<int> data) => [
  ...ascii.encode(id),
  ..._u32le(data.length),
  ...data,
  if (data.length.isOdd) 0,
];

List<int> _u32le(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

/// Minimal ID3v2.3 tag with text frames.
Uint8List _id3(Map<String, String> frames) {
  final body = BytesBuilder();
  frames.forEach((id, text) {
    final data = [0, ...latin1.encode(text)];
    body
      ..add(ascii.encode(id))
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add([0, 0])
      ..add(data);
  });
  final size = body.length;
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    3,
    0,
    0,
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...body.toBytes(),
  ]);
}

// ---------------------------------------------------------------------------
// Readers
// ---------------------------------------------------------------------------

Iterable<(String, Uint8List)> _chunks(Uint8List bytes) sync* {
  final view = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, offset, offset + 4);
    final size = view.getUint32(offset + 4, Endian.little);
    yield (id, Uint8List.sublistView(bytes, offset + 8, offset + 8 + size));
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
}

List<String> _chunkIds(Uint8List bytes) => [
  for (final c in _chunks(bytes)) c.$1,
];

Uint8List _chunkData(Uint8List bytes, String id) =>
    _chunks(bytes).firstWhere((c) => c.$1 == id).$2;

Map<String, String> _info(Uint8List bytes) {
  final list = _chunks(bytes)
      .firstWhere(
        (c) => c.$1 == 'LIST' && ascii.decode(c.$2.sublist(0, 4)) == 'INFO',
      )
      .$2;
  final view = ByteData.sublistView(list);
  final fields = <String, String>{};
  var offset = 4;
  while (offset + 8 <= list.length) {
    final id = String.fromCharCodes(list, offset, offset + 4);
    final size = view.getUint32(offset + 4, Endian.little);
    var data = list.sublist(offset + 8, offset + 8 + size);
    if (data.isNotEmpty && data.last == 0) {
      data = data.sublist(0, data.length - 1);
    }
    fields[id] = data.every((b) => b < 0x80)
        ? ascii.decode(data)
        : (_isUtf8(data) ? utf8.decode(data) : latin1.decode(data));
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return fields;
}

bool _isUtf8(List<int> data) {
  try {
    utf8.decode(data);
    return true;
  } on FormatException {
    return false;
  }
}

/// Everything after the leading ID3v2 tag — the audio frames.
Uint8List _afterId3(Uint8List bytes) {
  if (String.fromCharCodes(bytes, 0, 3) != 'ID3') return bytes;
  final size = (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
  final footer = (bytes[5] & 0x10) != 0 ? 10 : 0;
  return Uint8List.sublistView(bytes, 10 + size + footer);
}

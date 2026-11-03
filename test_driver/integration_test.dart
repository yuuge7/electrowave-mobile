import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final dir = Directory('docs/testing');
          await dir.create(recursive: true);
          await File('${dir.path}/$name.png').writeAsBytes(bytes);
          return bytes.length > 1000;
        },
    responseDataCallback: (data) async {
      final copy = Map<String, dynamic>.from(data ?? {})..remove('screenshots');
      await File(
        'docs/testing/emulator-result.json',
      ).writeAsString(jsonEncode(copy));
    },
  );
}

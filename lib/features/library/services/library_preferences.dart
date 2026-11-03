import 'dart:convert';
import 'dart:io';
import '../../../core/services/local_log.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/database/database.dart';

class LibraryPreferences {
  const LibraryPreferences({
    this.folders = const [],
    this.sort = LibrarySort.title,
    this.descending = false,
  });
  final List<String> folders;
  final LibrarySort sort;
  final bool descending;
  Map<String, dynamic> toJson() => {
    'folders': folders,
    'sort': sort.name,
    'descending': descending,
  };
  static Future<LibraryPreferences> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final json =
          jsonDecode(await File('${dir.path}/library.json').readAsString())
              as Map;
      return LibraryPreferences(
        folders: (json['folders'] as List? ?? []).whereType<String>().toList(),
        sort: LibrarySort.values.firstWhere(
          (s) => s.name == json['sort'],
          orElse: () => LibrarySort.title,
        ),
        descending: json['descending'] == true,
      );
    } catch (_) {
      return const LibraryPreferences();
    }
  }

  static Future<void> _pending = Future.value();
  Future<void> save() {
    _pending = _pending
        .then((_) async {
          final dir = await getApplicationSupportDirectory();
          final file = File('${dir.path}/library.json.tmp');
          await file.writeAsString(jsonEncode(toJson()), flush: true);
          await file.rename('${dir.path}/library.json');
        })
        .catchError((Object e, StackTrace s) {
          LocalLog.record(e, s);
        });
    return _pending;
  }
}

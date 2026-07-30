import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Overridden in main() after the staged-import bootstrap has run.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// True when a staged backup import was applied during this launch.
/// Overridden in main().
final importAppliedProvider = Provider<bool>((ref) => false);

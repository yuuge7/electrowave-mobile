import 'dart:convert';

/// A smart playlist is a saved query, not a list of tracks: the rules below
/// are stored as JSON on the playlist row and re-evaluated against the library
/// every time the list is opened.

enum SmartField {
  title,
  artist,
  album,
  genre,
  year,
  durationMinutes,
  playCount,
  listenedMinutes,
  lastPlayed,
  dateAdded,
  favorite,
}

enum SmartOperator {
  contains,
  equals,
  greaterThan,
  lessThan,

  /// Date fields: within the last N days / not in the last N days.
  within,
  notWithin,

  /// Date fields: the track has never been played.
  never,
  isTrue,
  isFalse,
}

enum SmartFieldKind { text, number, date, boolean }

enum SmartSort {
  title,
  artist,
  dateAdded,
  playCount,
  lastPlayed,
  listenedTime,
  random,
}

extension SmartFieldInfo on SmartField {
  String get label => switch (this) {
    SmartField.title => 'Title',
    SmartField.artist => 'Artist',
    SmartField.album => 'Album',
    SmartField.genre => 'Genre',
    SmartField.year => 'Year',
    SmartField.durationMinutes => 'Duration (min)',
    SmartField.playCount => 'Play count',
    SmartField.listenedMinutes => 'Time listened (min)',
    SmartField.lastPlayed => 'Last played',
    SmartField.dateAdded => 'Date added',
    SmartField.favorite => 'Favorite',
  };

  SmartFieldKind get kind => switch (this) {
    SmartField.title ||
    SmartField.artist ||
    SmartField.album ||
    SmartField.genre => SmartFieldKind.text,
    SmartField.year ||
    SmartField.durationMinutes ||
    SmartField.playCount ||
    SmartField.listenedMinutes => SmartFieldKind.number,
    SmartField.lastPlayed || SmartField.dateAdded => SmartFieldKind.date,
    SmartField.favorite => SmartFieldKind.boolean,
  };

  /// Operators that make sense for this field, first one being the default.
  List<SmartOperator> get operators => switch (kind) {
    SmartFieldKind.text => const [SmartOperator.contains, SmartOperator.equals],
    SmartFieldKind.number => const [
      SmartOperator.greaterThan,
      SmartOperator.lessThan,
      SmartOperator.equals,
    ],
    // "Never played" only means anything for lastPlayed; dateAdded is
    // always set, so it is left off that field.
    SmartFieldKind.date =>
      this == SmartField.lastPlayed
          ? const [
              SmartOperator.within,
              SmartOperator.notWithin,
              SmartOperator.never,
            ]
          : const [SmartOperator.within, SmartOperator.notWithin],
    SmartFieldKind.boolean => const [
      SmartOperator.isTrue,
      SmartOperator.isFalse,
    ],
  };
}

extension SmartOperatorInfo on SmartOperator {
  String get label => switch (this) {
    SmartOperator.contains => 'contains',
    SmartOperator.equals => 'is',
    SmartOperator.greaterThan => 'more than',
    SmartOperator.lessThan => 'less than',
    SmartOperator.within => 'in the last (days)',
    SmartOperator.notWithin => 'not in the last (days)',
    SmartOperator.never => 'never',
    SmartOperator.isTrue => 'yes',
    SmartOperator.isFalse => 'no',
  };

  /// False for operators that carry their own meaning and need no input.
  bool get takesValue => switch (this) {
    SmartOperator.never ||
    SmartOperator.isTrue ||
    SmartOperator.isFalse => false,
    _ => true,
  };
}

extension SmartSortInfo on SmartSort {
  String get label => switch (this) {
    SmartSort.title => 'Title',
    SmartSort.artist => 'Artist',
    SmartSort.dateAdded => 'Date added',
    SmartSort.playCount => 'Play count',
    SmartSort.lastPlayed => 'Last played',
    SmartSort.listenedTime => 'Time listened',
    SmartSort.random => 'Random',
  };
}

class SmartRule {
  const SmartRule({
    required this.field,
    required this.operator,
    this.value = '',
  });

  final SmartField field;
  final SmartOperator operator;

  /// Raw user input, parsed per [SmartField.kind] when the rule is compiled.
  final String value;

  /// Falls back to the field's default operator when the stored one no longer
  /// applies (a rule edited from "Genre contains" to "Play count", say).
  SmartRule copyWith({
    SmartField? field,
    SmartOperator? operator,
    String? value,
  }) {
    final nextField = field ?? this.field;
    var nextOperator = operator ?? this.operator;
    if (!nextField.operators.contains(nextOperator)) {
      nextOperator = nextField.operators.first;
    }
    return SmartRule(
      field: nextField,
      operator: nextOperator,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() => {
    'field': field.name,
    'operator': operator.name,
    'value': value,
  };

  static SmartRule? fromJson(Map<String, dynamic> json) {
    final field = SmartField.values
        .where((f) => f.name == json['field'])
        .firstOrNull;
    if (field == null) return null;
    final operator = SmartOperator.values
        .where((o) => o.name == json['operator'])
        .firstOrNull;
    if (operator == null || !field.operators.contains(operator)) return null;
    return SmartRule(
      field: field,
      operator: operator,
      value: json['value'] as String? ?? '',
    );
  }

  /// Human-readable form, used for the subtitle on the playlists screen.
  String describe() {
    final buffer = StringBuffer('${field.label} ${operator.label}');
    if (operator.takesValue && value.trim().isNotEmpty) {
      buffer.write(' ${value.trim()}');
    }
    return buffer.toString();
  }
}

class SmartPlaylistDefinition {
  const SmartPlaylistDefinition({
    this.matchAll = true,
    this.rules = const [],
    this.sort = SmartSort.title,
    this.descending = false,
    this.limit,
  });

  /// True: every rule must match. False: any rule matching is enough.
  final bool matchAll;
  final List<SmartRule> rules;
  final SmartSort sort;
  final bool descending;

  /// Null means no cap.
  final int? limit;

  SmartPlaylistDefinition copyWith({
    bool? matchAll,
    List<SmartRule>? rules,
    SmartSort? sort,
    bool? descending,
    int? limit,
    bool clearLimit = false,
  }) {
    return SmartPlaylistDefinition(
      matchAll: matchAll ?? this.matchAll,
      rules: rules ?? this.rules,
      sort: sort ?? this.sort,
      descending: descending ?? this.descending,
      limit: clearLimit ? null : (limit ?? this.limit),
    );
  }

  Map<String, dynamic> toJson() => {
    'matchAll': matchAll,
    'rules': [for (final rule in rules) rule.toJson()],
    'sort': sort.name,
    'descending': descending,
    if (limit != null) 'limit': limit,
  };

  String encode() => jsonEncode(toJson());

  /// Tolerant on purpose: a definition written by a newer build (unknown
  /// fields, dropped operators) degrades to the rules this build understands
  /// instead of throwing the playlist away.
  static SmartPlaylistDefinition decode(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic>) return const SmartPlaylistDefinition();
      final rawRules = json['rules'];
      return SmartPlaylistDefinition(
        matchAll: json['matchAll'] as bool? ?? true,
        rules: [
          if (rawRules is List)
            for (final raw in rawRules)
              if (raw is Map<String, dynamic>) ?SmartRule.fromJson(raw),
        ],
        sort:
            SmartSort.values.where((s) => s.name == json['sort']).firstOrNull ??
            SmartSort.title,
        descending: json['descending'] as bool? ?? false,
        limit: switch (json['limit']) {
          final num limit when limit > 0 => limit.toInt(),
          _ => null,
        },
      );
    } catch (_) {
      return const SmartPlaylistDefinition();
    }
  }

  String describe() {
    if (rules.isEmpty) return 'Every track';
    final joiner = matchAll ? ' · ' : ' or ';
    return [for (final rule in rules) rule.describe()].join(joiner);
  }
}

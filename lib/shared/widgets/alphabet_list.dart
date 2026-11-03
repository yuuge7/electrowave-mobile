import 'package:flutter/material.dart';

/// A proportional rail with exact jumps to fixed-extent rows. Only present
/// for alphabetical lists; each letter is also a labelled accessibility target.
class AlphabetList extends StatefulWidget {
  const AlphabetList({
    super.key,
    required this.labels,
    required this.itemBuilder,
    this.itemExtent = 76,
    this.showRail = true,
  });
  final List<String> labels;
  final IndexedWidgetBuilder itemBuilder;
  final double itemExtent;
  final bool showRail;
  @override
  State<AlphabetList> createState() => _AlphabetListState();
}

class _AlphabetListState extends State<AlphabetList> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = <String, int>{};
    for (var i = 0; i < widget.labels.length; i++) {
      final text = widget.labels[i].trim().toUpperCase();
      final letter = text.isEmpty ? '#' : text.substring(0, 1);
      letters.putIfAbsent(
        RegExp('[A-Z]').hasMatch(letter) ? letter : '#',
        () => i,
      );
    }
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final extent = widget.itemExtent * scale;
    return Row(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemExtent: extent,
            itemCount: widget.labels.length,
            itemBuilder: widget.itemBuilder,
          ),
        ),
        if (widget.labels.length > 20 && widget.showRail)
          SizedBox(
            width: 32,
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  if (letters.isEmpty || !_scroll.hasClients) return;
                  final index =
                      (d.localPosition.dy / c.maxHeight * letters.length)
                          .floor()
                          .clamp(0, letters.length - 1);
                  _scroll.jumpTo(
                    (letters.values.elementAt(index) * extent).clamp(
                      0,
                      _scroll.position.maxScrollExtent,
                    ),
                  );
                },
                child: Column(
                  children: [
                    for (final e in letters.entries)
                      Expanded(
                        child: Semantics(
                          label: 'Jump to ${e.key}',
                          button: true,
                          child: InkWell(
                            onTap: () {
                              if (_scroll.hasClients) {
                                _scroll.jumpTo(
                                  (e.value * extent).clamp(
                                    0,
                                    _scroll.position.maxScrollExtent,
                                  ),
                                );
                              }
                            },
                            child: Center(
                              child: Text(
                                e.key,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AlphabetGrid extends StatefulWidget {
  const AlphabetGrid({
    super.key,
    required this.labels,
    required this.itemBuilder,
  });
  final List<String> labels;
  final IndexedWidgetBuilder itemBuilder;
  @override
  State<AlphabetGrid> createState() => _AlphabetGridState();
}

class _AlphabetGridState extends State<AlphabetGrid> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final letters = <String, int>{};
      for (var i = 0; i < widget.labels.length; i++) {
        final name = widget.labels[i].trim().toUpperCase();
        final letter = name.isEmpty ? '#' : name.substring(0, 1);
        letters.putIfAbsent(
          RegExp('[A-Z]').hasMatch(letter) ? letter : '#',
          () => i,
        );
      }
      final rail = widget.labels.length > 20;
      final width = c.maxWidth - (rail ? 32 : 0) - 24;
      final columns = ((width + 12) / 232).ceil().clamp(1, 100);
      final rowHeight = (width - (columns - 1) * 12) / columns / 0.78 + 12;
      void jump(int index) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(
            (index ~/ columns * rowHeight).clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      }

      return Row(
        children: [
          Expanded(
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: widget.labels.length,
              itemBuilder: widget.itemBuilder,
            ),
          ),
          if (rail)
            SizedBox(
              width: 32,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  if (letters.isNotEmpty) {
                    jump(
                      letters.values.elementAt(
                        (d.localPosition.dy / c.maxHeight * letters.length)
                            .floor()
                            .clamp(0, letters.length - 1),
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    for (final e in letters.entries)
                      Expanded(
                        child: Semantics(
                          label: 'Jump to ${e.key}',
                          button: true,
                          child: InkWell(
                            onTap: () => jump(e.value),
                            child: Center(
                              child: Text(
                                e.key,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

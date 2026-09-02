import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import 'deck.dart';

/// Bottom navigation.
///
/// Material's `NavigationBar` puts a filled pill behind the selected icon.
/// That pill is one of the most recognisable "this is stock Material" tells
/// there is, and it also spends the accent colour on navigation — which is
/// meant to be reserved for what is playing.
///
/// This marks the active destination with the same 2px rule the app already
/// uses for playback position, sitting on the top edge of that column. One
/// form, used wherever something needs to say "here".
class DeckNavBar extends StatelessWidget {
  const DeckNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DeckDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final (index, destination) in destinations.indexed)
                Expanded(
                  child: _Destination(
                    destination: destination,
                    selected: index == selectedIndex,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelected(index);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeckDestination {
  const DeckDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DeckDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? tokens.signal : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: SignalRule(value: selected ? 1 : 0, height: 2),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 21,
                    color: color,
                  ),
                  const SizedBox(height: 5),
                  PanelLabel(destination.label, size: 9, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

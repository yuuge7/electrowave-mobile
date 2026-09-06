import 'package:flutter/material.dart';

/// Every modal sheet in the app opens through here.
///
/// `showModalBottomSheet` caps a sheet that is not scroll controlled at 9/16
/// of the screen and then overflows whatever does not fit — the track menu is
/// nine rows tall and lost its last two on a short phone. Opening the sheets
/// this way lets one grow to the height its content asks for, stop below the
/// status bar, and scroll from there instead.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => AppSheetBody(child: builder(sheetContext)),
  );
}

/// The body of a sheet: keeps clear of the bottom system inset, and scrolls
/// once the content runs past the room the sheet has. A short sheet still
/// wraps its content, so nothing gains empty space from this.
class AppSheetBody extends StatelessWidget {
  const AppSheetBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `useSafeArea` above only handles the top, left and right.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(child: child),
    );
  }
}

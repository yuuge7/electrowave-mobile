import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Electrowave's palette and component styling.
///
/// Two things here are deliberate departures from what `ColorScheme.fromSeed`
/// would produce, and both are the point:
///
/// 1. **The ground is not neutral.** Material's dark surfaces are grey with a
///    faint tint painted over them. These step in *chroma* as well as
///    lightness — a deep petrol ink that gets greener and lighter as surfaces
///    come forward — so the app reads as one material rather than as grey
///    boxes with an accent dropped on top.
/// 2. **Corners are quiet.** Material 3 rounds everything to 12–28; a
///    transport should look machined, so radii top out at 12 and most
///    structural edges are 8 or 4.
class ElectrowaveTheme {
  const ElectrowaveTheme._();

  /// The signal colour, and the app's identity. Bright enough to be the only
  /// saturated thing on a dark ground.
  static const Color signalDark = Color(0xFF00E5CC);

  /// Its light-theme counterpart: the same hue taken down until it passes
  /// contrast against paper.
  static const Color signalLight = Color(0xFF00695E);

  // -------------------------------------------------------------------------
  // Palettes
  // -------------------------------------------------------------------------

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: signalDark,
    onPrimary: Color(0xFF002B26),
    primaryContainer: Color(0xFF00463E),
    onPrimaryContainer: Color(0xFF6FFFEB),
    secondary: Color(0xFF9FCCC5),
    onSecondary: Color(0xFF123430),
    secondaryContainer: Color(0xFF1E3B37),
    onSecondaryContainer: Color(0xFFBCEAE2),
    tertiary: Color(0xFFE8A33D),
    onTertiary: Color(0xFF3A2400),
    tertiaryContainer: Color(0xFF533600),
    onTertiaryContainer: Color(0xFFFFDDA8),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF080F11),
    onSurface: Color(0xFFE2ECEC),
    onSurfaceVariant: Color(0xFF8FA6A9),
    surfaceDim: Color(0xFF060C0D),
    surfaceBright: Color(0xFF1B2E32),
    surfaceContainerLowest: Color(0xFF050A0B),
    surfaceContainerLow: Color(0xFF0B1417),
    surfaceContainer: Color(0xFF0F1D20),
    surfaceContainerHigh: Color(0xFF142529),
    surfaceContainerHighest: Color(0xFF1A3035),
    outline: Color(0xFF33494E),
    outlineVariant: Color(0xFF223437),
    inverseSurface: Color(0xFFE2ECEC),
    onInverseSurface: Color(0xFF0F1D20),
    inversePrimary: signalLight,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: signalDark,
  );

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: signalLight,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF8CF7E5),
    onPrimaryContainer: Color(0xFF00201C),
    secondary: Color(0xFF40635D),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFC2E9E1),
    onSecondaryContainer: Color(0xFF00201C),
    tertiary: Color(0xFF8A5B00),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFDDA8),
    onTertiaryContainer: Color(0xFF2B1A00),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFEFF3F2),
    onSurface: Color(0xFF0C1719),
    onSurfaceVariant: Color(0xFF46595C),
    surfaceDim: Color(0xFFD8E0DF),
    surfaceBright: Color(0xFFF7FBFA),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFE9EFEE),
    surfaceContainer: Color(0xFFE3EAE9),
    surfaceContainerHigh: Color(0xFFDDE5E4),
    surfaceContainerHighest: Color(0xFFD7E0DF),
    outline: Color(0xFF76898C),
    outlineVariant: Color(0xFFC3D0D0),
    inverseSurface: Color(0xFF2B3739),
    onInverseSurface: Color(0xFFECF2F1),
    inversePrimary: signalDark,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: signalLight,
  );

  static DeckTokens tokensFor(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return DeckTokens(
      signal: scheme.primary,
      onSignal: scheme.onPrimary,
      signalDim: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.34 : 0.42),
        scheme.surface,
      ),
      meterTrack: dark
          ? scheme.onSurface.withValues(alpha: 0.14)
          : scheme.onSurface.withValues(alpha: 0.13),
      peak: scheme.tertiary,
      panel: scheme.onSurfaceVariant,
      hairline: scheme.outlineVariant.withValues(alpha: dark ? 0.7 : 0.9),
      recessed: dark
          ? const Color(0xFF050A0B)
          : scheme.onSurface.withValues(alpha: 0.06),
    );
  }

  // -------------------------------------------------------------------------
  // Assembly
  // -------------------------------------------------------------------------

  static ThemeData build(ColorScheme scheme) {
    final tokens = tokensFor(scheme);
    final textTheme = buildTextTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      extensions: [tokens],

      // Material paints an elevation tint over dark surfaces, which is what
      // makes every M3 app's app bar and sheets drift toward the same milky
      // grey. The surfaces here are already designed; leave them alone.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        actionsIconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      ),

      dividerTheme: DividerThemeData(
        color: tokens.hairline,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minVerticalPadding: 10,
        visualDensity: VisualDensity.standard,
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.hairline),
        ),
      ),

      // A machined marker rather than Material's lozenge: a squared-off thumb
      // riding a thin channel, sized so it stays grabbable.
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: tokens.signal,
        inactiveTrackColor: tokens.meterTrack,
        thumbColor: tokens.signal,
        overlayColor: tokens.signal.withValues(alpha: 0.12),
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 7,
          pressedElevation: 0,
          elevation: 0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        showValueIndicator: ShowValueIndicator.never,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.signal,
        linearTrackColor: tokens.meterTrack,
        circularTrackColor: tokens.meterTrack,
        linearMinHeight: 2,
      ),

      // Chips at rest are outlined and achromatic — they are navigation, not
      // state. Only a selected chip earns the signal colour.
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        disabledColor: scheme.surfaceContainerHigh,
        labelStyle: textTheme.labelLarge!.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelLarge!,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        iconTheme: IconThemeData(size: 17, color: scheme.onSurfaceVariant),
        showCheckmark: false,
      ),

      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.04),
        ),
        elevation: const WidgetStatePropertyAll(0),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14),
        ),
        constraints: const BoxConstraints(minHeight: 46),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
          ),
        ),
      ),

      // Uppercase panel labels under a 2px signal rule — the same rule that
      // shows playback position elsewhere, reused to mark position in a set
      // of tabs.
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: panelLabel(size: 9.5),
        unselectedLabelStyle: panelLabel(size: 9.5),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: tokens.signal, width: 2),
        ),
        dividerColor: tokens.hairline,
        dividerHeight: 1,
        overlayColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.04),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tokens.hairline),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.hairline),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.signal,
        foregroundColor: tokens.onSignal,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: textTheme.labelMedium,
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        labelStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.signal, width: 1.5),
        ),
      ),

      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    );
  }

  /// Material You: the wallpaper palette replaces the hues, but the structure
  /// above — flat surfaces, quiet radii, the panel type, signal-only accent —
  /// still applies, so dynamic schemes go through the same builder.
  static ThemeData buildDynamic(ColorScheme scheme) => build(scheme);
}

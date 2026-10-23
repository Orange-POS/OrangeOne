import 'package:flutter/material.dart';

abstract final class OrangeTheme {
  /// Top inset baseline; larger hardware cutouts remain protected.
  static const topSafeArea = 34.0;

  static const brand = Color(0xFFFF8A33);
  static const dark = Color(0xFFBE4602);
  static const camera = Color(0xFF1B120B);
  static const pale = Color(0xFFFFF3E8);
  static const secondary = Color(0xFF5F6368);
  // Supplied button component colors; independent of branded backgrounds.
  static const action = Color(0xFFF56600);
  static const actionPressed = Color(0xFFC84E00);
  static const actionDisabled = Color(0xFFDADCE0);
  static const actionDisabledLabel = Color(0xFF5F6368);

  static Color _actionColor(Set<WidgetState> states) =>
      states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)
      ? actionPressed
      : action;
  // Use the dark endpoint for readable small accents on white surfaces.
  static const Color scannerAccent = dark;
  static const gradient = LinearGradient(
    begin: Alignment(-.54, -.72),
    end: Alignment(1, .6),
    colors: [dark, brand],
    stops: [.08, .94],
  );
  static const LinearGradient homeGradient = gradient;
  static const LinearGradient scannerGradient = gradient;

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      primary: dark,
      secondary: dark,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? actionDisabled
              : _actionColor(states),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? actionDisabledLabel
              : Colors.white,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 56)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? actionDisabledLabel
              : _actionColor(states),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? actionDisabled
                : _actionColor(states),
          ),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll(Size(64, 56)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
  );
}

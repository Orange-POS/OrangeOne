import 'package:flutter/material.dart';

abstract final class OrangeTheme {
  static const brand = Color(0xFFFF8A33);
  static const dark = Color(0xFFBE4602);
  static const camera = Color(0xFF1B120B);
  static const pale = Color(0xFFFFF3E8);
  static const secondary = Color(0xFF5F6368);
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
              ? const Color(0xFFDADCE0)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? const Color(0xFF5F6368)
              : Colors.white,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? const Color(0xFFDADCE0)
                : const Color(0x99FFFFFF),
            width: .5,
          ),
        ),
        backgroundBuilder: (context, states, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: states.contains(WidgetState.disabled) ? null : gradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    ),
  );
}

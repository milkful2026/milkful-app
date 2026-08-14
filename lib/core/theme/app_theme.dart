import 'package:flutter/material.dart';

/// Placeholder brand color — the welcome-screen story doc itself says
/// "confirm against design system" for the real token; this is a
/// reasonable placeholder, not a sourced brand value.
const _milkfulGreen = Color(0xFF0B6B3A);

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _milkfulGreen),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: _milkfulGreen,
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Placeholder brand color — the welcome-screen story doc itself says
/// "confirm against design system" for the real token; this is a
/// reasonable placeholder, not a sourced brand value.
const _milkfulGreen = Color(0xFF0B6B3A);

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _milkfulGreen),
        // Matches the reference mockups' rounded, friendly display font.
        // Falls back to the platform default if it can't be fetched (no
        // network on first use) — never a hard failure, just a plainer look.
        textTheme: GoogleFonts.poppinsTextTheme(),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: _milkfulGreen,
            shape: const StadiumBorder(),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _milkfulGreen, width: 2),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black87,
        ),
      );
}

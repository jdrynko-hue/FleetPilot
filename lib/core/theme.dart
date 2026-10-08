import 'package:flutter/material.dart';

ThemeData buildFleetPilotTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1E5AA8),
    brightness: Brightness.light,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF7F9FC),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
  );
}

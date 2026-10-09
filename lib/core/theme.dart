import 'package:flutter/material.dart';

ThemeData buildFleetPilotTheme() {
  const navy = Color(0xFF102A43);
  const blue = Color(0xFF2563EB);
  const background = Color(0xFFF3F6FA);

  final scheme = ColorScheme.fromSeed(
    seedColor: blue,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,

    appBarTheme: const AppBarTheme(
      backgroundColor: navy,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w700,
      ),
    ),

    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
          color: Color(0xFFE3E9F0),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFD8E0E8),
        ),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 74,
      backgroundColor: Colors.white,
      indicatorColor: scheme.primaryContainer,
      elevation: 8,
    ),
  );
}

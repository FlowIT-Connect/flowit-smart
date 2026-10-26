import 'package:flutter/material.dart';

/// Identité visuelle propre à FlowIT (aucune ressource Smart Life, §5.11).
class AppTheme {
  static const seed = Color(0xFF0E7C86);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: seed));

  static ThemeData dark() => _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        cardTheme: CardThemeData(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsetsDirectional.only(start: 16, end: 12)),
      );
}

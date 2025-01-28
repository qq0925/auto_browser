import 'package:flutter/material.dart';
import 'package:auto_browser/features/browser/presentation/browser_screen.dart';

void main() => runApp(const AutoBrowserApp());

class AutoBrowserApp extends StatelessWidget {
  const AutoBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Browser',
      debugShowCheckedModeBanner: false,
      theme: _buildIOSTheme(),
      home: const BrowserScreen(),
    );
  }

  ThemeData _buildIOSTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0.5,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.blue.shade100,
        foregroundColor: Colors.blue.shade800,
      ),
    );
  }
}
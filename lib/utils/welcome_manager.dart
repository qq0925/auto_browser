import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

/// Utility class for managing welcome.html updates
class WelcomeManager {
  static const String _remoteUrl = 'http://test.txsj.ink/welcome.html';
  static const String _localFilename = 'welcome.html';
  static const String _assetPath = 'assets/welcome.html';

  /// Get the welcome.html content
  /// Priority: 1. Local downloaded version, 2. Bundled asset
  static Future<String> getWelcomeContent() async {
    try {
      // Try to load from documents directory first (updated version)
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, _localFilename));

      if (await localFile.exists()) {
        return await localFile.readAsString();
      }
    } catch (e) {
      // If local file fails, fall through to asset
    }

    // Fallback to bundled asset
    return await rootBundle.loadString(_assetPath);
  }

  /// Update welcome.html in background (silent, no user feedback)
  /// Fetches from remote URL and saves to local documents if successful
  static Future<void> updateWelcomeInBackground() async {
    try {
      // Fetch remote version with timeout
      final response = await http
          .get(Uri.parse(_remoteUrl))
          .timeout(const Duration(seconds: 5));

      // Check if successful
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // Decode response with UTF-8 to handle Chinese characters correctly
        final content = utf8.decode(response.bodyBytes);
        
        // Save to documents directory with UTF-8 encoding
        final documentsDir = await getApplicationDocumentsDirectory();
        final localFile = File(path.join(documentsDir.path, _localFilename));

        await localFile.writeAsString(content, encoding: utf8);

        // Silent success - no user notification needed
      }
    } catch (e) {
      // Silent fail - network errors, timeouts, etc.
      // User will continue using local/bundled version
    }
  }

  /// Get the local file path for loading in WebView
  /// Returns either local file:// URL or asset path
  static Future<String> getWelcomeUrl() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, _localFilename));

      if (await localFile.exists()) {
        return 'file://${localFile.path}';
      }
    } catch (e) {
      // Fall through to asset
    }

    // Return asset path
    return _assetPath;
  }
}

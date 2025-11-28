import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Utility class for managing script file directories
class FileManager {
  /// Get the default script directory path (Auok/脚本)
  /// Creates the directory if it doesn't exist
  static Future<String> getScriptDirectory() async {
    // Get app documents directory
    final Directory appDocDir = await getApplicationDocumentsDirectory();

    // Create Auok/脚本 path
    final String scriptDirPath = path.join(appDocDir.path, 'Auok', '脚本');

    // Create directory if it doesn't exist
    final Directory scriptDir = Directory(scriptDirPath);
    if (!await scriptDir.exists()) {
      await scriptDir.create(recursive: true);
    }

    return scriptDirPath;
  }

  /// Check if a file exists at the given path
  static Future<bool> fileExists(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      return false;
    }
    return await File(filePath).exists();
  }

  /// Delete a file at the given path
  static Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

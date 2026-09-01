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

  /// 尝试从服务器拉取并返回最新内容，若获取成功返回内容并缓存到本地，失败返回 null
  static Future<String?> fetchLatestRemoteContent(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final response = await http.get(Uri.parse(_remoteUrl)).timeout(timeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final content = utf8.decode(response.bodyBytes);
        await _saveToLocal(content);
        return content;
      }
    } catch (_) {}
    return null;
  }

  /// Get the welcome.html content
  /// Priority: 1. Fetch remote version (timeout 2.5s), 2. Local cached file, 3. Bundled asset
  static Future<String> getWelcomeContent(
      {Duration remoteTimeout = const Duration(milliseconds: 2500)}) async {
    // 1. 优先尝试从服务器获取最新起始页
    final remoteContent =
        await fetchLatestRemoteContent(timeout: remoteTimeout);
    if (remoteContent != null && remoteContent.isNotEmpty) {
      return remoteContent;
    }

    // 2. 尝试读取本地缓存文件
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, _localFilename));

      if (await localFile.exists()) {
        return await localFile.readAsString();
      }
    } catch (e) {
      // If local file fails, fall through to asset
    }

    // 3. 最终降级到内置安装包资产
    return await rootBundle.loadString(_assetPath);
  }

  /// 辅助方法：异步将内容持久化到本地文件
  static Future<void> _saveToLocal(String content) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, _localFilename));
      await localFile.writeAsString(content, encoding: utf8);
    } catch (_) {}
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
        final content = utf8.decode(response.bodyBytes);
        await _saveToLocal(content);
      }
    } catch (e) {
      // Silent fail - network errors, timeouts, etc.
    }
  }

  /// Get the local file path for loading in WebView
  /// Returns either local file:// URL or asset path
  static Future<String> getWelcomeUrl() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, _localFilename));

      if (await localFile.exists()) {
        return Uri.file(localFile.path).toString();
      }
    } catch (e) {
      // Fall through to asset
    }

    // Return asset path
    return _assetPath;
  }
}

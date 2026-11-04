import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

/// 欢迎页 welcome.html 资源与远程热更新管理工具类
class WelcomeManager {
  static const String _remoteUrl = 'http://test.txsj.ink/welcome.html';
  static const String _localFilename = 'welcome.html';
  static const String _assetPath = 'assets/welcome.html';

  // 正在进行的远程请求复用句柄，防止启动阶段多处并发请求并同时写同一个本地文件
  static Future<String?>? _inFlightFetch;

  /// 尝试从服务器拉取并返回最新内容，若获取成功返回内容并缓存到本地，失败返回 null
  static Future<String?> fetchLatestRemoteContent(
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (_inFlightFetch != null) {
      try {
        return await _inFlightFetch!.timeout(timeout);
      } catch (_) {
        return null;
      }
    }

    final future = _doFetchRemote(timeout);
    _inFlightFetch = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightFetch, future)) {
        _inFlightFetch = null;
      }
    }
  }

  static Future<String?> _doFetchRemote(Duration timeout) async {
    try {
      final response = await http.get(Uri.parse(_remoteUrl)).timeout(timeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final content = utf8.decode(response.bodyBytes, allowMalformed: true);
        await _saveToLocal(content);
        return content;
      }
    } catch (_) {}
    return null;
  }

  /// 获取 welcome.html 内容
  /// 优先级：1. 远程最新版本 (超时 2.5s)，2. 本地缓存文件，3. 内置安装包资产
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
        final localContent = await localFile.readAsString();
        if (localContent.isNotEmpty) {
          return localContent;
        }
      }
    } catch (_) {}

    // 3. 最终降级到内置安装包资产
    return await rootBundle.loadString(_assetPath);
  }

  /// 辅助方法：原子化将内容持久化到本地文件，防止并发读写撕裂或 Windows 文件锁冲突
  static Future<void> _saveToLocal(String content) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final targetPath = path.join(documentsDir.path, _localFilename);
      final tempPath =
          '$targetPath.${DateTime.now().microsecondsSinceEpoch}.tmp';
      final tempFile = File(tempPath);
      await tempFile.writeAsString(content, encoding: utf8, flush: true);
      try {
        await tempFile.rename(targetPath);
      } catch (_) {
        await File(targetPath).writeAsString(content, encoding: utf8);
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 后台静默更新 welcome.html
  static Future<void> updateWelcomeInBackground() async {
    await fetchLatestRemoteContent(timeout: const Duration(seconds: 5));
  }

  /// 获取可在 WebView 中加载的本地 file:// URL
  static Future<String> getWelcomeUrl() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final localFile = File(path.join(documentsDir.path, _localFilename));

      if (!await localFile.exists()) {
        final assetContent = await rootBundle.loadString(_assetPath);
        await _saveToLocal(assetContent);
      }
      if (await localFile.exists()) {
        return Uri.file(localFile.path).toString();
      }
    } catch (_) {}

    return 'file:///welcome.html';
  }
}

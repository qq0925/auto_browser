import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 下载管理服务 - 支持PC/Android/iOS三平台
class DownloadService {
  /// 获取下载目录
  /// - Windows/macOS: 用户 Downloads 文件夹
  /// - Android: 外部存储 Downloads 目录
  /// - iOS: 应用 Documents 目录
  static Future<String> getDownloadDirectory() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // PC平台: 获取Downloads目录
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        return downloadsDir.path;
      }
      // 备用: 文档目录
      final docDir = await getApplicationDocumentsDirectory();
      return docDir.path;
    } else if (Platform.isAndroid) {
      // Android: 尝试获取外部存储目录
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final downloadPath = path.join(
              externalDir.parent.parent.parent.parent.path, 'Download');
          final downloadDir = Directory(downloadPath);
          if (await downloadDir.exists()) {
            return downloadPath;
          }
          return externalDir.path;
        }
      } catch (_) {}
      // 备用: 应用文档目录
      final docDir = await getApplicationDocumentsDirectory();
      return docDir.path;
    } else {
      // iOS: 只能使用应用沙盒内的Documents目录
      final docDir = await getApplicationDocumentsDirectory();
      return docDir.path;
    }
  }

  /// 从URL下载文件
  /// [url] - 下载链接
  /// [suggestedFilename] - 建议的文件名
  /// [onProgress] - 进度回调 (0.0 - 1.0)
  /// [onComplete] - 完成回调 (文件保存路径)
  /// [onError] - 错误回调
  static Future<void> downloadFile({
    required String url,
    String? suggestedFilename,
    Function(double progress)? onProgress,
    Function(String filePath)? onComplete,
    Function(String error)? onError,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      // 解析文件名
      String filename = suggestedFilename ?? _getFilenameFromUrl(url);

      // 获取下载目录
      final downloadDir = await getDownloadDirectory();
      final filePath = path.join(downloadDir, filename);

      // 检查文件是否已存在，如果存在则添加序号
      final uniquePath = await _getUniqueFilePath(filePath);

      // 开始下载
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        onError?.call('下载失败: HTTP ${response.statusCode}');
        return;
      }

      // 获取文件大小
      final contentLength = response.contentLength ?? 0;
      int receivedBytes = 0;

      // 创建文件
      final file = File(uniquePath);
      sink = file.openWrite();

      // 写入数据并报告进度
      await response.stream.listen(
        (List<int> chunk) {
          sink?.add(chunk);
          receivedBytes += chunk.length;
          if (contentLength > 0) {
            onProgress?.call(receivedBytes / contentLength);
          }
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();
      sink = null;

      onComplete?.call(uniquePath);
    } catch (e) {
      onError?.call('下载失败: $e');
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client.close();
    }
  }

  /// 从URL中提取文件名
  static String _getFilenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        if (lastSegment.contains('.')) {
          return Uri.decodeComponent(lastSegment);
        }
      }
    } catch (_) {}

    // 默认文件名
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 获取唯一文件路径（如果文件已存在则添加序号）
  static Future<String> _getUniqueFilePath(String originalPath) async {
    var file = File(originalPath);
    if (!await file.exists()) {
      return originalPath;
    }

    final dir = path.dirname(originalPath);
    final extension = path.extension(originalPath);
    final baseName = path.basenameWithoutExtension(originalPath);

    int counter = 1;
    String newPath;
    do {
      newPath = path.join(dir, '$baseName ($counter)$extension');
      file = File(newPath);
      counter++;
    } while (await file.exists());

    return newPath;
  }

  /// 显示下载开始的 SnackBar
  static void showDownloadStarted(BuildContext context, String filename) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('开始下载: $filename'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 显示下载完成的 SnackBar
  static void showDownloadComplete(BuildContext context, String filePath) {
    final filename = path.basename(filePath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('下载完成: $filename'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () {
          },
        ),
      ),
    );
  }

  /// 显示下载失败的 SnackBar
  static void showDownloadError(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

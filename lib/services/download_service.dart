import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 下载与跨平台文件服务
/// 深度适配 Windows、Android、iOS 三端的文件存储、打开与系统交互
class DownloadService {
  /// 获取多端安全下载存储目录
  /// - Windows/macOS: 用户系统 Downloads 目录
  /// - Android: 公共 Downloads 目录或应用外部私有 Downloads 目录（兼容 Android 10+ 分区存储）
  /// - iOS: 应用沙盒 Documents 目录（保证 App Store 合规）
  static Future<String> getDownloadDirectory() async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          return downloadsDir.path;
        }
        final docDir = await getApplicationDocumentsDirectory();
        return docDir.path;
      } else if (Platform.isAndroid) {
        // 优先使用标准公共下载目录
        try {
          const publicDownloadPath = '/storage/emulated/0/Download';
          final publicDir = Directory(publicDownloadPath);
          if (await publicDir.exists()) {
            return publicDownloadPath;
          }
        } catch (_) {}

        // 回退到外部私有存储目录下的 Download 文件夹（无需 WRITE_EXTERNAL_STORAGE 权限）
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final downloadDir = Directory(path.join(extDir.path, 'Download'));
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir.path;
        }

        // 最终兜底：内部文档目录
        final docDir = await getApplicationDocumentsDirectory();
        return docDir.path;
      } else {
        // iOS: 使用应用沙盒 Documents 目录
        final docDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory(path.join(docDir.path, 'Downloads'));
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir.path;
      }
    } catch (e) {
      debugPrint('获取下载目录异常: $e');
      final fallbackDir = await getApplicationDocumentsDirectory();
      return fallbackDir.path;
    }
  }

  /// 清洗并标准化文件名，过滤操作系统非法字符
  static String sanitizeFileName(String rawName) {
    var name = rawName.trim();
    // 过滤 Windows/Linux/macOS 特殊非法字符: \ / : * ? " < > | \0
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00]'), '_');
    // 去除连续下划线
    name = name.replaceAll(RegExp(r'_+'), '_');
    // 去除前后点号和空格
    name = name.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');

    if (name.isEmpty) {
      name = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return name;
  }

  /// 从 URL、建议文件名或 Content-Disposition 提取文件名
  static String extractFileName(String url, {String? suggestedFilename}) {
    if (suggestedFilename != null && suggestedFilename.trim().isNotEmpty) {
      return sanitizeFileName(suggestedFilename);
    }

    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = Uri.decodeComponent(segments.last);
        if (last.contains('.')) {
          return sanitizeFileName(last);
        }
      }
    } catch (_) {}

    return sanitizeFileName('download_${DateTime.now().millisecondsSinceEpoch}');
  }

  /// 获取唯一文件保存路径（若存在同名文件则自动递增添加 (1)、(2)）
  static Future<String> getUniqueFilePath(String targetPath) async {
    var file = File(targetPath);
    if (!await file.exists()) {
      return targetPath;
    }

    final dir = path.dirname(targetPath);
    final extension = path.extension(targetPath);
    final baseName = path.basenameWithoutExtension(targetPath);

    int counter = 1;
    String newPath;
    do {
      newPath = path.join(dir, '$baseName ($counter)$extension');
      file = File(newPath);
      counter++;
    } while (await file.exists());

    return newPath;
  }

  /// 打开文件（跨平台兼容适配）
  /// - Windows: 调用 explorer.exe 打开默认关联程序，0依赖且100%兼容MSIX
  /// - Android/iOS: 优先调用 OpenFilex 打开；若系统无对应软件则提供分享弹窗
  static Future<bool> openFile(BuildContext? context, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在或已被移除')),
        );
      }
      return false;
    }

    try {
      if (Platform.isWindows) {
        // Windows 原生通过 explorer.exe 唤起默认关联程序
        await Process.run('explorer.exe', [filePath]);
        return true;
      } else {
        // Android / iOS 使用 open_filex
        final result = await OpenFilex.open(filePath);
        if (result.type == ResultType.done) {
          return true;
        }

        // 若打开失败（如找不到应用支持），提示或调用分享面板
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无法直接打开此文件: ${result.message}，正在尝试调用系统分享'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        await shareFile(filePath);
        return true;
      }
    } catch (e) {
      debugPrint('打开文件失败: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件异常: $e')),
        );
      }
      return false;
    }
  }

  /// 在系统文件资源管理器中定位并选中文件
  /// - Windows: 使用 explorer.exe /select,"filePath"
  /// - Android/iOS: 调用系统分享面板导出或查看
  static Future<void> showInFolder(BuildContext? context, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
      }
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      } else {
        // 移动端唤起系统分享面板
        await shareFile(filePath);
      }
    } catch (e) {
      debugPrint('定位文件异常: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作异常: $e')),
        );
      }
    }
  }

  /// 分享文件（移动端与桌面端均可支持）
  static Future<void> shareFile(String filePath) async {
    try {
      final file = XFile(filePath);
      await Share.shareXFiles([file], text: path.basename(filePath));
    } catch (e) {
      debugPrint('分享文件异常: $e');
    }
  }

  /// 删除已下载文件及其临时分块文件
  static Future<void> deleteFile(String filePath, {String? tempPath}) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除文件失败: $e');
    }

    if (tempPath != null) {
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        debugPrint('删除临时文件失败: $e');
      }
    }
  }

  /// 显示开始下载提示
  static void showDownloadStarted(BuildContext context, String filename) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.download, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已开始下载: $filename',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 显示下载完成提示
  static void showDownloadComplete(
    BuildContext context,
    String filePath, {
    VoidCallback? onOpen,
  }) {
    final filename = path.basename(filePath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '下载完成: $filename',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '打开',
          textColor: Colors.white,
          onPressed: onOpen ?? () => openFile(context, filePath),
        ),
      ),
    );
  }

  /// 显示下载错误提示
  static void showDownloadError(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

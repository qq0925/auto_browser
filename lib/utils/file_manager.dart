import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 脚本文件目录管理工具类
class FileManager {
  /// 获取默认脚本目录路径 (脚本)，若不存在则自动创建
  static Future<String> getScriptDirectory() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String scriptDirPath = path.join(appDocDir.path, '脚本');

    final Directory scriptDir = Directory(scriptDirPath);
    if (!await scriptDir.exists()) {
      await scriptDir.create(recursive: true);
    }

    return scriptDirPath;
  }

  /// 获取所有已保存的脚本文件 (.json / .zds)，按修改时间倒序排列
  static Future<List<File>> getSavedScripts() async {
    final scriptDirPath = await getScriptDirectory();
    final scriptDir = Directory(scriptDirPath);

    if (!await scriptDir.exists()) {
      return [];
    }

    final List<FileSystemEntity> entities = await scriptDir.list().toList();
    final List<MapEntry<File, DateTime>> fileEntries = [];

    for (var entity in entities) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.json') || lower.endsWith('.zds')) {
          DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
          try {
            modified = await entity.lastModified();
          } catch (_) {}
          fileEntries.add(MapEntry(entity, modified));
        }
      }
    }

    // 预先获取修改时间后再排序，避免在 sort 比较器内频繁调用同步 statSync 阻塞主线程
    fileEntries.sort((a, b) => b.value.compareTo(a.value));
    return fileEntries.map((e) => e.key).toList();
  }

  /// 检查指定路径文件是否存在
  static Future<bool> fileExists(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      return false;
    }
    try {
      return await File(filePath).exists();
    } catch (_) {
      return false;
    }
  }

  /// 安全删除指定路径文件
  static Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

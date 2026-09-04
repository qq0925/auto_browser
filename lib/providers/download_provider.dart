import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';
import '../services/download_service.dart';

/// 全局多任务下载状态管理器
/// 支持断点续传、并发控制、Cookie/UA鉴权、持久化与实时速率监测
class DownloadProvider with ChangeNotifier {
  static const String _storageKey = 'auok_download_tasks_v1';

  final List<DownloadTask> _tasks = [];
  bool _isInitialized = false;

  // 最大并发下载数
  int maxConcurrentDownloads = 3;

  // 运行中的连接和数据流句柄
  final Map<String, HttpClientRequest> _activeRequests = {};
  final Map<String, StreamSubscription<List<int>>> _activeSubscriptions = {};
  final Map<String, IOSink> _activeSinks = {};

  // 速率统计辅助数据
  final Map<String, int> _lastBytes = {};
  final Map<String, DateTime> _lastTime = {};

  // UI 更新节流定时器
  DateTime _lastNotifyTime = DateTime.now();

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// 正在下载中的任务列表
  List<DownloadTask> get activeDownloads => _tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.pending)
      .toList();

  /// 活跃任务总数（用于在AppBar等位置展示角标）
  int get activeCount => _tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.pending)
      .length;

  /// 已完成任务列表
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.completed).toList();

  DownloadProvider() {
    _init();
  }

  /// 初始化并加载持久化的下载任务列表
  Future<void> _init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        _tasks.clear();
        for (var item in list) {
          try {
            final task = DownloadTask.fromJson(item as Map<String, dynamic>);
            // 校验文件实际存在性
            if (task.status == DownloadStatus.completed) {
              final file = File(task.filePath);
              if (!file.existsSync()) {
                // 如果文件已被移走，保留记录但标记
              }
            }
            _tasks.add(task);
          } catch (e) {
            debugPrint('解析下载任务异常: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('加载下载任务历史失败: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// 保存任务列表到本地存储
  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _tasks.map((t) => t.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('保存下载任务失败: $e');
    }
  }

  /// 创建并添加下载任务
  Future<DownloadTask> addTask({
    required String url,
    String? customFileName,
    String? suggestedFilename,
    String? mimeType,
    String? userAgent,
    String? cookies,
    bool autoStart = true,
  }) async {
    // 1. 获取安全的存储目录
    final saveDir = await DownloadService.getDownloadDirectory();

    // 2. 确定文件名与唯一存储路径
    String targetFileName = customFileName?.trim().isNotEmpty == true
        ? DownloadService.sanitizeFileName(customFileName!)
        : DownloadService.extractFileName(url, suggestedFilename: suggestedFilename);

    final fullPath = path.join(saveDir, targetFileName);
    final uniquePath = await DownloadService.getUniqueFilePath(fullPath);
    targetFileName = path.basename(uniquePath);

    // 3. 构造任务对象
    final task = DownloadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}',
      url: url,
      fileName: targetFileName,
      filePath: uniquePath,
      receivedBytes: 0,
      totalBytes: -1,
      status: DownloadStatus.pending,
      mimeType: mimeType,
      userAgent: userAgent,
      cookies: cookies,
    );

    _tasks.insert(0, task);
    await _saveTasks();
    notifyListeners();

    if (autoStart) {
      startTask(task.id);
    }

    return task;
  }

  /// 启动/开始任务
  void startTask(String taskId) {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = _tasks[taskIndex];

    // 如果任务已在下载中或已完成，不重复启动
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return;
    }

    // 检查当前下载中的任务数
    final currentRunningCount =
        _tasks.where((t) => t.status == DownloadStatus.downloading).length;

    if (currentRunningCount >= maxConcurrentDownloads) {
      task.status = DownloadStatus.pending;
      task.error = null;
      notifyListeners();
      _saveTasks();
      return;
    }

    _executeDownload(task);
  }

  /// 内部执行下载流（基于 HttpClient 与断点续传）
  Future<void> _executeDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    task.error = null;
    task.speed = 0;
    _lastBytes[task.id] = task.receivedBytes;
    _lastTime[task.id] = DateTime.now();
    notifyListeners();

    final tempFile = File(task.tempPath);
    int existingLength = 0;
    if (await tempFile.exists()) {
      existingLength = await tempFile.length();
      task.receivedBytes = existingLength;
    }

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (cert, host, port) => true; // 容错证书

      final uri = Uri.parse(task.url);
      final request = await client.getUrl(uri);
      _activeRequests[task.id] = request;

      // 设置 User-Agent
      if (task.userAgent != null && task.userAgent!.isNotEmpty) {
        request.headers.set(HttpHeaders.userAgentHeader, task.userAgent!);
      } else {
        request.headers.set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 AuokBrowser');
      }

      // 设置 Session Cookies
      if (task.cookies != null && task.cookies!.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, task.cookies!);
      }

      // 设置断点续传 Range 请求头
      if (existingLength > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingLength-');
      }

      final response = await request.close();

      // 判断 HTTP 状态码
      final statusCode = response.statusCode;
      bool isResume = false;

      if (statusCode == HttpStatus.partialContent) {
        // 206 Partial Content：服务端支持断点续传
        isResume = true;
        final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
        if (contentRange != null) {
          // 例如 bytes 1000-1999/2000
          final parts = contentRange.split('/');
          if (parts.length == 2) {
            final total = int.tryParse(parts[1]);
            if (total != null) task.totalBytes = total;
          }
        }
        if (task.totalBytes <= 0 && response.contentLength > 0) {
          task.totalBytes = existingLength + response.contentLength;
        }
      } else if (statusCode == HttpStatus.ok) {
        // 200 OK：全量响应（不支持断点续传或从头下载）
        isResume = false;
        task.receivedBytes = 0;
        if (response.contentLength > 0) {
          task.totalBytes = response.contentLength;
        }
      } else if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // 416 Range Not Satisfiable：文件可能已经下载完成或者文件在服务端已更新，重头开始
        await DownloadService.deleteFile(task.filePath, tempPath: task.tempPath);
        task.receivedBytes = 0;
        _executeDownload(task);
        return;
      } else {
        throw 'HTTP 状态码异常: $statusCode (${response.reasonPhrase})';
      }

      // 提取文件名（如果服务器提供了 Content-Disposition）
      final disposition = response.headers.value('content-disposition');
      if (disposition != null && disposition.contains('filename=')) {
        try {
          final regex = RegExp(r"""filename\*?=(?:UTF-8'')?["']?([^"';]+)["']?""");
          final match = regex.firstMatch(disposition);
          if (match != null && match.group(1) != null) {
            final decoded = Uri.decodeComponent(match.group(1)!);
            final sanitized = DownloadService.sanitizeFileName(decoded);
            if (sanitized.isNotEmpty && sanitized != task.fileName) {
              // 更新最终路径
              final dir = path.dirname(task.filePath);
              task.fileName = sanitized;
              task.filePath = path.join(dir, sanitized);
            }
          }
        } catch (_) {}
      }

      // 打开文件流写入
      final sink = tempFile.openWrite(
        mode: isResume ? FileMode.append : FileMode.write,
      );
      _activeSinks[task.id] = sink;

      final subscription = response.listen(
        (chunk) {
          sink.add(chunk);
          task.receivedBytes += chunk.length;
          _updateSpeedAndProgress(task);
        },
        onError: (e) {
          _handleTaskError(task, '传输异常: $e');
        },
        onDone: () async {
          await _handleTaskComplete(task, sink, tempFile);
        },
        cancelOnError: true,
      );

      _activeSubscriptions[task.id] = subscription;
    } catch (e) {
      _handleTaskError(task, '$e');
    } finally {
      client?.close();
    }
  }

  /// 节流更新瞬时下载速度与进度
  void _updateSpeedAndProgress(DownloadTask task) {
    final now = DateTime.now();
    final lastT = _lastTime[task.id] ?? now;
    final lastB = _lastBytes[task.id] ?? task.receivedBytes;
    final elapsedMs = now.difference(lastT).inMilliseconds;

    if (elapsedMs >= 500) {
      final bytesDiff = task.receivedBytes - lastB;
      if (bytesDiff >= 0 && elapsedMs > 0) {
        task.speed = (bytesDiff * 1000 ~/ elapsedMs);
      }
      _lastBytes[task.id] = task.receivedBytes;
      _lastTime[task.id] = now;
    }

    // 限制每 300ms 最多通知一次 UI
    if (now.difference(_lastNotifyTime).inMilliseconds >= 300) {
      _lastNotifyTime = now;
      notifyListeners();
    }
  }

  /// 任务正常下载完成处理
  Future<void> _handleTaskComplete(
    DownloadTask task,
    IOSink sink,
    File tempFile,
  ) async {
    try {
      await sink.flush();
      await sink.close();
      _activeSinks.remove(task.id);
      _activeSubscriptions.remove(task.id);
      _activeRequests.remove(task.id);

      // 将临时文件原子重命名为最终目标文件
      if (await tempFile.exists()) {
        // 如果最终文件已存在，先获取唯一路径
        final finalUniquePath =
            await DownloadService.getUniqueFilePath(task.filePath);
        final finalFile = File(finalUniquePath);
        await tempFile.rename(finalFile.path);
        task.filePath = finalFile.path;
        task.fileName = path.basename(finalFile.path);
      }

      task.status = DownloadStatus.completed;
      task.completeTime = DateTime.now();
      task.speed = 0;
      task.error = null;
      if (task.totalBytes <= 0) {
        task.totalBytes = task.receivedBytes;
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = '完成处理失败: $e';
    } finally {
      _cleanupTaskHandles(task.id);
      notifyListeners();
      await _saveTasks();
      _scheduleNextPendingTask();
    }
  }

  /// 任务异常处理
  void _handleTaskError(DownloadTask task, String errorMsg) {
    _cleanupTaskHandles(task.id);
    task.status = DownloadStatus.failed;
    task.error = errorMsg;
    task.speed = 0;
    notifyListeners();
    _saveTasks();
    _scheduleNextPendingTask();
  }

  /// 清理任务关联的所有网络和文件句柄
  void _cleanupTaskHandles(String taskId) {
    try {
      _activeSubscriptions[taskId]?.cancel();
    } catch (_) {}
    _activeSubscriptions.remove(taskId);

    try {
      _activeRequests[taskId]?.abort();
    } catch (_) {}
    _activeRequests.remove(taskId);

    try {
      _activeSinks[taskId]?.close();
    } catch (_) {}
    _activeSinks.remove(taskId);

    _lastBytes.remove(taskId);
    _lastTime.remove(taskId);
  }

  /// 调度下一个排队中的任务
  void _scheduleNextPendingTask() {
    final runningCount =
        _tasks.where((t) => t.status == DownloadStatus.downloading).length;
    if (runningCount >= maxConcurrentDownloads) return;

    final nextTaskIndex =
        _tasks.indexWhere((t) => t.status == DownloadStatus.pending);
    if (nextTaskIndex != -1) {
      startTask(_tasks[nextTaskIndex].id);
    }
  }

  /// 暂停任务
  Future<void> pauseTask(String taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = _tasks[taskIndex];

    _cleanupTaskHandles(taskId);
    task.status = DownloadStatus.paused;
    task.speed = 0;
    notifyListeners();
    await _saveTasks();

    _scheduleNextPendingTask();
  }

  /// 恢复任务（断点续传）
  void resumeTask(String taskId) {
    startTask(taskId);
  }

  /// 重试失败或已取消的任务
  void retryTask(String taskId) {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = _tasks[taskIndex];

    task.error = null;
    startTask(taskId);
  }

  /// 取消任务（删除未完成的临时文件）
  Future<void> cancelTask(String taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = _tasks[taskIndex];

    _cleanupTaskHandles(taskId);
    task.status = DownloadStatus.canceled;
    task.speed = 0;

    // 清理临时 .part 文件
    await DownloadService.deleteFile(task.filePath, tempPath: task.tempPath);
    task.receivedBytes = 0;

    notifyListeners();
    await _saveTasks();
    _scheduleNextPendingTask();
  }

  /// 删除任务（可选择是否连同本地文件一起删除）
  Future<void> deleteTask(String taskId, {bool deleteFileOnDisk = false}) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = _tasks[taskIndex];

    _cleanupTaskHandles(taskId);

    if (deleteFileOnDisk) {
      await DownloadService.deleteFile(task.filePath, tempPath: task.tempPath);
    }

    _tasks.removeAt(taskIndex);
    notifyListeners();
    await _saveTasks();
    _scheduleNextPendingTask();
  }

  /// 清理所有已完成/已取消的任务记录
  Future<void> clearCompletedTasks({bool deleteFilesOnDisk = false}) async {
    final toRemove = _tasks
        .where((t) =>
            t.status == DownloadStatus.completed ||
            t.status == DownloadStatus.canceled ||
            t.status == DownloadStatus.failed)
        .toList();

    for (var task in toRemove) {
      if (deleteFilesOnDisk) {
        await DownloadService.deleteFile(task.filePath, tempPath: task.tempPath);
      }
      _tasks.remove(task);
    }

    notifyListeners();
    await _saveTasks();
  }
}

/// 下载任务状态枚举
enum DownloadStatus {
  pending, // 等待中
  downloading, // 下载中
  paused, // 已暂停
  completed, // 已完成
  failed, // 下载失败
  canceled; // 已取消

  String get label {
    switch (this) {
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
      case DownloadStatus.canceled:
        return '已取消';
    }
  }
}

/// 下载任务模型
class DownloadTask {
  final String id;
  final String url;
  String fileName;
  String filePath;
  int receivedBytes;
  int totalBytes; // -1 表示未知大小
  DownloadStatus status;
  String? error;
  final DateTime createTime;
  DateTime? completeTime;
  int speed; // 字节/秒 (实时下载速度)
  String? mimeType;
  String? userAgent;
  String? cookies;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.filePath,
    this.receivedBytes = 0,
    this.totalBytes = -1,
    this.status = DownloadStatus.pending,
    this.error,
    DateTime? createTime,
    this.completeTime,
    this.speed = 0,
    this.mimeType,
    this.userAgent,
    this.cookies,
  }) : createTime = createTime ?? DateTime.now();

  /// 临时下载文件路径（未完成时以 .part 结尾，避免被用户或系统误认作完整文件）
  String get tempPath => '$filePath.part';

  /// 下载进度 (0.0 ~ 1.0)，如果未知总大小则返回 null
  double? get progress {
    if (totalBytes <= 0) return null;
    if (receivedBytes >= totalBytes) return 1.0;
    return receivedBytes / totalBytes;
  }

  /// 格式化进度百分比文本，例如 "45.2%"
  String get progressPercentage {
    if (totalBytes <= 0) {
      return formatBytes(receivedBytes);
    }
    final p = ((receivedBytes / totalBytes) * 100).clamp(0.0, 100.0);
    return '${p.toStringAsFixed(1)}%';
  }

  /// 格式化当前已下载字节大小
  String get formattedReceivedSize => formatBytes(receivedBytes);

  /// 格式化总字节大小
  String get formattedTotalSize => totalBytes > 0 ? formatBytes(totalBytes) : '未知大小';

  /// 格式化瞬时下载速度
  String get formattedSpeed {
    if (status != DownloadStatus.downloading || speed <= 0) {
      return '';
    }
    return '${formatBytes(speed)}/s';
  }

  /// 字节数通用格式化工具函数
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${suffixes[i]}';
  }

  /// 序列化为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'fileName': fileName,
      'filePath': filePath,
      'receivedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'status': status.name,
      'error': error,
      'createTime': createTime.toIso8601String(),
      'completeTime': completeTime?.toIso8601String(),
      'mimeType': mimeType,
      'userAgent': userAgent,
      'cookies': cookies,
    };
  }

  /// 从 JSON Map 反序列化
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    DownloadStatus parsedStatus = DownloadStatus.pending;
    if (json['status'] != null) {
      try {
        parsedStatus = DownloadStatus.values.byName(json['status'] as String);
      } catch (_) {
        parsedStatus = DownloadStatus.failed;
      }
    }
    // 如果持久化时是下载中，恢复时转为暂停
    if (parsedStatus == DownloadStatus.downloading) {
      parsedStatus = DownloadStatus.paused;
    }

    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? -1,
      status: parsedStatus,
      error: json['error'] as String?,
      createTime: json['createTime'] != null
          ? DateTime.tryParse(json['createTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      completeTime: json['completeTime'] != null
          ? DateTime.tryParse(json['completeTime'] as String)
          : null,
      mimeType: json['mimeType'] as String?,
      userAgent: json['userAgent'] as String?,
      cookies: json['cookies'] as String?,
    );
  }

  /// 复制并修改指定属性
  DownloadTask copyWith({
    String? fileName,
    String? filePath,
    int? receivedBytes,
    int? totalBytes,
    DownloadStatus? status,
    String? error,
    DateTime? completeTime,
    int? speed,
    String? mimeType,
    String? userAgent,
    String? cookies,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      error: error ?? this.error,
      createTime: createTime,
      completeTime: completeTime ?? this.completeTime,
      speed: speed ?? this.speed,
      mimeType: mimeType ?? this.mimeType,
      userAgent: userAgent ?? this.userAgent,
      cookies: cookies ?? this.cookies,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:auto_browser/models/download_task.dart';
import 'package:auto_browser/services/download_service.dart';

void main() {
  group('下载功能与数据模型测试', () {
    test('文件名非法字符过滤与清洗测试', () {
      expect(DownloadService.sanitizeFileName('test/file:name*?.zip'), 'test_file_name_.zip');
      expect(DownloadService.sanitizeFileName('   ...file.pdf..  '), 'file.pdf');
      expect(DownloadService.sanitizeFileName('normal_app.apk'), 'normal_app.apk');
    });

    test('从 URL 及 suggestedFilename 提取文件名测试', () {
      expect(
        DownloadService.extractFileName('https://example.com/downloads/package.zip?v=1.2.3'),
        'package.zip',
      );
      expect(
        DownloadService.extractFileName(
          'https://example.com/download',
          suggestedFilename: 'my_custom_setup.exe',
        ),
        'my_custom_setup.exe',
      );
    });

    test('字节与大小格式化测试', () {
      expect(DownloadTask.formatBytes(0), '0 B');
      expect(DownloadTask.formatBytes(1024), '1.0 KB');
      expect(DownloadTask.formatBytes(1024 * 1024 * 5), '5.0 MB');
      expect(DownloadTask.formatBytes(1024 * 1024 * 1024 * 2), '2.0 GB');
    });

    test('DownloadTask 序列化与反序列化测试', () {
      final task = DownloadTask(
        id: 'task_001',
        url: 'https://example.com/test.zip',
        fileName: 'test.zip',
        filePath: 'C:/Users/test/Downloads/test.zip',
        receivedBytes: 1024 * 500,
        totalBytes: 1024 * 1000,
        status: DownloadStatus.downloading,
        speed: 1024 * 100,
        userAgent: 'TestBrowser',
        cookies: 'session=123',
      );

      expect(task.tempPath, 'C:/Users/test/Downloads/test.zip.part');
      expect(task.progress, 0.5);
      expect(task.progressPercentage, '50.0%');
      expect(task.formattedSpeed, '100 KB/s');

      final jsonMap = task.toJson();
      final restored = DownloadTask.fromJson(jsonMap);

      expect(restored.id, task.id);
      expect(restored.url, task.url);
      expect(restored.fileName, task.fileName);
      expect(restored.filePath, task.filePath);
      expect(restored.receivedBytes, task.receivedBytes);
      expect(restored.totalBytes, task.totalBytes);
      // 重新加载时原本 downloading 的任务应平滑重置为 paused
      expect(restored.status, DownloadStatus.paused);
      expect(restored.userAgent, task.userAgent);
      expect(restored.cookies, task.cookies);
    });
  });
}

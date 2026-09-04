import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../services/download_service.dart';

/// 下载确认弹窗（支持查看和修改文件名与存储位置）
class DownloadConfirmDialog extends StatefulWidget {
  final String url;
  final String? suggestedFilename;
  final String? mimeType;
  final String? userAgent;
  final String? cookies;

  const DownloadConfirmDialog({
    super.key,
    required this.url,
    this.suggestedFilename,
    this.mimeType,
    this.userAgent,
    this.cookies,
  });

  /// 静态快速弹出确认窗口方法
  static Future<bool?> show(
    BuildContext context, {
    required String url,
    String? suggestedFilename,
    String? mimeType,
    String? userAgent,
    String? cookies,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => DownloadConfirmDialog(
        url: url,
        suggestedFilename: suggestedFilename,
        mimeType: mimeType,
        userAgent: userAgent,
        cookies: cookies,
      ),
    );
  }

  @override
  State<DownloadConfirmDialog> createState() => _DownloadConfirmDialogState();
}

class _DownloadConfirmDialogState extends State<DownloadConfirmDialog> {
  late final TextEditingController _nameController;
  String _saveDirectory = '正在获取...';

  @override
  void initState() {
    super.initState();
    final defaultName = DownloadService.extractFileName(
      widget.url,
      suggestedFilename: widget.suggestedFilename,
    );
    _nameController = TextEditingController(text: defaultName);
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final dir = await DownloadService.getDownloadDirectory();
    if (mounted) {
      setState(() {
        _saveDirectory = dir;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirmDownload() {
    final fileName = _nameController.text.trim();
    if (fileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件名不能为空')),
      );
      return;
    }

    final downloadProvider =
        Provider.of<DownloadProvider>(context, listen: false);

    downloadProvider.addTask(
      url: widget.url,
      customFileName: fileName,
      mimeType: widget.mimeType,
      userAgent: widget.userAgent,
      cookies: widget.cookies,
      autoStart: true,
    );

    DownloadService.showDownloadStarted(context, fileName);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF242424) : Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withAlpha(40),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.download_rounded, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            '新建下载任务',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文件名输入框
              const Text(
                '文件名',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
                  prefixIcon: const Icon(Icons.insert_drive_file_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              // 目标保存路径
              const Text(
                '保存位置',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 20, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveDirectory,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 下载链接预览
              const Text(
                '下载链接',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.url,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton.icon(
          onPressed: _confirmDownload,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('立即下载'),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../providers/download_provider.dart';
import '../services/download_service.dart';
import 'download_confirm_dialog.dart';

/// 跨平台下载管理器界面（支持 Windows / Android / iOS）
class DownloadManagerDialog extends StatefulWidget {
  const DownloadManagerDialog({super.key});

  /// 静态调起下载管理器方法
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const DownloadManagerDialog(),
    );
  }

  @override
  State<DownloadManagerDialog> createState() => _DownloadManagerDialogState();
}

class _DownloadManagerDialogState extends State<DownloadManagerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 弹出手动新建下载任务的弹窗
  void _showNewDownloadDialog(BuildContext context) {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_link_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('新建下载', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入下载链接 (HTTP / HTTPS):', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'https://example.com/file.zip',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty || !url.startsWith('http')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入合法的 HTTP/HTTPS 下载链接')),
                );
                return;
              }
              Navigator.pop(ctx);
              DownloadConfirmDialog.show(context, url: url);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('下一步'),
          ),
        ],
      ),
    );
  }

  /// 清空任务历史
  void _confirmClearTasks(BuildContext context, DownloadProvider provider) {
    bool deleteFiles = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('清空下载记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('确定要清空所有已完成和已取消的下载记录吗？'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (v) {
                  setStateDialog(() {
                    deleteFiles = v ?? false;
                  });
                },
                title: const Text('同时删除本地磁盘文件', style: TextStyle(fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                provider.clearCompletedTasks(deleteFilesOnDisk: deleteFiles);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('确定清空'),
            ),
          ],
        ),
      ),
    );
  }

  /// 根据后缀获取文件对应图标和色彩
  Widget _buildFileIcon(String fileName) {
    final ext = path.extension(fileName).toLowerCase().replaceAll('.', '');
    IconData iconData = Icons.insert_drive_file_rounded;
    Color iconColor = Colors.grey;

    if (['apk'].contains(ext)) {
      iconData = Icons.android_rounded;
      iconColor = const Color(0xFF4CAF50);
    } else if (['exe', 'msi', 'dmg', 'pkg'].contains(ext)) {
      iconData = Icons.settings_applications_rounded;
      iconColor = const Color(0xFF0288D1);
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      iconData = Icons.folder_zip_rounded;
      iconColor = const Color(0xFFFF9800);
    } else if (['mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv'].contains(ext)) {
      iconData = Icons.video_file_rounded;
      iconColor = const Color(0xFF9C27B0);
    } else if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'].contains(ext)) {
      iconData = Icons.audio_file_rounded;
      iconColor = const Color(0xFFE91E63);
    } else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      iconData = Icons.image_rounded;
      iconColor = const Color(0xFF00BCD4);
    } else if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(ext)) {
      iconData = Icons.description_rounded;
      iconColor = const Color(0xFFF44336);
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    final isDesktop = size.width >= 700;
    final dialogWidth = isDesktop ? 680.0 : size.width * 0.94;
    final dialogHeight = isDesktop ? 600.0 : size.height * 0.85;

    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, child) {
        final allTasks = downloadProvider.tasks;
        final downloadingTasks = downloadProvider.tasks
            .where((t) =>
                t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.pending ||
                t.status == DownloadStatus.paused)
            .toList();
        final completedTasks = downloadProvider.tasks
            .where((t) =>
                t.status == DownloadStatus.completed ||
                t.status == DownloadStatus.failed ||
                t.status == DownloadStatus.canceled)
            .toList();

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              children: [
                // 顶部标题栏
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F8FA),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.download_for_offline_rounded,
                              color: Colors.blueAccent, size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            '下载管理',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          // 新建下载按钮
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 22),
                            tooltip: '新建下载',
                            onPressed: () => _showNewDownloadDialog(context),
                          ),
                          // 清空历史按钮
                          if (completedTasks.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.delete_sweep_rounded, size: 22),
                              tooltip: '清空历史',
                              onPressed: () =>
                                  _confirmClearTasks(context, downloadProvider),
                            ),
                          // 关闭按钮
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 22),
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      // 分类 Tab
                      TabBar(
                        controller: _tabController,
                        labelColor: Colors.blueAccent,
                        unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
                        indicatorColor: Colors.blueAccent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        tabs: [
                          Tab(text: '全部 (${allTasks.length})'),
                          Tab(text: '进行中 (${downloadingTasks.length})'),
                          Tab(text: '已完成 (${completedTasks.length})'),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab 内容列表
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTaskList(allTasks, downloadProvider, isDark),
                      _buildTaskList(downloadingTasks, downloadProvider, isDark),
                      _buildTaskList(completedTasks, downloadProvider, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 列表构建视图
  Widget _buildTaskList(
    List<DownloadTask> tasks,
    DownloadProvider provider,
    bool isDark,
  ) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 56,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无下载任务',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildTaskCard(task, provider, isDark);
      },
    );
  }

  /// 单个任务卡片
  Widget _buildTaskCard(DownloadTask task, DownloadProvider provider, bool isDark) {
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isPending = task.status == DownloadStatus.pending;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildFileIcon(task.fileName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 状态描述行
                    _buildStatusDescription(task, isDark),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 快捷操作按钮组
              _buildActionButtons(task, provider),
            ],
          ),

          // 正在下载或暂停时显示进度条
          if (isDownloading || isPaused || isPending) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 5,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPaused ? Colors.amber : Colors.blueAccent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 状态描述文本（包含大小、速度、状态标签）
  Widget _buildStatusDescription(DownloadTask task, bool isDark) {
    if (task.status == DownloadStatus.downloading) {
      return Row(
        children: [
          Text(
            '${task.formattedReceivedSize} / ${task.formattedTotalSize}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Spacer(),
          if (task.formattedSpeed.isNotEmpty)
            Text(
              task.formattedSpeed,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blueAccent,
              ),
            ),
        ],
      );
    } else if (task.status == DownloadStatus.paused) {
      return Text(
        '已暂停 (${task.progressPercentage}) - 已下载 ${task.formattedReceivedSize}',
        style: const TextStyle(fontSize: 12, color: Colors.amber),
      );
    } else if (task.status == DownloadStatus.pending) {
      return const Text(
        '正在等待下载队列...',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    } else if (task.status == DownloadStatus.completed) {
      return Text(
        '下载完成 · ${task.formattedTotalSize}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50)),
      );
    } else if (task.status == DownloadStatus.failed) {
      return Text(
        '下载失败: ${task.error ?? "未知错误"}',
        style: const TextStyle(fontSize: 12, color: Colors.redAccent),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      return const Text(
        '已取消',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
  }

  /// 卡片右侧动作按钮
  Widget _buildActionButtons(DownloadTask task, DownloadProvider provider) {
    if (task.status == DownloadStatus.downloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause_circle_outline_rounded, color: Colors.amber),
            tooltip: '暂停',
            onPressed: () => provider.pauseTask(task.id),
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.grey),
            tooltip: '取消',
            onPressed: () => provider.cancelTask(task.id),
          ),
        ],
      );
    } else if (task.status == DownloadStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.blueAccent),
            tooltip: '继续下载',
            onPressed: () => provider.resumeTask(task.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
            tooltip: '删除任务',
            onPressed: () => provider.deleteTask(task.id, deleteFileOnDisk: true),
          ),
        ],
      );
    } else if (task.status == DownloadStatus.pending) {
      return IconButton(
        icon: const Icon(Icons.cancel_outlined, color: Colors.grey),
        tooltip: '取消排队',
        onPressed: () => provider.cancelTask(task.id),
      );
    } else if (task.status == DownloadStatus.completed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 打开文件按钮
          IconButton(
            icon: const Icon(Icons.launch_rounded, color: Colors.blueAccent),
            tooltip: '打开文件',
            onPressed: () => DownloadService.openFile(context, task.filePath),
          ),
          // 资源管理器定位 / 移动端分享
          IconButton(
            icon: Icon(
              Platform.isWindows ? Icons.folder_open_rounded : Icons.share_rounded,
              color: Colors.teal,
            ),
            tooltip: Platform.isWindows ? '在文件夹中显示' : '分享文件',
            onPressed: () => DownloadService.showInFolder(context, task.filePath),
          ),
          // 删除记录菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
            onSelected: (value) {
              if (value == 'delete_record') {
                provider.deleteTask(task.id, deleteFileOnDisk: false);
              } else if (value == 'delete_file') {
                provider.deleteTask(task.id, deleteFileOnDisk: true);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete_record',
                child: Row(
                  children: [
                    Icon(Icons.clear_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('仅删除记录'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_file',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_rounded, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('同时删除磁盘文件', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // 失败或已取消
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.blueAccent),
            tooltip: '重新下载',
            onPressed: () => provider.retryTask(task.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
            tooltip: '删除记录',
            onPressed: () => provider.deleteTask(task.id, deleteFileOnDisk: true),
          ),
        ],
      );
    }
  }
}

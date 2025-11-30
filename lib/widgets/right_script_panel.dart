import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';
import 'add_script_dialog.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import '../utils/file_manager.dart';

class RightScriptPanel extends StatelessWidget {
  final VoidCallback onAddScript;
  final VoidCallback onGlobalSettings;
  final VoidCallback onExecute;
  final VoidCallback onLoad;
  final VoidCallback? onRecordScript; // Optional callback for recording

  const RightScriptPanel({
    super.key,
    required this.onAddScript,
    required this.onGlobalSettings,
    required this.onExecute,
    required this.onLoad,
    this.onRecordScript,
  });

  @override
  Widget build(BuildContext context) {
    final scriptProvider = context.watch<ScriptProvider>();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        border: const Border(
          left: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // --- Top Section: Global Settings ---
          InkWell(
            onTap: onGlobalSettings,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Left: Global Settings Title
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '全局',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right: Settings Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '执行速度: ',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${scriptProvider.executionDelay ~/ scriptProvider.delayTimeUnit.multiplier}${scriptProvider.delayTimeUnit.label}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text(
                              '循环次数: ',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${scriptProvider.originalLoopCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Divider 1 (White) - Separates Top and Middle
          Container(height: 1, color: Colors.white),

          // --- Middle Section: Script List & Management ---
          Expanded(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  color: Colors.white.withValues(alpha: 0.05),
                  child: Text(
                    '脚本列表 (${scriptProvider.scripts.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Divider (Subtle)
                const Divider(height: 1, color: Colors.white12),

                // Scrollable List
                Expanded(
                  child: scriptProvider.scripts.isEmpty
                      ? _buildEmptyState(scriptProvider)
                      : ListView.builder(
                          itemCount: scriptProvider.scripts.length,
                          itemBuilder: (context, index) =>
                              _buildScriptItem(context, scriptProvider, index),
                        ),
                ),

                // Divider (Subtle)
                const Divider(height: 1, color: Colors.white12),

                // Add Script Button
                InkWell(
                  onTap: onAddScript,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '添加脚本',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider 2 (White) - Separates Middle and Bottom
          Container(height: 1, color: Colors.white),

          // --- Bottom Section: Action Buttons ---
          IntrinsicHeight(
            child: scriptProvider.isExecuting
                ? _buildExecutingActions(scriptProvider)
                : _buildIdleActions(context, scriptProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ScriptProvider scriptProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '暂无脚本',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              if (!scriptProvider.isExecuting) {
                onRecordScript?.call();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                  SizedBox(width: 4),
                  Text(
                    '录制脚本',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptItem(
      BuildContext context, ScriptProvider scriptProvider, int index) {
    final script = scriptProvider.scripts[index];
    final isCurrent = scriptProvider.isExecuting &&
        scriptProvider.currentScriptIndex == index;

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AddScriptDialog(
            script: script,
            index: index,
          ),
        );
      },
      onLongPress: () {
        _showScriptContextMenu(context, scriptProvider, index);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        color: isCurrent ? Colors.blue.withValues(alpha: 0.3) : null,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  script.type,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getScriptContent(script),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
                if (index < scriptProvider.scripts.length - 1)
                  const Divider(color: Colors.grey, height: 8),

                // Status Line
                if (scriptProvider.isExecuting &&
                    script.status != ScriptStatus.idle) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _getStatusIcon(script.status),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getStatusText(script),
                              style: TextStyle(
                                color: _getStatusColor(script.status),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (script.progress != null &&
                                script.progress! >= 0 &&
                                script.progress! <= 1.0) ...[
                              const SizedBox(height: 2),
                              LinearProgressIndicator(
                                value: script.progress,
                                backgroundColor: Colors.white24,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    _getStatusColor(script.status)),
                                minHeight: 2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            // Numbering Badge (ignore pointer so it doesn't block touches)
            Positioned(
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScriptContextMenu(
      BuildContext context, ScriptProvider scriptProvider, int index) {
    final script = scriptProvider.scripts[index];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 禁用/启用
              ListTile(
                leading: Icon(
                  script.isEnabled ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white,
                ),
                title: Text(
                  script.isEnabled ? '禁用' : '启用',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  scriptProvider.toggleScriptEnabled(index, !script.isEnabled);
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 复制
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white),
                title: const Text('复制', style: TextStyle(color: Colors.white)),
                onTap: () {
                  final copied = scriptProvider.duplicateScript(index);
                  if (copied != null) {
                    scriptProvider.addScript(copied);
                  }
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 在前粘贴脚本
              ListTile(
                leading: const Icon(Icons.content_paste, color: Colors.white),
                title:
                    const Text('在前粘贴脚本', style: TextStyle(color: Colors.white)),
                onTap: () {
                  final copied = scriptProvider.duplicateScript(index);
                  if (copied != null) {
                    scriptProvider.insertScript(index, copied);
                  }
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 删除
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  scriptProvider.removeScript(index);
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 在前插入新脚本
              ListTile(
                leading:
                    const Icon(Icons.add_circle_outline, color: Colors.white),
                title: const Text('在前插入新脚本',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);

                  // Show index info on screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('准备在位置 $index 插入 (序号${index + 1}之前)'),
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  final result = await showDialog<Script>(
                    context: context,
                    builder: (context) => const AddScriptDialog(),
                  );
                  if (result != null) {
                    scriptProvider.insertScript(index, result);

                    // Show result
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '已插入到位置 $index，现在共${scriptProvider.scripts.length}个脚本'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExecutingActions(ScriptProvider scriptProvider) {
    return Row(
      children: [
        // Pause/Resume button
        Expanded(
          child: InkWell(
            onTap: () {
              if (scriptProvider.isPaused) {
                scriptProvider.resumeExecution();
              } else {
                scriptProvider.pauseExecution();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(
                scriptProvider.isPaused ? Icons.play_arrow : Icons.pause,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Stop button
        Expanded(
          child: InkWell(
            onTap: () => scriptProvider.stopExecution(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: const Text(
                '停止',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Counts display
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '失败${scriptProvider.failureCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '成功${scriptProvider.successCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdleActions(
      BuildContext context, ScriptProvider scriptProvider) {
    return Row(
      children: [
        // Execute button
        Expanded(
          child: InkWell(
            onTap: scriptProvider.isRecording ? null : onExecute,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '执行',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      scriptProvider.isRecording ? Colors.grey : Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Load button
        Expanded(
          child: InkWell(
            onTap: () {
              _handleLoadScript(context, scriptProvider);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: const Text(
                '读取',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Menu button (3 dots)
        Expanded(
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
            color: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (value) {
              if (value == 'share') {
                _showShareDialog(context, scriptProvider);
              } else if (value == 'clear') {
                scriptProvider.clearScripts();
              } else if (value == 'save') {
                _showSaveDialog(context, scriptProvider);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share',
                child: Text('分享', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('清空', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'save',
                child: Text('保存', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getScriptContent(Script script) {
    final params = script.params;
    switch (script.type) {
      case '点击文字':
        return '点击: ${params['点击文本'] ?? ''}';
      case '点击图片':
        return '点击图片';
      case '输入框提交':
        final List<String> parts = [];
        if (params['提交按钮文字'] != null &&
            params['提交按钮文字'].toString().isNotEmpty) {
          parts.add('提交: ${params['提交按钮文字']}');
        }
        final formData = params['表单数据'];
        if (formData is Map && formData.isNotEmpty) {
          parts.addAll(formData.entries.map((e) => '${e.key}: ${e.value}'));
        }
        return parts.join('\n');
      case '进入网址':
        return '网址: ${params['网址'] ?? ''}';
      case '间隔时间':
        final h = params['时间间隔-小时'] ?? 0;
        final m = params['时间间隔-分钟'] ?? 0;
        final s = params['时间间隔-秒'] ?? 0;
        return '等待: $h时$m分$s秒';
      case '跳转脚本':
        return '跳转到: ${params['跳转标签'] ?? ''}';
      case '延时脚本':
        return '延时: ${params['延时时间'] ?? 0}ms';
      case '逻辑脚本-出现文字':
        return '检测: ${params['出现文字'] ?? ''}';
      case '刷新网页':
        return '刷新当前页面';
      case '网页后退':
        return '后退';
      case '网页前进':
        return '前进';
      case '脚本停止':
        return '停止运行';
      case '脚本暂停':
        return '暂停运行';
      default:
        if (params.containsKey('执行延迟')) {
          return '延迟: ${params['执行延迟']}ms';
        }
        return '';
    }
  }

  Widget _getStatusIcon(ScriptStatus status) {
    switch (status) {
      case ScriptStatus.success:
        return const Icon(Icons.check, color: Colors.green, size: 12);
      case ScriptStatus.failure:
        return const Icon(Icons.close, color: Colors.red, size: 12);
      case ScriptStatus.waiting:
        return const Icon(Icons.access_time, color: Colors.orange, size: 12);
      case ScriptStatus.running:
        return const Icon(Icons.arrow_forward, color: Colors.blue, size: 12);
      default:
        return const SizedBox.shrink();
    }
  }

  Color _getStatusColor(ScriptStatus status) {
    switch (status) {
      case ScriptStatus.success:
        return Colors.green;
      case ScriptStatus.failure:
        return Colors.red;
      case ScriptStatus.waiting:
        return Colors.orange;
      case ScriptStatus.running:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(Script script) {
    if (script.statusMessage != null) {
      return script.statusMessage!;
    }
    switch (script.status) {
      case ScriptStatus.success:
        return '成功';
      case ScriptStatus.failure:
        return '失败';
      case ScriptStatus.waiting:
        return '等待中';
      case ScriptStatus.running:
        return '执行中';
      default:
        return '';
    }
  }

  Future<void> _handleSaveScript(
      BuildContext context, ScriptProvider scriptProvider) async {
    try {
      final String? existingFilePath = scriptProvider.currentScriptFilePath;
      String filePath;

      if (existingFilePath == null || existingFilePath.isEmpty) {
        // First-time save: ask for filename and use default directory
        final String defaultDir = await FileManager.getScriptDirectory();

        if (!context.mounted) return;

        // Show filename input dialog
        final TextEditingController filenameController = TextEditingController(
          text: 'script_${DateTime.now().millisecondsSinceEpoch}',
        );

        final filename = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            title: const Text('输入文件名', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: filenameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '脚本名称',
                hintStyle: TextStyle(color: Colors.white54),
                suffixText: '.json',
                suffixStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消', style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, filenameController.text);
                },
                child: const Text('保存', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );

        if (filename == null || filename.isEmpty) return;

        // Create full file path in default directory
        filePath = path.join(defaultDir, '$filename.json');
      } else {
        // Overwrite existing file
        filePath = existingFilePath;
      }

      // Get script content and save
      final scriptContent = scriptProvider.exportScript();
      final file = File(filePath);
      await file.writeAsString(scriptContent);

      // Update file path in provider
      scriptProvider.updateScriptFilePath(filePath);

      // Show success message
      if (context.mounted) {
        final String message = existingFilePath == null
            ? '脚本已保存到: Auok/脚本/${path.basename(filePath)}'
            : '脚本已更新';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleShareScript(
      BuildContext context, ScriptProvider scriptProvider) async {
    try {
      final String? filePath = scriptProvider.currentScriptFilePath;

      // Check if script is saved
      if (filePath == null ||
          filePath.isEmpty ||
          !await FileManager.fileExists(filePath)) {
        // Show warning: file not saved
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('你还没有保存文件，请先保存'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Share the saved file
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: '脚本分享',
        text: '这是我的浏览器自动化脚本',
      );

      if (context.mounted && result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('分享成功'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分享失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleLoadScript(
      BuildContext context, ScriptProvider scriptProvider) async {
    try {
      // Get default script directory
      final String defaultDir = await FileManager.getScriptDirectory();

      // Let user pick a JSON file from default directory
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择脚本文件',
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: defaultDir,
      );

      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
      final file = File(filePath);

      // Read file content
      final content = await file.readAsString();

      // Import script
      scriptProvider.importScript(content);

      // Update file path for this tab
      scriptProvider.updateScriptFilePath(filePath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已加载: ${path.basename(filePath)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('读取失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context, ScriptProvider scriptProvider) {
    _handleShareScript(context, scriptProvider);
  }

  void _showSaveDialog(BuildContext context, ScriptProvider scriptProvider) {
    _handleSaveScript(context, scriptProvider);
  }
}

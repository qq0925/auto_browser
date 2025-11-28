import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';
import 'add_script_dialog.dart';

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
          // Top Section: Global Settings (centered) + Script Info
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Global Settings button (left)
                Expanded(
                  child: InkWell(
                    onTap: onGlobalSettings,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: const Text(
                        '全局设置',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
                // Vertical divider
                Container(
                  width: 1,
                  color: Colors.white,
                ),
                // Script info (right)
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '执行延迟',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${scriptProvider.executionDelay ~/ scriptProvider.delayTimeUnit.multiplier}${scriptProvider.delayTimeUnit.label}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '循环次数',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                  ),
                ),
              ],
            ),
          ),

          // White divider
          Container(height: 1, color: Colors.white),

          // Middle Section: Script List (scrollable)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Text(
              '脚本列表 (${scriptProvider.scripts.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),

          // White divider
          Container(height: 1, color: Colors.white),

          // Scrollable script list
          Expanded(
            child: scriptProvider.scripts.isEmpty
                ? Center(
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white54),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fiber_manual_record,
                                    color: Colors.red, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  '录制脚本',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: scriptProvider.scripts.length,
                    itemBuilder: (context, index) {
                      final script = scriptProvider.scripts[index];
                      final isCurrent = scriptProvider.isExecuting &&
                          scriptProvider.currentScriptIndex == index;

                      return InkWell(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AddScriptDialog(
                              script: script,
                              index: index,
                            ),
                          );
                        },
                        child: Container(
                          color: isCurrent
                              ? Colors.blue.withValues(alpha: 0.3)
                              : null,
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 8),
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (index < scriptProvider.scripts.length - 1)
                                    const Divider(
                                        color: Colors.grey, height: 8),

                                  // Status Line
                                  if (scriptProvider.isExecuting &&
                                      script.status != ScriptStatus.idle) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _getStatusIcon(script.status),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            _getStatusText(script),
                                            style: TextStyle(
                                              color: _getStatusColor(
                                                  script.status),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              // Numbering Badge
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
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
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // White divider
          Container(height: 1, color: Colors.white),

          // Add Script Section
          InkWell(
            onTap: onAddScript,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
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

          // White divider
          Container(height: 1, color: Colors.white),

          // Bottom Section: Action buttons
          IntrinsicHeight(
            child: scriptProvider.isExecuting
                ? Row(
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
                              scriptProvider.isPaused
                                  ? Icons.play_arrow
                                  : Icons.pause,
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
                  )
                : Row(
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
                                color: scriptProvider.isRecording
                                    ? Colors.grey
                                    : Colors.white,
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
                          onTap: onLoad,
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
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white, size: 20),
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
                              child: Text('分享',
                                  style: TextStyle(color: Colors.white)),
                            ),
                            const PopupMenuItem(
                              value: 'clear',
                              child: Text('清空',
                                  style: TextStyle(color: Colors.white)),
                            ),
                            const PopupMenuItem(
                              value: 'save',
                              child: Text('保存',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
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
        return '输入: ${params['输入框值'] ?? ''}';
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

  void _showShareDialog(BuildContext context, ScriptProvider scriptProvider) {
    final scriptText = scriptProvider.exportScript();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('分享脚本', style: TextStyle(color: Colors.white)),
        content: SelectableText(
          scriptText,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSaveDialog(BuildContext context, ScriptProvider scriptProvider) {
    final scriptText = scriptProvider.exportScript();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('保存脚本', style: TextStyle(color: Colors.white)),
        content: Text(
          '脚本已导出到剪贴板:\n$scriptText',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

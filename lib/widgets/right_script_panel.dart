import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';
import 'add_script_dialog.dart';
import 'global_settings_dialog.dart';

class RightScriptPanel extends StatelessWidget {
  final VoidCallback onAddScript;
  final VoidCallback onGlobalSettings;
  final VoidCallback onExecute;
  final VoidCallback onLoad;

  const RightScriptPanel({
    super.key,
    required this.onAddScript,
    required this.onGlobalSettings,
    required this.onExecute,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    final scriptProvider = context.watch<ScriptProvider>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF303030), // Darker background
        border: const Border(
          left: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Top Section: Global Settings & Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF424242),
              border: Border(
                bottom: BorderSide(color: Colors.grey[700]!, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Global Settings Row
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const GlobalSettingsDialog(),
                    );
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '全局',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '执行延迟',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                                const Spacer(),
                                Text(
                                  '${scriptProvider.executionDelay ~/ scriptProvider.delayTimeUnit.multiplier}${scriptProvider.delayTimeUnit.label}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text(
                                  '循环次数',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                                const Spacer(),
                                Text(
                                  '${scriptProvider.originalLoopCount}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Extra Actions Row (Load, Menu) - Moved here since bottom bar is replaced
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: onLoad,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text('读取',
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz,
                          color: Colors.white, size: 20),
                      color: const Color(0xFF424242),
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
                          child:
                              Text('分享', style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: 'clear',
                          child:
                              Text('清空', style: TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(
                          value: 'save',
                          child:
                              Text('保存', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Middle Section: Script List Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            color: const Color(0xFF383838),
            child: Row(
              children: [
                Text(
                  '脚本列表 (${scriptProvider.scripts.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                // Add Script Button (Small icon)
                InkWell(
                  onTap: onAddScript,
                  child: const Icon(Icons.add_circle_outline,
                      color: Colors.white, size: 18),
                ),
              ],
            ),
          ),

          // Scrollable script list
          Expanded(
            child: scriptProvider.scripts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '暂无脚本',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        // Record Script Button for Empty State
                        InkWell(
                          onTap: () {
                            if (!scriptProvider.isRecording) {
                              scriptProvider.startRecording();
                            } else {
                              scriptProvider.stopRecording();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white54),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  scriptProvider.isRecording
                                      ? Icons.stop
                                      : Icons.fiber_manual_record,
                                  color: scriptProvider.isRecording
                                      ? Colors.red
                                      : Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  scriptProvider.isRecording ? '停止录制' : '录制脚本',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
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
                              ? Colors.blue.withValues(alpha: 0.2)
                              : null,
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey[800]!, width: 0.5),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        script.type,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _getScriptContent(script),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  // Status Line
                                  if (scriptProvider.isExecuting &&
                                      script.status != ScriptStatus.idle) ...[
                                    const SizedBox(height: 6),
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
                                              fontSize: 11,
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
                              // Number Badge (Top Right)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[700],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
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

          // Bottom Control Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF424242),
              border: Border(
                top: BorderSide(color: Colors.grey, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Pause/Resume Button (Icon)
                IconButton(
                  icon: Icon(
                    scriptProvider.isPaused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white,
                  ),
                  onPressed: scriptProvider.isExecuting
                      ? () {
                          if (scriptProvider.isPaused) {
                            scriptProvider.resumeExecution();
                          } else {
                            scriptProvider.pauseExecution();
                          }
                        }
                      : null, // Disabled if not executing
                ),

                // Stop Button (Text)
                Expanded(
                  child: InkWell(
                    onTap: scriptProvider.isExecuting
                        ? onExecute
                        : null, // onExecute toggles, but here we want stop
                    child: Center(
                      child: Text(
                        '停止',
                        style: TextStyle(
                          color: scriptProvider.isExecuting
                              ? Colors.white
                              : Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),

                // Success/Failure Counts
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '失败${scriptProvider.failureCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      '成功${scriptProvider.successCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
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
        return const Icon(Icons.check, color: Colors.green, size: 14);
      case ScriptStatus.failure:
        return const Icon(Icons.close, color: Colors.red, size: 14);
      case ScriptStatus.waiting:
        return const Icon(Icons.access_time,
            color: Colors.orange, size: 14); // Clock icon
      case ScriptStatus.running:
        return const Icon(Icons.arrow_forward,
            color: Colors.blue, size: 14); // Arrow icon
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';

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
        color: Colors.black.withValues(alpha: 0.7),
        border: const Border(
          left: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Top Section: Global + Script Info (side by side)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Global button (left)
                Expanded(
                  child: InkWell(
                    onTap: onGlobalSettings,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: const Text(
                        '全局',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
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
                ? const Center(
                    child: Text(
                      '暂无脚本',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    itemCount: scriptProvider.scripts.length,
                    itemBuilder: (context, index) {
                      final script = scriptProvider.scripts[index];
                      final isCurrent = scriptProvider.isExecuting &&
                          scriptProvider.currentScriptIndex == index;

                      return Container(
                        color: isCurrent
                            ? Colors.blue.withValues(alpha: 0.3)
                            : null,
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 8),
                        child: Column(
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
                              const Divider(color: Colors.grey, height: 8),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // White divider
          Container(height: 1, color: Colors.white),

          // Bottom Section: Action buttons (Execute | Load | Menu)
          IntrinsicHeight(
            child: Row(
              children: [
                // Execute button
                Expanded(
                  child: InkWell(
                    onTap: onExecute,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        scriptProvider.isExecuting ? '停止' : '执行',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scriptProvider.isExecuting
                              ? Colors.red
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
                        // TODO: Implement share functionality
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getScriptContent(Script script) {
    if (script.type == '点击文字') {
      return script.params['点击文字'] ?? '';
    } else if (script.type == '输入框提交') {
      return script.params.toString();
    }
    return '';
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

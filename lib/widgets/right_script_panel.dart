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
      width: 100,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        border: const Border(
          left: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // 全局按钮
          _buildButton(
            context,
            '全局',
            onGlobalSettings,
          ),
          const Divider(color: Colors.grey, height: 1),

          // 执行速度
          _buildInfoItem(
            '执行速度',
            '${scriptProvider.executionDelay ~/ scriptProvider.delayTimeUnit.multiplier}${scriptProvider.delayTimeUnit.label}',
          ),
          const Divider(color: Colors.grey, height: 1),

          // 循环次数
          _buildInfoItem(
            '循环次数',
            '${scriptProvider.originalLoopCount}',
          ),
          const Divider(color: Colors.grey, height: 1),

          // 脚本列表标题
          _buildInfoItem(
            '脚本列表',
            '${scriptProvider.scripts.length}',
          ),
          const Divider(color: Colors.grey, height: 1),

          // 脚本列表
          Expanded(
            child: ListView.builder(
              itemCount: scriptProvider.scripts.length,
              itemBuilder: (context, index) {
                final script = scriptProvider.scripts[index];
                final isCurrent = scriptProvider.isExecuting &&
                    scriptProvider.currentScriptIndex == index;

                return Container(
                  color: isCurrent ? Colors.blue.withValues(alpha: 0.3) : null,
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        script.type,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _getScriptContent(script),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (index < scriptProvider.scripts.length - 1)
                        const Divider(color: Colors.grey, height: 1),
                    ],
                  ),
                );
              },
            ),
          ),

          const Divider(color: Colors.grey, height: 1),

          // 添加脚本按钮
          _buildButton(
            context,
            '⊕ 添加脚本',
            onAddScript,
          ),
          const Divider(color: Colors.grey, height: 1),

          // 执行按钮
          _buildButton(
            context,
            scriptProvider.isExecuting ? '停止' : '执行',
            onExecute,
            color: scriptProvider.isExecuting ? Colors.red : null,
          ),
          const Divider(color: Colors.grey, height: 1),

          // 读取按钮
          _buildButton(
            context,
            '读取',
            onLoad,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, String text, VoidCallback onPressed,
      {Color? color}) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 13,
          ),
        ),
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
}

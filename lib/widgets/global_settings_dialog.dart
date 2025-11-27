import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';

class GlobalSettingsDialog extends StatefulWidget {
  const GlobalSettingsDialog({super.key});

  @override
  State<GlobalSettingsDialog> createState() => _GlobalSettingsDialogState();
}

class _GlobalSettingsDialogState extends State<GlobalSettingsDialog> {
  late TextEditingController _delayController;
  late TextEditingController _loopController;
  String _timeUnit = '毫秒';
  bool _showCompleteAlert = false;
  String _executionLogic = '默认(顺序模式)';

  @override
  void initState() {
    super.initState();
    final scriptProvider = context.read<ScriptProvider>();
    _delayController = TextEditingController(
      text: (scriptProvider.executionDelay ~/
              scriptProvider.delayTimeUnit.multiplier)
          .toString(),
    );
    _loopController = TextEditingController(
      text: scriptProvider.originalLoopCount.toString(),
    );
    _timeUnit = scriptProvider.delayTimeUnit.label;
  }

  @override
  void dispose() {
    _delayController.dispose();
    _loopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black87,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  '全局',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 执行延迟
              Row(
                children: [
                  const Text(
                    '执行延迟',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _delayController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white24,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButton<String>(
                      value: _timeUnit,
                      dropdownColor: Colors.black87,
                      style: const TextStyle(color: Colors.white),
                      underline: Container(),
                      items: const [
                        DropdownMenuItem(value: '毫秒', child: Text('毫秒')),
                        DropdownMenuItem(value: '秒', child: Text('秒')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _timeUnit = value);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 循环次数
              Row(
                children: [
                  const Text(
                    '循环次数',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _loopController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white24,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 执行完成提醒
              CheckboxListTile(
                title: const Text(
                  '执行完成提醒',
                  style: TextStyle(color: Colors.white),
                ),
                value: _showCompleteAlert,
                onChanged: (value) {
                  setState(() => _showCompleteAlert = value ?? false);
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.blue,
                checkColor: Colors.white,
              ),

              // 执行逻辑
              Row(
                children: [
                  const Text(
                    '执行逻辑',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: _executionLogic,
                        isExpanded: true,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        underline: Container(),
                        items: const [
                          DropdownMenuItem(
                            value: '默认(顺序模式)',
                            child: Text('默认(顺序模式)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _executionLogic = value);
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 执行每个脚本前执行
              const Text(
                '执行每个脚本前执行:',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '点击设置脚本(选填)',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              // 所有脚本均执行失败后执行
              const Text(
                '所有脚本均执行失败后执行:',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '点击设置脚本(选填)',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // 按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white24,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        final scriptProvider = context.read<ScriptProvider>();
                        final delay =
                            int.tryParse(_delayController.text) ?? 1000;
                        final loop = int.tryParse(_loopController.text) ?? 1;

                        final unit = TimeUnit.values.firstWhere(
                          (u) => u.label == _timeUnit,
                          orElse: () => TimeUnit.milliseconds,
                        );

                        scriptProvider.setDelayTimeUnit(unit);
                        scriptProvider
                            .setExecutionDelay(delay * unit.multiplier);
                        scriptProvider.setLoopCount(loop);

                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white24,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

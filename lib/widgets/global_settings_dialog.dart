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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Rounded corners
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
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
                const SizedBox(
                  width: 80,
                  child: Text(
                    '执行延迟',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
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
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      DropdownMenuItem(value: '分', child: Text('分')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _timeUnit = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 循环次数
            Row(
              children: [
                const SizedBox(
                  width: 80,
                  child: Text(
                    '循环次数',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _loopController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white24,
                      hintText: '0 = 无限循环',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
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
                      final delay = int.tryParse(_delayController.text) ?? 1000;
                      final loop = int.tryParse(_loopController.text) ?? 1;

                      // Map '分' to TimeUnit
                      TimeUnit unit;
                      if (_timeUnit == '毫秒') {
                        unit = TimeUnit.milliseconds;
                      } else if (_timeUnit == '秒') {
                        unit = TimeUnit.seconds;
                      } else {
                        unit = TimeUnit.minutes;
                      }

                      scriptProvider.setDelayTimeUnit(unit);
                      scriptProvider.setExecutionDelay(delay * unit.multiplier);
                      scriptProvider.setLoopCount(loop);

                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
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
    );
  }
}

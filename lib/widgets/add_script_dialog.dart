import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';

class AddScriptDialog extends StatefulWidget {
  const AddScriptDialog({super.key});

  @override
  State<AddScriptDialog> createState() => _AddScriptDialogState();
}

class _AddScriptDialogState extends State<AddScriptDialog> {
  String _scriptType = '点击文字';
  final TextEditingController _contentController = TextEditingController();

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '添加脚本',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 脚本类型选择
            Row(
              children: [
                const Text(
                  '脚本类型',
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
                      value: _scriptType,
                      isExpanded: true,
                      dropdownColor: Colors.black87,
                      style: const TextStyle(color: Colors.white),
                      underline: Container(),
                      items: const [
                        DropdownMenuItem(
                          value: '点击文字',
                          child: Text('点击文字'),
                        ),
                        DropdownMenuItem(
                          value: '简易',
                          child: Text('简易'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _scriptType = value;
                          });
                        }
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                  onPressed: () {
                    // 显示帮助
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 内容输入
            Row(
              children: [
                Text(
                  _scriptType == '点击文字' ? '点击文字' : '内容',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    style: const TextStyle(color: Colors.white),
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
                  onPressed: () {
                    // 显示帮助
                  },
                ),
              ],
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
                      scriptProvider.addScript(Script(
                        type: _scriptType,
                        params: {_scriptType: _contentController.text},
                        isEnabled: true,
                      ));
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
    );
  }
}

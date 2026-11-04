import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AutoRefreshDialog extends StatefulWidget {
  final Function(int interval, int count) onConfirm;

  const AutoRefreshDialog({super.key, required this.onConfirm});

  @override
  State<AutoRefreshDialog> createState() => _AutoRefreshDialogState();
}

class _AutoRefreshDialogState extends State<AutoRefreshDialog> {
  final TextEditingController _intervalController =
      TextEditingController(text: '1');
  final TextEditingController _countController =
      TextEditingController(text: '0');
  String _unit = '秒'; // 默认时间单位

  @override
  void dispose() {
    _intervalController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF333333), // 深色背景
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '自动刷新',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // 刷新间隔行
            Row(
              children: [
                const Text('刷新间隔',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber, width: 2),
                    ),
                    child: TextField(
                      controller: _intervalController,
                      style: const TextStyle(color: Colors.black87),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 时间单位选择按钮
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF555555),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: PopupMenuButton<String>(
                    initialValue: _unit,
                    onSelected: (String value) {
                      setState(() {
                        _unit = value;
                      });
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                          value: '毫秒', child: Text('毫秒')),
                      const PopupMenuItem<String>(value: '秒', child: Text('秒')),
                      const PopupMenuItem<String>(
                          value: '分钟', child: Text('分钟')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: Text(
                          _unit,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 刷新次数行
            Row(
              children: [
                const Text('刷新次数',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: TextField(
                      controller: _countController,
                      style: const TextStyle(color: Colors.black87),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 80, top: 4),
              child: Text(
                '请输入刷新次数，0为无限次',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),

            // 底部按钮行
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('取消',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
                Container(width: 1, height: 20, color: Colors.grey),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      final interval =
                          int.tryParse(_intervalController.text) ?? 1;
                      final count = int.tryParse(_countController.text) ?? 0;

                      // 根据所选单位转换为秒数，并保证最小刷新间隔为 1 秒
                      int intervalSeconds = interval;
                      if (_unit == '毫秒') {
                        intervalSeconds = (interval / 1000).round();
                      } else if (_unit == '分钟') {
                        intervalSeconds = interval * 60;
                      }
                      if (intervalSeconds < 1) {
                        intervalSeconds = 1;
                      }

                      widget.onConfirm(intervalSeconds, count);
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('确定',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
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

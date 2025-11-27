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
  String _unit = '秒'; // Default unit

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF333333), // Dark background
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

            // Interval Row
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
                // Unit Button
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
                const SizedBox(width: 4),
                // Help Button (?)
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF555555),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text('?', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Count Row
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

            // Buttons
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

                      // Convert to seconds for the callback as per current BrowserTab implementation
                      // If BrowserTab only supports seconds, we might lose precision for ms.
                      // But for now, let's just pass the raw interval and handle unit conversion here if possible
                      // or assume the callback handles it.
                      // Since I defined startAutoRefresh(int intervalSeconds, int count), I should convert to seconds.
                      // If unit is ms, intervalSeconds might be 0.

                      // Let's modify the callback to accept Duration instead?
                      // Or just convert to seconds (rounding up/down?)

                      int intervalSeconds = interval;
                      if (_unit == '毫秒') {
                        intervalSeconds = (interval / 1000).round();
                        if (intervalSeconds < 1) {
                          intervalSeconds = 1; // Minimum 1s for now
                        }
                      } else if (_unit == '分钟') {
                        intervalSeconds = interval * 60;
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

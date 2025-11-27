import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';

class BrowserSettingsDialog extends StatelessWidget {
  const BrowserSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '浏览器设置',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('浏览器标识 (UA)'),
            const SizedBox(height: 12),
            Consumer<BrowserProvider>(
              builder: (context, provider, child) {
                return Column(
                  children: [
                    _buildRadioItem(
                      context,
                      '手机 (Mobile)',
                      'Mobile',
                      provider.userAgent,
                      (val) => provider.setUserAgent(val!),
                    ),
                    _buildRadioItem(
                      context,
                      '平板 (Tablet)',
                      'Tablet',
                      provider.userAgent,
                      (val) => provider.setUserAgent(val!),
                    ),
                    _buildRadioItem(
                      context,
                      '电脑 (Desktop)',
                      'Desktop',
                      provider.userAgent,
                      (val) => provider.setUserAgent(val!),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            _buildSectionTitle('显示设置'),
            const SizedBox(height: 12),
            Consumer<BrowserProvider>(
              builder: (context, provider, child) {
                return SwitchListTile(
                  title: const Text('夜间模式',
                      style: TextStyle(color: Colors.black87)),
                  value: provider.isDarkMode,
                  onChanged: (value) => provider.toggleDarkMode(value),
                  activeColor: Colors.blue,
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildRadioItem(BuildContext context, String label, String value,
      String groupValue, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(
      title: Text(label, style: const TextStyle(color: Colors.black87)),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeColor: Colors.blue,
      dense: true,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';

class BrowserSettingsDialog extends StatelessWidget {
  const BrowserSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        context.select<BrowserProvider, bool>((p) => p.isDarkMode);
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final dividerColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8, // 最大高度为屏幕的 80%
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '浏览器设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('浏览器标识 (UA)', textColor),
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
                          textColor,
                          (val) => provider.setUserAgent(val!),
                        ),
                        _buildRadioItem(
                          context,
                          '平板 (Tablet)',
                          'Tablet',
                          provider.userAgent,
                          textColor,
                          (val) => provider.setUserAgent(val!),
                        ),
                        _buildRadioItem(
                          context,
                          '电脑 (Desktop)',
                          'Desktop',
                          provider.userAgent,
                          textColor,
                          (val) => provider.setUserAgent(val!),
                        ),
                      ],
                    );
                  },
                ),
                Divider(height: 32, color: dividerColor),
                _buildSectionTitle('显示设置', textColor),
                const SizedBox(height: 12),
                Consumer<BrowserProvider>(
                  builder: (context, provider, child) {
                    return Column(
                      children: [
                        SwitchListTile(
                          title: Text('夜间模式',
                              style: TextStyle(color: textColor)),
                          value: provider.isDarkMode,
                          onChanged: (value) => provider.toggleDarkMode(value),
                          activeColor: Colors.blue,
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          title: Text('屏幕常亮',
                              style: TextStyle(color: textColor)),
                          value: provider.keepScreenOn,
                          onChanged: (value) =>
                              provider.toggleKeepScreenOn(value),
                          activeColor: Colors.blue,
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          title: Text('广告与浮窗拦截',
                              style: TextStyle(color: textColor)),
                          subtitle: Text('屏蔽常见广告弹窗与全屏遮罩',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                          value: provider.isAdBlockEnabled,
                          onChanged: (value) => provider.toggleAdBlock(value),
                          activeColor: Colors.blue,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    );
                  },
                ),
                Divider(height: 32, color: dividerColor),
                _buildSectionTitle('搜索引擎', textColor),
                const SizedBox(height: 12),
                Consumer<BrowserProvider>(
                  builder: (context, provider, child) {
                    return Column(
                      children: [
                        _buildRadioItem(
                          context,
                          '百度 (Baidu)',
                          'Baidu',
                          provider.searchEngine,
                          textColor,
                          (val) => provider.setSearchEngine(val!),
                        ),
                        _buildRadioItem(
                          context,
                          '必应 (Bing)',
                          'Bing',
                          provider.searchEngine,
                          textColor,
                          (val) => provider.setSearchEngine(val!),
                        ),
                        _buildRadioItem(
                          context,
                          '谷歌 (Google)',
                          'Google',
                          provider.searchEngine,
                          textColor,
                          (val) => provider.setSearchEngine(val!),
                        ),
                      ],
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
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
    );
  }

  Widget _buildRadioItem(BuildContext context, String label, String value,
      String groupValue, Color textColor, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(
      title: Text(label, style: TextStyle(color: textColor)),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeColor: Colors.blue,
      dense: true,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';
import 'privacy_policy_dialog.dart';

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
                Divider(height: 32, color: dividerColor),
                _buildSectionTitle('数据与历史', textColor),
                const SizedBox(height: 8),
                Consumer<BrowserProvider>(
                  builder: (context, provider, child) {
                    final days = provider.maxHistoryDays;
                    final currentText = days == 0 ? '永久' : '$days天';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '最大历史记录保存天数',
                        style: TextStyle(color: textColor, fontSize: 15),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '当前:$currentText',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white60 : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: isDarkMode ? Colors.white54 : Colors.grey,
                          ),
                        ],
                      ),
                      onTap: () => _showHistoryDaysDialog(
                        context,
                        provider,
                        isDarkMode,
                        textColor,
                        backgroundColor,
                        dividerColor,
                      ),
                    );
                  },
                ),
                Divider(height: 32, color: dividerColor),
                _buildSectionTitle('合规与法律条款', textColor),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined, color: Colors.blue, size: 20),
                  title: Text('隐私政策 (Privacy Policy)',
                      style: TextStyle(color: textColor, fontSize: 15)),
                  trailing: Icon(Icons.chevron_right, size: 18, color: isDarkMode ? Colors.white54 : Colors.grey),
                  onTap: () => PrivacyPolicyDialog.show(context, initialTabIndex: 0),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined, color: Colors.blue, size: 20),
                  title: Text('用户服务协议 (Terms of Service)',
                      style: TextStyle(color: textColor, fontSize: 15)),
                  trailing: Icon(Icons.chevron_right, size: 18, color: isDarkMode ? Colors.white54 : Colors.grey),
                  onTap: () => PrivacyPolicyDialog.show(context, initialTabIndex: 1),
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

  /// 弹出最大历史记录保存天数选择框
  void _showHistoryDaysDialog(
    BuildContext context,
    BrowserProvider provider,
    bool isDarkMode,
    Color textColor,
    Color backgroundColor,
    Color dividerColor,
  ) {
    final options = [
      {'label': '1天', 'value': 1},
      {'label': '4天', 'value': 4},
      {'label': '7天', 'value': 7},
      {'label': '15天', 'value': 15},
      {'label': '30天', 'value': 30},
      {'label': '永久保存', 'value': 0},
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                child: Text(
                  '最大历史记录保存天数',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: dividerColor),
              ...options.map((option) {
                final isSelected = provider.maxHistoryDays == option['value'];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        provider.setMaxHistoryDays(option['value'] as int);
                        Navigator.pop(dialogContext);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 14.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              option['label'] as String,
                              style: TextStyle(
                                fontSize: 16,
                                color: isSelected
                                    ? textColor
                                    : (isDarkMode
                                        ? Colors.white60
                                        : Colors.black54),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check,
                                color: Colors.blue,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                  ],
                );
              }),
            ],
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

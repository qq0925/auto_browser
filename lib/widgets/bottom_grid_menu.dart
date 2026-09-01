import 'package:flutter/material.dart';

class BottomGridMenu extends StatelessWidget {
  final VoidCallback onBookmarksHistory;
  final VoidCallback onAutoRefresh;
  final VoidCallback onRecordScript;
  final VoidCallback onCookieManager;
  final VoidCallback onSettings;
  final bool isAutoRefreshActive;
  final bool isExecuting;

  const BottomGridMenu({
    super.key,
    required this.onBookmarksHistory,
    required this.onAutoRefresh,
    required this.onRecordScript,
    required this.onCookieManager,
    required this.onSettings,
    this.isAutoRefreshActive = false,
    this.isExecuting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF333333),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _buildMenuItem(
                    Icons.bookmarks_outlined, '书签/历史', onBookmarksHistory),
                _buildMenuItem(
                  isAutoRefreshActive
                      ? Icons.cancel_presentation
                      : Icons.autorenew,
                  isAutoRefreshActive ? '取消刷新' : '自动刷新',
                  onAutoRefresh,
                ),
                _buildMenuItem(
                  Icons.fiber_manual_record_outlined,
                  '录制脚本',
                  isExecuting ? null : onRecordScript,
                  color: isExecuting ? Colors.grey : Colors.white,
                ),
                _buildMenuItem(
                    Icons.account_circle_outlined, '会话账号', onCookieManager),
                _buildMenuItem(Icons.settings_outlined, '设置', onSettings),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, VoidCallback? onTap,
      {Color color = Colors.white}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

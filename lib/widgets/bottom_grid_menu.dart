import 'package:flutter/material.dart';

/// 底部网格更多功能菜单 (3x2 经典网格设计)
class BottomGridMenu extends StatelessWidget {
  final VoidCallback onBookmarksHistory;
  final VoidCallback onAutoRefresh;
  final VoidCallback onRecordScript;
  final VoidCallback onCookieManager;
  final VoidCallback onDownloads;
  final VoidCallback onSettings;
  final bool isAutoRefreshActive;
  final bool isExecuting;
  final int activeDownloadCount;

  const BottomGridMenu({
    super.key,
    required this.onBookmarksHistory,
    required this.onAutoRefresh,
    required this.onRecordScript,
    required this.onCookieManager,
    required this.onDownloads,
    required this.onSettings,
    this.isAutoRefreshActive = false,
    this.isExecuting = false,
    this.activeDownloadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF2B2B2B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部小拖拽指示条
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.15,
              children: [
                _buildMenuItem(
                  Icons.bookmarks_outlined,
                  '书签/历史',
                  onBookmarksHistory,
                ),
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
                  Icons.account_circle_outlined,
                  '会话账号',
                  onCookieManager,
                ),
                _buildMenuItem(
                  Icons.download_rounded,
                  '下载管理',
                  onDownloads,
                  badgeCount: activeDownloadCount,
                ),
                _buildMenuItem(
                  Icons.settings_outlined,
                  '设置',
                  onSettings,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color color = Colors.white,
    int badgeCount = 0,
  }) {
    return Material(
      color: Colors.white.withAlpha(15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            // 角标徽章
            if (badgeCount > 0)
              Positioned(
                top: 10,
                right: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

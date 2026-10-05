import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';

/// 隐私政策与用户服务协议合规对话框（符合 Apple App Store Guideline 5.1.1 规范）
class PrivacyPolicyDialog extends StatefulWidget {
  final int initialTabIndex; // 0: 隐私政策, 1: 用户协议

  const PrivacyPolicyDialog({
    super.key,
    this.initialTabIndex = 0,
  });

  static void show(BuildContext context, {int initialTabIndex = 0}) {
    showDialog(
      context: context,
      builder: (context) => PrivacyPolicyDialog(initialTabIndex: initialTabIndex),
    );
  }

  @override
  State<PrivacyPolicyDialog> createState() => _PrivacyPolicyDialogState();
}

class _PrivacyPolicyDialogState extends State<PrivacyPolicyDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        context.select<BrowserProvider, bool>((p) => p.isDarkMode);
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDarkMode ? Colors.white70 : const Color(0xFF334155);
    final cardBg = isDarkMode ? const Color(0xFF282828) : const Color(0xFFF8FAFC);
    final dividerColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部与 Tab
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.blue,
                      labelColor: Colors.blue,
                      unselectedLabelColor:
                          isDarkMode ? Colors.white60 : Colors.black54,
                      labelStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: const [
                        Tab(text: '隐私政策'),
                        Tab(text: '用户协议'),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textColor),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),

            // 内容区
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPrivacyContent(
                      context, textColor, subTextColor, cardBg, isDarkMode),
                  _buildTermsContent(
                      context, textColor, subTextColor, cardBg, isDarkMode),
                ],
              ),
            ),

            Divider(height: 1, color: dividerColor),

            // 底部操作栏
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '我已了解',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyContent(BuildContext context, Color textColor,
      Color subTextColor, Color cardBg, bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.security, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '核心承诺：Auok 浏览器坚持「本地沙盒存储」原则。您的全部 Cookie 存档、书签、历史记录及自动化脚本均仅保存在本设备沙盒内，本 App 不搭建任何外部用户数据收集服务器，绝不向第三方上传或出售您的个人浏览隐私数据。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDarkMode ? Colors.blue.shade200 : Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildItem(
            '1. 我们如何管理与使用数据',
            '• 本地浏览数据：历史记录、书签收藏、多标签页状态全部保存在本地，用户可随时在设置中一键清理。\n'
            '• Cookie 管理：提供本地多账号会话隔离存档，数据仅存储于本机应用沙盒内，不上传云端。\n'
            '• 自动化脚本：用户录制与编写的 .zds / .json 脚本完全归用户所有，仅在本机沙盒中存储。',
            textColor,
            subTextColor,
          ),
          _buildItem(
            '2. 系统权限申请与目的',
            '• 网络权限：通过系统原生 WebKit 框架访问公开互联网。\n'
            '• 相册权限：仅在用户主动点击“保存网页截图”或“保存图片到相册”时，用于向系统相册写入图片。\n'
            '• 文件权限：仅在用户主动导入或导出本地脚本时使用。',
            textColor,
            subTextColor,
          ),
          _buildItem(
            '3. 第三方 Web 内容与 WebKit 容器说明',
            '本 App 基于系统推荐的官方 WebKit (WKWebView) 引擎。用户访问的外部网站遵从各网站自身的隐私协议，本 App 不会注入恶意追踪代码，不会篡改用户与第三方网站之间的通信流量。',
            textColor,
            subTextColor,
          ),
          _buildItem(
            '4. 未成年人保护与年龄分级',
            '本软件为开放式通用 Web 浏览与自动化测试工具，根据 Apple App Store 审核准则，年龄分级设定为 17+（包含未受限制的 Web 访问）。未成年人请在监护人指导下使用。',
            textColor,
            subTextColor,
          ),
        ],
      ),
    );
  }

  Widget _buildTermsContent(BuildContext context, Color textColor,
      Color subTextColor, Color cardBg, bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItem(
            '1. 协议的接受与工具定位',
            '欢迎使用 Auok 浏览器。本软件是一款面向普通用户及开发人员的生产力浏览器工具，提供通用网页浏览、自动化测试辅助及交互模拟能力。使用本软件即代表您同意本协议的全部条款。',
            textColor,
            subTextColor,
          ),
          _buildItem(
            '2. 合规与合规使用守则',
            '用户在编写、导入或执行自动化脚本时，须承诺遵守适用的国家法律法规，并尊重目标网站的服务条款与知识产权：\n'
            '• 不得利用脚本自动化功能实施恶意攻击、刷量、干扰公平竞争秩序或破坏第三方正常服务；\n'
            '• 不得用于传播违规违法或侵犯他人权益的信息；\n'
            '• 用户自行编写、导入并执行的任何脚本，其行为后果与法律责任均由使用者自行承担。',
            textColor,
            subTextColor,
          ),
          _buildItem(
            '3. 知识产权与免责声明',
            '• 本软件由点梦科技独立开发并享有完整知识产权。\n'
            '• 本软件作为中立通用的客户端测试工具，不对用户访问的第三方网络内容的真实性或合法性承担连带担保责任。',
            textColor,
            subTextColor,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(String title, String content, Color titleColor, Color contentColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: contentColor,
            ),
          ),
        ],
      ),
    );
  }
}

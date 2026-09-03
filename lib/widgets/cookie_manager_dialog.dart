import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/cookie_service.dart';

/// 现代化 Cookie 与多账号会话管理对话框
class CookieManagerDialog extends StatefulWidget {
  final String currentUrl;
  final VoidCallback? onReloadRequired;

  const CookieManagerDialog({
    super.key,
    required this.currentUrl,
    this.onReloadRequired,
  });

  @override
  State<CookieManagerDialog> createState() => _CookieManagerDialogState();
}

class _CookieManagerDialogState extends State<CookieManagerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Cookie> _currentCookies = [];
  List<Map<String, dynamic>> _savedProfiles = [];
  bool _isLoading = true;
  String _domain = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _extractDomain();
    _loadData();
  }

  void _extractDomain() {
    try {
      final uri = Uri.parse(widget.currentUrl);
      _domain = uri.host;
    } catch (_) {
      _domain = '';
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cookies = await CookieService.getCookies(widget.currentUrl);
    final profiles = await CookieService.getSavedProfiles(domain: _domain);
    if (mounted) {
      setState(() {
        _currentCookies = cookies;
        _savedProfiles = profiles;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSaveProfileDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为账号存档'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入账号别名 (如：主账号 / 测试小号)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                await CookieService.saveProfile(
                  profileName: name,
                  domain: _domain,
                  cookies: _currentCookies,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已成功保存账号存档: $name')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _exportCookies() {
    if (_currentCookies.isEmpty) return;
    final list = _currentCookies.map((c) => {
          'name': c.name,
          'value': c.value,
          'domain': c.domain,
          'path': c.path,
        }).toList();
    final jsonStr = jsonEncode(list);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cookie JSON 已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        constraints: const BoxConstraints(maxWidth: 540),
        height: 520,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 头部
            Row(
              children: [
                const Icon(Icons.account_circle, color: Colors.blue, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '会话与 Cookie 管理',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _domain.isNotEmpty ? '站点: $_domain' : widget.currentUrl,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tab 栏
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: '当前 Cookie (${_currentCookies.length})'),
                Tab(text: '多账号存档 (${_savedProfiles.length})'),
              ],
            ),
            const SizedBox(height: 8),

            // 内容区
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCurrentCookiesTab(isDark),
                        _buildProfilesTab(isDark),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCookiesTab(bool isDark) {
    if (_currentCookies.isEmpty) {
      return const Center(
        child: Text('当前站点暂无 Cookie 数据', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _currentCookies.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final cookie = _currentCookies[index];
              return ListTile(
                dense: true,
                title: Text(
                  cookie.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  cookie.value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: '${cookie.name}=${cookie.value}'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已复制: ${cookie.name}')),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.save, size: 15),
              label: const Text('存为新账号', style: TextStyle(fontSize: 12)),
              onPressed: _showSaveProfileDialog,
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 15),
              label: const Text('导出 JSON', style: TextStyle(fontSize: 12)),
              onPressed: _exportCookies,
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('清理站点', style: TextStyle(fontSize: 12)),
              onPressed: () async {
                await CookieService.clearCookiesForUrl(widget.currentUrl);
                await _loadData();
                widget.onReloadRequired?.call();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除当前站点 Cookie 并刷新')),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfilesTab(bool isDark) {
    if (_savedProfiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('暂无已保存的账号存档', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _showSaveProfileDialog,
              child: const Text('保存当前 Cookie 为账号'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _savedProfiles.length,
      itemBuilder: (context, index) {
        final profile = _savedProfiles[index];
        final name = profile['profileName'] as String;
        final createdAt = profile['createdAt'] as String? ?? '';
        final cookies = profile['cookies'] as List? ?? [];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                name.isNotEmpty ? name.substring(0, 1) : 'U',
                style: const TextStyle(
                    color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Cookie: ${cookies.length} 项 | $createdAt',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '切换到此账号',
                  icon: const Icon(Icons.login, color: Colors.green),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    await CookieService.applyProfile(
                      profileName: name,
                      urlString: widget.currentUrl,
                    );
                    widget.onReloadRequired?.call();
                    if (mounted) {
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text('已成功切换到账号: $name 并重新加载')),
                      );
                    }
                  },
                ),
                IconButton(
                  tooltip: '删除此存档',
                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await CookieService.deleteProfile(name);
                    _loadData();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

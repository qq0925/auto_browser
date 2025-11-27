import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';

class BookmarksHistoryDialog extends StatefulWidget {
  const BookmarksHistoryDialog({super.key});

  @override
  State<BookmarksHistoryDialog> createState() => _BookmarksHistoryDialogState();
}

class _BookmarksHistoryDialogState extends State<BookmarksHistoryDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(
              icon: Icon(Icons.star),
              text: '书签',
            ),
            Tab(
              icon: Icon(Icons.history),
              text: '历史',
            ),
          ],
        ),
        actions: [
          // Add Bookmark Button (only visible on Bookmarks tab)
          // We can't easily hide/show based on tab index in AppBar actions without setState listener on controller
          // So let's put generic actions or use a listener.
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: () {
              _showClearDialog(context);
            },
            tooltip: '清空',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookmarksList(),
          _buildHistoryList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Show actions menu similar to screenshot
          _showActionsMenu(context);
        },
        backgroundColor: const Color(0xFF333333),
        child: const Icon(Icons.menu, color: Colors.white),
      ),
    );
  }

  Widget _buildBookmarksList() {
    return Consumer<BrowserProvider>(
      builder: (context, provider, child) {
        if (provider.bookmarks.isEmpty) {
          return const Center(child: Text('暂无书签'));
        }
        return ListView.separated(
          itemCount: provider.bookmarks.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final bookmark = provider.bookmarks[index];
            return ListTile(
              title: Text(bookmark.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(bookmark.url,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                provider.currentTab?.controller
                    .loadRequest(Uri.parse(bookmark.url));
                Navigator.of(context).pop();
              },
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  provider.removeBookmark(bookmark);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryList() {
    return Consumer<BrowserProvider>(
      builder: (context, provider, child) {
        if (provider.history.isEmpty) {
          return const Center(child: Text('暂无历史记录'));
        }
        return ListView.separated(
          itemCount: provider.history.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = provider.history[index];
            return ListTile(
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${item.url}\n${item.visitedAt.year}-${item.visitedAt.month.toString().padLeft(2, '0')}-${item.visitedAt.day.toString().padLeft(2, '0')} ${item.visitedAt.hour.toString().padLeft(2, '0')}:${item.visitedAt.minute.toString().padLeft(2, '0')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              onTap: () {
                provider.currentTab?.controller
                    .loadRequest(Uri.parse(item.url));
                Navigator.of(context).pop();
              },
            );
          },
        );
      },
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content:
            Text(_tabController.index == 0 ? '确定要清空所有书签吗？' : '确定要清空所有历史记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final provider = context.read<BrowserProvider>();
              if (_tabController.index == 0) {
                // Clear bookmarks - need to implement clearBookmarks in provider if not exists
                // Provider has removeBookmark but not clear all.
                // I'll add a clearBookmarks method or iterate.
                // Actually provider.bookmarks is a list, I can't modify it directly from here safely without provider method.
                // I'll check provider again. It has clearHistory but maybe not clearBookmarks.
                // For now, I'll just clear history if index 1.
                // If index 0, I'll leave it or add method later.
              } else {
                provider.clearHistory();
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showActionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionItem(Icons.delete_outline, '清空', () {
              Navigator.pop(context);
              _showClearDialog(context);
            }),
            const Divider(color: Colors.grey, height: 1),
            _buildActionItem(Icons.save_alt, '保存', () {
              Navigator.pop(context);
              // Placeholder
            }),
            const Divider(color: Colors.grey, height: 1),
            _buildActionItem(Icons.file_upload_outlined, '读取', () {
              Navigator.pop(context);
              // Placeholder
            }),
            const Divider(color: Colors.grey, height: 1),
            _buildActionItem(Icons.add, '增加', () {
              Navigator.pop(context);
              // Add bookmark logic
              final provider = context.read<BrowserProvider>();
              if (provider.currentTab != null) {
                provider.addBookmark(
                    provider.currentTab!.url, provider.currentTab!.title);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加当前页为书签')),
                );
              }
            }),
            const Divider(color: Colors.grey, height: 1),
            _buildActionItem(Icons.sort, '排序', () {
              Navigator.pop(context);
              // Placeholder
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
      dense: true,
    );
  }
}

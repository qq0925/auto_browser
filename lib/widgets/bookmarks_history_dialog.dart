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
    final isDarkMode =
        context.select<BrowserProvider, bool>((p) => p.isDarkMode);
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
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
        actions: [],
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
            final textColor =
                provider.isDarkMode ? Colors.white : Colors.black87;
            final subtitleColor =
                provider.isDarkMode ? Colors.white70 : Colors.black54;

            return ListTile(
              title: Text(bookmark.title,
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(bookmark.url,
                  style: TextStyle(color: subtitleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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
            final textColor =
                provider.isDarkMode ? Colors.white : Colors.black87;
            final subtitleColor =
                provider.isDarkMode ? Colors.white70 : Colors.black54;

            return ListTile(
              title: Text(item.title,
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.url,
                      style: TextStyle(color: subtitleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${item.visitedAt.year}-${item.visitedAt.month.toString().padLeft(2, '0')}-${item.visitedAt.day.toString().padLeft(2, '0')} ${item.visitedAt.hour.toString().padLeft(2, '0')}:${item.visitedAt.minute.toString().padLeft(2, '0')}:${item.visitedAt.second.toString().padLeft(2, '0')}',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                    maxLines: 1,
                  ),
                ],
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
                provider.clearBookmarks();
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
    final isBookmarks = _tabController.index == 0;
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
            if (isBookmarks) ...[
              _buildActionItem(Icons.add, '增加书签', () {
                Navigator.pop(context);
                _showAddBookmarkDialog(context);
              }),
              const Divider(color: Colors.grey, height: 1),
              _buildActionItem(Icons.sort, '排序', () {
                Navigator.pop(context);
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
                        _buildActionItem(null, '按地址排序', () {
                          context.read<BrowserProvider>().sortBookmarks('url');
                          Navigator.pop(context);
                        }),
                        const Divider(color: Colors.grey, height: 1),
                        _buildActionItem(null, '按名称排序', () {
                          context.read<BrowserProvider>().sortBookmarks('name');
                          Navigator.pop(context);
                        }),
                        const Divider(color: Colors.grey, height: 1),
                        _buildActionItem(null, '按时间排序', () {
                          context.read<BrowserProvider>().sortBookmarks('time');
                          Navigator.pop(context);
                        }),
                        const Divider(color: Colors.grey, height: 1),
                        _buildActionItem(null, '取消', () {
                          Navigator.pop(context);
                        }),
                      ],
                    ),
                  ),
                );
              }),
              const Divider(color: Colors.grey, height: 1),
            ],
            _buildActionItem(Icons.delete_outline, '清空', () {
              Navigator.pop(context);
              _showClearDialog(context);
            }),
          ],
        ),
      ),
    );
  }

  void _showAddBookmarkDialog(BuildContext context) {
    final provider = context.read<BrowserProvider>();
    String initialTitle = provider.currentTab?.title ?? '';
    String initialUrl = provider.currentTab?.url ?? '';

    if (initialUrl == 'about:blank' || initialUrl.endsWith('welcome.html')) {
      initialTitle = 'Auok浏览器';
      initialUrl = 'about:blank';
    }

    final titleController = TextEditingController(text: initialTitle);
    final urlController = TextEditingController(text: initialUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Row(
          children: [
            Icon(Icons.star, color: Colors.white),
            SizedBox(width: 8),
            Text('增加书签', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '名称:',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '地址:',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  urlController.text.isNotEmpty) {
                provider.addBookmark(urlController.text, titleController.text);
              }
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData? icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: icon != null ? Icon(icon, color: Colors.white) : null,
      title: Text(
        label,
        style: const TextStyle(color: Colors.white),
        textAlign: icon == null ? TextAlign.center : TextAlign.start,
      ),
      onTap: onTap,
      dense: true,
    );
  }
}

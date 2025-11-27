import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../providers/browser_provider.dart';
import '../models/browser_data.dart';

class MenuPage extends StatelessWidget {
  final BrowserProvider browserProvider;

  const MenuPage({super.key, required this.browserProvider});

  @override
  Widget build(BuildContext context) {
    final isDark = browserProvider.isDarkMode;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          '菜单',
          style: TextStyle(
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
      ),
      child: Material(
        color: isDark ? CupertinoColors.black : CupertinoColors.white,
        child: SafeArea(
          child: ListView(
            children: [
              _buildSection(context, '书签', browserProvider.bookmarks, isDark,
                  isBookmark: true),
              const Divider(),
              _buildSection(context, '历史', browserProvider.history, isDark,
                  isBookmark: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List items, bool isDark,
      {required bool isBookmark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '$title (${items.length})',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '暂无$title',
              style: TextStyle(
                color: isDark
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.systemGrey2,
              ),
            ),
          )
        else
          ...items.map((item) {
            final title = isBookmark
                ? (item as Bookmark).title
                : (item as HistoryItem).title;
            final url =
                isBookmark ? (item as Bookmark).url : (item as HistoryItem).url;
            final time = isBookmark
                ? (item as Bookmark).createdAt
                : (item as HistoryItem).visitedAt;

            return ListTile(
              title: Text(
                title,
                style: TextStyle(
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
              subtitle: Text(
                '$url\n${_formatTime(time)}',
                style: TextStyle(
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2,
                ),
              ),
              onTap: () {
                // Navigate to URL
                Navigator.pop(context, url);
              },
              trailing: isBookmark
                  ? IconButton(
                      icon: Icon(
                        CupertinoIcons.trash,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                      onPressed: () {
                        browserProvider.removeBookmark(item as Bookmark);
                      },
                    )
                  : null,
            );
          }),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}

class Bookmark {
  final String title;
  final String url;
  final DateTime createdAt;

  Bookmark({
    required this.title,
    required this.url,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Bookmark &&
        other.url == url &&
        other.title == title &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(url, title, createdAt);
}

class HistoryItem {
  final String title;
  final String url;
  final DateTime visitedAt;

  HistoryItem({
    required this.title,
    required this.url,
    required this.visitedAt,
  });
}

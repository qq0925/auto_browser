import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/browser_tab.dart';
import '../models/browser_data.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class BrowserProvider extends ChangeNotifier {
  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final List<Bookmark> _bookmarks = [];
  final List<HistoryItem> _history = [];
  bool _isDarkMode = false;
  bool _keepScreenOn = false;
  bool _autoLeaveMode = false;
  bool _isScriptPanelExpanded = false; // Default to false (collapsed)
  String _searchEngine = 'Baidu'; // Default to Baidu
  String? _nightCssContent;

  // Need a navigator key to access context for AssetBundle if context not available
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  List<BrowserTab> get tabs => _tabs;
  int get currentIndex => _currentIndex;
  List<Bookmark> get bookmarks => _bookmarks;
  List<HistoryItem> get history => _history;
  bool get isDarkMode => _isDarkMode;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoLeaveMode => _autoLeaveMode;
  bool get isScriptPanelExpanded => _isScriptPanelExpanded;
  String get searchEngine => _searchEngine;

  BrowserTab? get currentTab =>
      _tabs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _tabs.length
          ? _tabs[_currentIndex]
          : null;

  BrowserProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadBookmarksAndHistory();
    await _restoreTabsState();
    try {
      if (navigatorKey.currentContext != null) {
        _nightCssContent =
            await DefaultAssetBundle.of(navigatorKey.currentContext!)
                .loadString('assets/night.css');
      }
    } catch (e) {
      debugPrint('Error loading night.css: $e');
    }
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _tabs.length) {
      _currentIndex = index;
      notifyListeners();
      _saveTabsState();
    }
  }

  void toggleDarkMode(bool value) {
    _isDarkMode = value;
    notifyListeners();
    _saveTabsState();

    // Apply to all tabs
    for (var tab in _tabs) {
      tab.controller.setBackgroundColor(value ? Colors.black : Colors.white);
      if (value) {
        _injectNightMode(tab.controller);
      } else {
        tab.controller.runJavaScript(
            "document.getElementById('auok-night-mode')?.remove();");
      }
    }
  }

  void _injectNightMode(WebViewController controller) {
    if (_nightCssContent != null) {
      final js = """
        (function() {
          if (document.getElementById('auok-night-mode')) return;
          var style = document.createElement('style');
          style.id = 'auok-night-mode';
          style.innerHTML = `${_nightCssContent!.replaceAll('\n', ' ')}`;
          document.head.appendChild(style);
        })();
      """;
      controller.runJavaScript(js);
    }
  }

  void injectNightModeIfEnabled(WebViewController controller) {
    if (_isDarkMode) {
      _injectNightMode(controller);
    }
  }

  void toggleKeepScreenOn(bool value) {
    _keepScreenOn = value;
    if (value) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    notifyListeners();
    _saveTabsState();
  }

  void toggleAutoLeaveMode(bool value) {
    _autoLeaveMode = value;
    notifyListeners();
  }

  Future<void> addTab(
      {String? initialUrl,
      String? initialTitle,
      String? scriptFilePath,
      required WebViewController controller}) async {
    final tab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      controller: controller,
      title: initialTitle ?? 'New Tab',
      url: initialUrl ?? 'about:blank',
    );

    // Set script file path if provided
    if (scriptFilePath != null) {
      tab.scriptFilePath = scriptFilePath;
    }

    _tabs.add(tab);
    _currentIndex = _tabs.length - 1;
    notifyListeners();
    _saveTabsState();
  }

  bool canCloseTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      return !_tabs[index].isExecutingScript;
    }
    return false;
  }

  void removeTab(int index) {
    if (_tabs.length > 1) {
      final tab = _tabs[index];

      // Prevent closing if executing script
      if (tab.isExecutingScript) {
        return; // Caller should show error message
      }

      tab.controller.clearCache();
      tab.controller.clearLocalStorage();

      _tabs.removeAt(index);
      if (_currentIndex >= index) {
        _currentIndex = _currentIndex > 0 ? _currentIndex - 1 : 0;
      }
      notifyListeners();
      _saveTabsState();
    } else if (_tabs.length == 1) {
      // Last tab - check if executing, will be handled by caller
      final tab = _tabs[0];
      if (tab.isExecutingScript) {
        return; // Prevent removal
      }
      // Allow removal - caller will create new default tab
      tab.controller.clearCache();
      tab.controller.clearLocalStorage();
      _tabs.removeAt(index);
      notifyListeners();
      _saveTabsState();
    }
  }

  void updateTabInfo(int index, String url, String title) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].url = url;
      _tabs[index].title = title;
      notifyListeners();
      _saveTabsState();
    }
  }

  void updateTabProgress(double progress) {
    if (_currentIndex >= 0 && _currentIndex < _tabs.length) {
      _tabs[_currentIndex].progress = progress;
      notifyListeners();
    }
  }

  void addToHistory(String url, String title) {
    if (url.startsWith('file:///') || url == 'about:blank') return;

    _history.insert(
        0,
        HistoryItem(
          title: title,
          url: url,
          visitedAt: DateTime.now(),
        ));
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void addBookmark(String url, String title) {
    _bookmarks.add(Bookmark(
      title: title,
      url: url,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void removeBookmark(Bookmark bookmark) {
    _bookmarks.remove(bookmark);
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void removeBookmarkByUrl(String url) {
    _bookmarks.removeWhere((bookmark) => bookmark.url == url);
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  bool isBookmarked(String url) {
    return _bookmarks.any((bookmark) => bookmark.url == url);
  }

  void toggleBookmark(String url, String title) {
    if (isBookmarked(url)) {
      removeBookmarkByUrl(url);
    } else {
      addBookmark(url, title);
    }
  }

  void sortBookmarks(String type) {
    if (type == 'url') {
      _bookmarks.sort((a, b) => a.url.compareTo(b.url));
    } else if (type == 'name') {
      _bookmarks.sort((a, b) => a.title.compareTo(b.title));
    } else if (type == 'time') {
      _bookmarks
          .sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Newest first
    }
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void toggleScriptPanel() {
    _isScriptPanelExpanded = !_isScriptPanelExpanded;
    notifyListeners();
    _saveTabsState();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void clearBookmarks() {
    _bookmarks.clear();
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  Future<void> _loadBookmarksAndHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarksJson = prefs.getStringList('bookmarks') ?? [];
      final historyJson = prefs.getStringList('history') ?? [];

      _bookmarks.clear();
      _bookmarks.addAll(bookmarksJson.map((json) {
        final data = jsonDecode(json);
        return Bookmark(
          title: data['title'],
          url: data['url'],
          createdAt: DateTime.parse(data['createdAt']),
        );
      }));

      _history.clear();
      _history.addAll(historyJson.map((json) {
        final data = jsonDecode(json);
        return HistoryItem(
          title: data['title'],
          url: data['url'],
          visitedAt: DateTime.parse(data['visitedAt']),
        );
      }));
      notifyListeners();
    } catch (e) {
      debugPrint('Load bookmarks and history error: $e');
    }
  }

  Future<void> _saveBookmarksAndHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'bookmarks',
          _bookmarks
              .map((bookmark) => jsonEncode({
                    'title': bookmark.title,
                    'url': bookmark.url,
                    'createdAt': bookmark.createdAt.toIso8601String(),
                  }))
              .toList());

      await prefs.setStringList(
          'history',
          _history
              .map((item) => jsonEncode({
                    'title': item.title,
                    'url': item.url,
                    'visitedAt': item.visitedAt.toIso8601String(),
                  }))
              .toList());
    } catch (e) {
      debugPrint('Save bookmarks and history error: $e');
    }
  }

  Future<void> _saveTabsState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tabsData = await Future.wait(_tabs.map((tab) async {
        // Note: We can't easily get current URL from controller here synchronously,
        // so we rely on the stored url in BrowserTab which should be updated via updateTabInfo
        return {
          'url': tab.url.startsWith('file:///') ? 'about:blank' : tab.url,
          'title': tab.title,
          'scriptFilePath': tab.scriptFilePath, // Save script file path
        };
      }));

      await prefs.setString(
          'last_tabs',
          jsonEncode({
            'tabs': tabsData,
            'currentIndex': _currentIndex,
            'isDarkMode': _isDarkMode,
            'keepScreenOn': _keepScreenOn,
            'isScriptPanelExpanded': _isScriptPanelExpanded,
            'searchEngine': _searchEngine,
          }));
    } catch (e) {
      debugPrint('Save tabs state error: $e');
    }
  }

  Future<void> _restoreTabsState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tabsJson = prefs.getString('last_tabs');

      if (tabsJson != null) {
        final data = jsonDecode(tabsJson);
        // We can't restore tabs fully here because we need to create WebViewControllers
        // which might need context or platform view initialization.
        // So we will just expose the data and let the UI/Main initialize the tabs.
        // However, for this Provider, we might need a way to signal "restore needed".

        _isDarkMode = data['isDarkMode'] ?? false;
        _keepScreenOn = data['keepScreenOn'] ?? false;
        _searchEngine = data['searchEngine'] ?? 'Baidu';
        // _isScriptPanelExpanded = data['isScriptPanelExpanded'] ?? true; // Do not restore state

        if (_keepScreenOn) {
          await WakelockPlus.enable();
        }

        // The actual tab creation will happen in the UI when it sees empty tabs or via a specific method
        // For now, we'll store the restored data in a temporary variable if needed,
        // or better yet, we just notify listeners that we have settings.
        // The tabs themselves need to be recreated with controllers.

        // Let's parse the tabs data and expose it so the UI can call addTab
        _restoredTabsData = List<Map<String, dynamic>>.from(data['tabs']);
        _restoredIndex = data['currentIndex'] as int;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Restore tabs state error: $e');
    }
  }

  // User Agent
  String _userAgent = 'Mobile'; // Default to Mobile
  String get userAgent => _userAgent;

  final Map<String, String> _uaMap = {
    'Mobile':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
    'Tablet':
        'Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
    'Desktop':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
  };

  void setUserAgent(String type) {
    if (_uaMap.containsKey(type)) {
      _userAgent = type;
      notifyListeners();
      _saveTabsState();
      // Apply to current tab if exists
      if (currentTab != null) {
        currentTab!.controller.setUserAgent(_uaMap[type]);
        currentTab!.controller.reload();
      }
    }
  }

  void setSearchEngine(String engine) {
    _searchEngine = engine;
    notifyListeners();
    _saveTabsState();
  }

  String get currentUserAgentString => _uaMap[_userAgent]!;

  List<Map<String, dynamic>>? _restoredTabsData;
  int? _restoredIndex;

  List<Map<String, dynamic>>? get restoredTabsData => _restoredTabsData;
  int? get restoredIndex => _restoredIndex;

  void clearRestoredData() {
    _restoredTabsData = null;
    _restoredIndex = null;
  }
}

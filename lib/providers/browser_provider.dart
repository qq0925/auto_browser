import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/browser_tab.dart';
import '../models/browser_data.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/welcome_manager.dart';

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

  // Filter welcome.html from visible history
  List<HistoryItem> get history =>
      _history.where((item) => !item.url.endsWith('welcome.html')).toList();

  bool get isDarkMode => _isDarkMode;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoLeaveMode => _autoLeaveMode;
  bool get isScriptPanelExpanded => _isScriptPanelExpanded;
  String get searchEngine => _searchEngine;
  String? get nightCssContent => _nightCssContent;

  BrowserTab? get currentTab =>
      _tabs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _tabs.length
          ? _tabs[_currentIndex]
          : null;

  BrowserProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadBookmarksAndHistory();
    // await _restoreTabsState(); // Removed restoration logic
    // Instead, just ensure settings are loaded or defaults set, and add a default tab
    await _loadSettings();
    await addTab(); // Always start with a new tab
    try {
      final String content = await rootBundle.loadString('assets/night.css');
      _nightCssContent = content;
    } catch (e) {
      debugPrint('Error loading night.css: $e');
    }

    // Apply restored dark mode to any existing tabs (handling race condition)
    if (_isDarkMode && _nightCssContent != null) {
      for (var tab in _tabs) {
        if (tab.controller != null && nightModeUserScript != null) {
          tab.controller!.addUserScript(userScript: nightModeUserScript!);
          _injectNightMode(tab.controller!);
        }
      }
    }

    // Start background welcome.html update (fire-and-forget)
    WelcomeManager.updateWelcomeInBackground();

    _isInitialized = true;
    notifyListeners();
  }

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  UserScript? _nightModeUserScript;

  String _getNightModeJs() {
    if (_nightCssContent == null) return '';
    // Escape the CSS content to be safe for JS string
    final css = _nightCssContent!.replaceAll('\n', '').replaceAll("'", "\\'");
    return """
      (function() {
        if (document.getElementById('auok-night-mode')) return;
        var style = document.createElement('style');
        style.id = 'auok-night-mode';
        style.innerHTML = '$css';
        document.head.appendChild(style);
      })();
    """;
  }

  UserScript? get nightModeUserScript {
    if (_nightCssContent == null) return null;
    _nightModeUserScript ??= UserScript(
      source: _getNightModeJs(),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
    return _nightModeUserScript;
  }

  void toggleDarkMode(bool value) {
    _isDarkMode = value;
    notifyListeners();
    _saveTabsState();

    // Apply to all tabs
    for (var tab in _tabs) {
      tab.controller?.setSettings(
          settings: InAppWebViewSettings(
        preferredContentMode: _getPreferredContentMode(userAgent),
      ));

      if (value) {
        if (tab.controller != null && nightModeUserScript != null) {
          // Add UserScript for future navigations
          tab.controller!.addUserScript(userScript: nightModeUserScript!);
          // Inject immediately for current page
          _injectNightMode(tab.controller!);
        }
      } else {
        if (tab.controller != null && nightModeUserScript != null) {
          // Remove UserScript
          tab.controller!.removeUserScript(userScript: nightModeUserScript!);
          // Remove style from current page
          tab.controller!.evaluateJavascript(
              source: "document.getElementById('auok-night-mode')?.remove();");
        }
      }
    }
  }

  void _injectNightMode(InAppWebViewController controller) {
    if (_nightCssContent != null) {
      controller.evaluateJavascript(source: _getNightModeJs());
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
    _saveTabsState();
  }

  Future<void> addTab({
    String initialUrl = 'about:blank',
    String? initialTitle,
    String? customName,
    String? customUserAgent,
  }) async {
    final tab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: initialUrl,
      title: initialTitle ?? 'New Tab',
      customName: customName,
      customUserAgent: customUserAgent,
    );
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

      InAppWebViewController.clearAllCache();
      // tab.controller.clearLocalStorage(); // InAppWebView handles this differently or globally

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
      InAppWebViewController.clearAllCache();
      // tab.controller.clearLocalStorage();
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

  void updateTabCustomSettings(
      int index, String? customName, String? customUserAgent) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].customName = customName;
      _tabs[index].customUserAgent = customUserAgent;
      notifyListeners();
      _saveTabsState();
    }
  }

  void updateTabNavigationState(int index, bool canGoBack, bool canGoForward) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].canGoBack = canGoBack;
      _tabs[index].canGoForward = canGoForward;
      notifyListeners();
    }
  }

  void updateTabProgress(double progress) {
    if (_currentIndex >= 0 && _currentIndex < _tabs.length) {
      _tabs[_currentIndex].progress = progress;
      notifyListeners();
    }
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _tabs.length) {
      _currentIndex = index;
      notifyListeners();
      _saveTabsState();
    }
  }

  void addToHistory(String url, String title) {
    // Allow welcome.html to be recorded, but exclude other file URLs and about:blank
    // We allow welcome.html so it's in the history list (for potential internal use)
    // but we filter it out in the 'history' getter so it's not shown in UI.
    if ((url.startsWith('file:///') && !url.endsWith('welcome.html')) ||
        url == 'about:blank') {
      return;
    }

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

  void updateHistoryTitle(String url, String title) {
    if (_history.isEmpty) return;

    // Check if the most recent item matches the URL
    if (_history.first.url == url) {
      final oldItem = _history.first;
      _history[0] = HistoryItem(
        title: title,
        url: oldItem.url,
        visitedAt: oldItem.visitedAt,
      );
      notifyListeners();
      _saveBookmarksAndHistory();
    }
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

      // Ensure we have valid data to save
      final tabsData = await Future.wait(_tabs.map((tab) async {
        String url = tab.url;
        // If url is file path (welcome page), save as about:blank to trigger welcome logic on restore
        if (url.startsWith('file:///')) {
          url = 'about:blank';
        }

        return {
          'url': url,
          'title': tab.title,
          'scriptFilePath': tab.scriptFilePath,
        };
      }));

      final dataToSave = {
        'tabs': tabsData,
        'currentIndex': _currentIndex,
        'isDarkMode': _isDarkMode,
        'keepScreenOn': _keepScreenOn,
        'isScriptPanelExpanded': _isScriptPanelExpanded,
        'searchEngine': _searchEngine,
        'userAgent': _userAgent, // Save UserAgent
        'autoLeaveMode': _autoLeaveMode,
      };

      await prefs.setString('last_tabs', jsonEncode(dataToSave));
    } catch (e) {
      debugPrint('Save tabs state error: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tabsJson = prefs.getString('last_tabs');

      if (tabsJson != null) {
        final data = jsonDecode(tabsJson);
        _isDarkMode = data['isDarkMode'] ?? false;
        _keepScreenOn = data['keepScreenOn'] ?? false;
        _autoLeaveMode = data['autoLeaveMode'] ?? false;
        _searchEngine = data['searchEngine'] ?? 'Baidu';
        _userAgent = data['userAgent'] ?? 'Mobile';

        if (_keepScreenOn) {
          await WakelockPlus.enable();
        }
      }
    } catch (e) {
      debugPrint('Load settings error: $e');
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
        if (currentTab != null && currentTab!.controller != null) {
          currentTab!.controller!.setSettings(
              settings: InAppWebViewSettings(
                  userAgent: _uaMap[type] ?? '',
                  preferredContentMode: _getPreferredContentMode(type)));
          currentTab!.controller!.reload();
        }
      }
    }
  }

  void setSearchEngine(String engine) {
    _searchEngine = engine;
    notifyListeners();
    _saveTabsState();
  }

  String get currentUserAgentString => _uaMap[_userAgent]!;

  UserPreferredContentMode _getPreferredContentMode(String userAgentType) {
    if (userAgentType == 'Desktop') {
      return UserPreferredContentMode.DESKTOP;
    }
    return UserPreferredContentMode.MOBILE;
  }
}

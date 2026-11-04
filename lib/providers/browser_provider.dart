import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/browser_tab.dart';
import '../models/browser_data.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/welcome_manager.dart';

class BrowserProvider extends ChangeNotifier {
  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final List<Bookmark> _bookmarks = [];
  final List<HistoryItem> _history = [];
  bool _isDarkMode = false;
  bool _keepScreenOn = false;
  bool _autoLeaveMode = false;
  bool _isScriptPanelExpanded = false; // 默认收起脚本面板
  String _searchEngine = 'Baidu'; // 默认使用百度搜索引擎
  String? _nightCssContent;
  int _maxHistoryDays = 4; // 最大历史记录保存天数，默认4天，0为永久保存

  // 夜间模式内置兜底高优先级 CSS
  static const String _fallbackNightCss = '''
    html, body {
      background-color: #121212 !important;
      color: #e0e0e0 !important;
    }
    div, p, span, a, li, ul, ol, table, tr, td, th, h1, h2, h3, h4, h5, h6 {
      background-color: transparent !important;
      color: inherit !important;
    }
    a { color: #bb86fc !important; }
    input, textarea, select, button {
      background-color: #333 !important;
      color: #fff !important;
      border-color: #555 !important;
    }
    img { opacity: 0.8 !important; }
  ''';

  // 全局导航 Key
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  List<BrowserTab> get tabs => _tabs;
  int get currentIndex => _currentIndex;
  List<Bookmark> get bookmarks => _bookmarks;

  // 过滤掉可见历史记录中的 welcome.html
  List<HistoryItem> get history =>
      _history.where((item) => !item.url.endsWith('welcome.html')).toList();

  bool get isDarkMode => _isDarkMode;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoLeaveMode => _autoLeaveMode;
  bool get isScriptPanelExpanded => _isScriptPanelExpanded;
  String get searchEngine => _searchEngine;
  String? get nightCssContent => _nightCssContent;
  int get maxHistoryDays => _maxHistoryDays;

  BrowserTab? get currentTab =>
      _tabs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _tabs.length
          ? _tabs[_currentIndex]
          : null;

  BrowserProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadBookmarksAndHistory();
    // 先加载配置和夜间模式样式，再创建初始标签页，避免竞态导致夜间模式未注入
    await _loadSettings();
    try {
      final String content = await rootBundle.loadString('assets/night.css');
      _nightCssContent = content;
      _nightModeUserScript = null; // 重置缓存以使用最新加载的 CSS 内容
    } catch (e) {
      debugPrint('Error loading night.css: $e');
    }

    await addTab(); // 始终以新标签页启动

    // 对已存在的标签页应用恢复的夜间模式
    if (_isDarkMode && nightModeUserScript != null) {
      for (var tab in _tabs) {
        if (tab.controller != null) {
          tab.controller!.addUserScript(userScript: nightModeUserScript!);
          _injectNightMode(tab.controller!);
        }
      }
    }

    // 后台静默更新 welcome.html
    WelcomeManager.updateWelcomeInBackground();

    _isInitialized = true;
    notifyListeners();
  }

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  UserScript? _nightModeUserScript;

  String _getNightModeJs() {
    final baseCss = (_nightCssContent != null && _nightCssContent!.isNotEmpty)
        ? _nightCssContent!
        : _fallbackNightCss;
    final fullCss =
        '$baseCss\nhtml, body { background-color: #121212 !important; }';

    // 使用 jsonEncode 生成合法的 JS 字符串字面量，防止 \r、\n、反斜杠或引号引发语法错误
    final safeCssJson = jsonEncode(fullCss);

    return '''
      (function() {
        // 1. 立即隐藏页面防止白屏闪烁
        if (!document.getElementById('auok-night-mode') && !document.getElementById('auok-night-hide')) {
          var hideStyle = document.createElement('style');
          hideStyle.id = 'auok-night-hide';
          hideStyle.textContent = 'html, body { visibility: hidden !important; background: #121212 !important; }';
          var earlyTarget = document.head || document.documentElement || document.body;
          if (earlyTarget) earlyTarget.appendChild(hideStyle);
        }
        
        // 2. 注入夜间模式 CSS
        if (document.getElementById('auok-night-mode')) {
          var hideEl = document.getElementById('auok-night-hide');
          if (hideEl) hideEl.remove();
          return;
        }
        var style = document.createElement('style');
        style.id = 'auok-night-mode';
        style.textContent = $safeCssJson;
        var target = document.head || document.documentElement || document.body;
        if (target) {
          target.appendChild(style);
          var hideEl = document.getElementById('auok-night-hide');
          if (hideEl) hideEl.remove();
        } else {
          setTimeout(function() {
            var targetRetry = document.head || document.documentElement || document.body;
            if (targetRetry && !document.getElementById('auok-night-mode')) {
              targetRetry.appendChild(style);
            }
            var hideEl = document.getElementById('auok-night-hide');
            if (hideEl) hideEl.remove();
          }, 50);
        }
        
        // 3. 样式应用后移除防闪烁遮罩以显示页面
        requestAnimationFrame(function() {
          var hideEl = document.getElementById('auok-night-hide');
          if (hideEl) hideEl.remove();
        });
      })();
    ''';
  }

  UserScript? get nightModeUserScript {
    _nightModeUserScript ??= UserScript(
      source: _getNightModeJs(),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
    return _nightModeUserScript;
  }

  Future<void> toggleDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    _saveTabsState();

    // 应用到所有标签页（先读取当前设置再修改，防止重置多窗口、下载拦截、UA等关键设置）
    for (var tab in _tabs) {
      final controller = tab.controller;
      if (controller == null) continue;

      try {
        final currentSettings =
            await controller.getSettings() ?? InAppWebViewSettings();
        currentSettings.preferredContentMode =
            _getPreferredContentMode(tab.customUserAgent ?? userAgent);
        await controller.setSettings(settings: currentSettings);
      } catch (_) {}

      if (value) {
        if (nightModeUserScript != null) {
          // 为后续导航添加 UserScript
          await controller.addUserScript(userScript: nightModeUserScript!);
          // 立即对当前页面注入夜间模式
          _injectNightMode(controller);
        }
      } else {
        if (nightModeUserScript != null) {
          // 移除 UserScript
          await controller.removeUserScript(userScript: nightModeUserScript!);
        }
        // 从当前页面移除夜间模式 style 标签与防闪烁标签
        await controller.evaluateJavascript(source: '''
          (function() {
            document.getElementById('auok-night-mode')?.remove();
            document.getElementById('auok-night-hide')?.remove();
          })();
        ''');
      }
    }
  }

  void injectNightMode(InAppWebViewController controller) {
    try {
      // 统一通过带 id (auok-night-mode) 的 style 标签注入夜间模式 CSS（含强制深色背景），
      // 避免在 Windows 上使用无法移除的 injectCSSCode 或永久内联背景色，确保关闭夜间模式时可干净移除
      controller.evaluateJavascript(source: _getNightModeJs());
    } catch (_) {}
  }

  void _injectNightMode(InAppWebViewController controller) {
    injectNightMode(controller);
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

  bool _isAdBlockEnabled = true;
  bool get isAdBlockEnabled => _isAdBlockEnabled;

  void toggleAdBlock(bool value) {
    _isAdBlockEnabled = value;
    notifyListeners();
    _saveTabsState();
  }

  bool _isDebugModeEnabled = false;
  bool get isDebugModeEnabled => _isDebugModeEnabled;

  void toggleDebugMode(bool value) {
    _isDebugModeEnabled = value;
    notifyListeners();
    _saveTabsState();
  }

  static int _tabIdCounter = 0;

  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return 'about:blank';
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file://') ||
        lower.startsWith('about:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:')) {
      return url;
    }
    return 'https://$url';
  }

  Future<void> addTab({
    String initialUrl = 'about:blank',
    String? initialTitle,
    String? customName,
    String? customUserAgent,
    bool switchToNewTab = true,
  }) async {
    _tabIdCounter++;
    final uniqueId = '${DateTime.now().millisecondsSinceEpoch}_$_tabIdCounter';
    final normalizedUrl = normalizeUrl(initialUrl);

    final tab = BrowserTab(
      id: uniqueId,
      url: normalizedUrl,
      title: initialTitle ??
          (normalizedUrl == 'about:blank' ? '新标签页' : '正在加载...'),
      customName: customName,
      customUserAgent: customUserAgent,
    );
    _tabs.add(tab);
    if (switchToNewTab) {
      _currentIndex = _tabs.length - 1;
    }
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
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];

    // 若标签页正在执行脚本，禁止关闭
    if (tab.isExecutingScript) {
      return;
    }

    // 停止标签页定时自动刷新
    tab.stopAutoRefresh();

    _tabs.removeAt(index);

    if (_tabs.isEmpty) {
      _currentIndex = 0;
    } else if (_currentIndex >= _tabs.length) {
      _currentIndex = _tabs.length - 1;
    } else if (_currentIndex > index) {
      _currentIndex--;
    }

    notifyListeners();
    _saveTabsState();
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
    // 允许记录 welcome.html 供内部使用，但在 history getter 中过滤不在 UI 展示；排除其他本地文件和 about:blank
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
    _cleanExpiredHistory();
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void updateHistoryTitle(String url, String title) {
    if (_history.isEmpty) return;

    // 若最新一条历史记录 URL 匹配，则更新其标题
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
          .sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 按时间从新到旧排序
    }
    notifyListeners();
    _saveBookmarksAndHistory();
  }

  void toggleScriptPanel() {
    _isScriptPanelExpanded = !_isScriptPanelExpanded;
    notifyListeners();
    _saveTabsState();
  }

  /// 明确收起/收纳脚本管理器抽屉
  void closeScriptPanel() {
    if (_isScriptPanelExpanded) {
      _isScriptPanelExpanded = false;
      notifyListeners();
      _saveTabsState();
    }
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
      _maxHistoryDays = prefs.getInt('max_history_days') ?? 4;
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
      _cleanExpiredHistory();
      notifyListeners();
    } catch (e) {
      debugPrint('Load bookmarks and history error: $e');
    }
  }

  /// 依据设置的最大保存天数清理过期历史记录（0 表示永久保存）
  void _cleanExpiredHistory() {
    if (_maxHistoryDays <= 0) return;
    final now = DateTime.now();
    _history.removeWhere((item) {
      final diffDays = now.difference(item.visitedAt).inDays;
      return diffDays >= _maxHistoryDays;
    });
  }

  /// 设置最大历史记录保存天数并持久化
  Future<void> setMaxHistoryDays(int days) async {
    _maxHistoryDays = days;
    _cleanExpiredHistory();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('max_history_days', days);
      await _saveBookmarksAndHistory();
    } catch (e) {
      debugPrint('Save max history days error: $e');
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

      // 构建待保存的标签页状态数据
      final tabsData = await Future.wait(_tabs.map((tab) async {
        String url = tab.url;
        // 如果 URL 是本地欢迎页路径，保存为 about:blank 以便恢复时触发欢迎页逻辑
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
        'userAgent': _userAgent, // 保存 UserAgent
        'autoLeaveMode': _autoLeaveMode,
        'isAdBlockEnabled': _isAdBlockEnabled,
        'isDebugModeEnabled': _isDebugModeEnabled,
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
        _isAdBlockEnabled = data['isAdBlockEnabled'] ?? true;
        _isDebugModeEnabled = data['isDebugModeEnabled'] ?? false;
        _searchEngine = data['searchEngine'] ?? 'Baidu';
        _userAgent = data['userAgent'] ?? defaultUserAgentType;

        if (_keepScreenOn) {
          await WakelockPlus.enable();
        }
      }
    } catch (e) {
      debugPrint('Load settings error: $e');
    }
  }

  /// 获取当前平台的默认 User-Agent 类型（PC/桌面端默认为 Desktop，移动端默认为 Mobile）
  static String get defaultUserAgentType {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return 'Desktop';
    }
    return 'Mobile';
  }

  static String get desktopUserAgentString {
    if (Platform.isWindows) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  static String get mobileUserAgentString {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';
    }
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  }

  static String get tabletUserAgentString {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14; Tablet) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  }

  // User-Agent 配置
  late String _userAgent = defaultUserAgentType;
  String get userAgent => _userAgent;

  Map<String, String> get uaMap => {
        'Mobile': mobileUserAgentString,
        'Tablet': tabletUserAgentString,
        'Desktop': desktopUserAgentString,
      };

  String getUserAgentString(String? type) {
    if (type == 'Desktop') return desktopUserAgentString;
    if (type == 'Tablet') return tabletUserAgentString;
    if (type == 'Mobile') return mobileUserAgentString;
    return uaMap[_userAgent] ??
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux
            ? desktopUserAgentString
            : mobileUserAgentString);
  }

  Future<void> setUserAgent(String type) async {
    if (uaMap.containsKey(type)) {
      _userAgent = type;
      notifyListeners();
      _saveTabsState();
      // 应用到当前标签页（先读取已有设置再修改，避免覆盖多窗口、下载拦截等设置）
      final tab = currentTab;
      final controller = tab?.controller;
      if (tab != null && controller != null) {
        final effectiveType = tab.customUserAgent ?? type;
        try {
          final currentSettings =
              await controller.getSettings() ?? InAppWebViewSettings();
          currentSettings.userAgent = getUserAgentString(effectiveType);
          currentSettings.preferredContentMode =
              _getPreferredContentMode(effectiveType);
          await controller.setSettings(settings: currentSettings);
        } catch (_) {}
        await controller.reload();
      }
    }
  }

  void setSearchEngine(String engine) {
    _searchEngine = engine;
    notifyListeners();
    _saveTabsState();
  }

  String get currentUserAgentString => getUserAgentString(_userAgent);

  UserPreferredContentMode _getPreferredContentMode(String userAgentType) {
    if (userAgentType == 'Desktop') {
      return UserPreferredContentMode.DESKTOP;
    }
    return UserPreferredContentMode.MOBILE;
  }

  /// 异步获取当前临时缓存大小估算字符串
  Future<String> getCacheSizeString() async {
    try {
      final tempDir = await getTemporaryDirectory();
      // Windows 平台下 getTemporaryDirectory() 返回系统全局 Temp 目录，仅统计应用专属子目录
      final cacheDir = Platform.isWindows
          ? Directory(path.join(tempDir.path, 'auok_browser_cache'))
          : tempDir;
      if (!await cacheDir.exists()) return '0.0 MB';
      int totalBytes = 0;
      await for (final file in cacheDir
          .list(recursive: true, followLinks: false)
          .handleError((_) {})) {
        if (file is File) {
          try {
            totalBytes += await file.length();
          } catch (_) {}
        }
      }
      if (totalBytes < 1024) {
        return '$totalBytes B';
      } else if (totalBytes < 1024 * 1024) {
        return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
      }
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '0.0 MB';
    }
  }

  /// 清空浏览器缓存
  /// 深度清除：InAppWebView 全局缓存、各活跃标签页控制器缓存、系统临时目录文件
  Future<void> clearCache() async {
    try {
      // 1. 全局清除 InAppWebView 缓存（涵盖所有活跃与非活跃标签页）
      try {
        await InAppWebViewController.clearAllCache();
      } catch (e) {
        debugPrint('clearAllCache error: $e');
      }

      // 2. 清理临时目录缓存文件（Windows 下仅清理应用专属子目录，防止误删系统全局 Temp 文件）
      try {
        final tempDir = await getTemporaryDirectory();
        final cacheDir = Platform.isWindows
            ? Directory(path.join(tempDir.path, 'auok_browser_cache'))
            : tempDir;
        if (await cacheDir.exists()) {
          List<FileSystemEntity> entities = [];
          try {
            entities = cacheDir.listSync(recursive: false, followLinks: false);
          } catch (_) {}
          for (final entity in entities) {
            try {
              if (entity is File) {
                await entity.delete();
              } else if (entity is Directory) {
                await entity.delete(recursive: true);
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('Clear temp dir error: $e');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('clearCache failed: $e');
    }
  }
}

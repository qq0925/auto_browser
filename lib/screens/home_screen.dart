import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/browser_provider.dart';
import '../providers/download_provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';
import '../models/browser_tab.dart';
import '../widgets/right_script_panel.dart';
import '../widgets/add_script_dialog.dart';
import '../widgets/global_settings_dialog.dart';
import '../widgets/browser_view.dart';
import '../widgets/download_manager_dialog.dart';

import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../utils/file_manager.dart';

import 'package:permission_handler/permission_handler.dart';
import '../widgets/url_search_overlay.dart';
import '../widgets/page_info_dialog.dart';
import '../widgets/bottom_grid_menu.dart';
import '../widgets/bookmarks_history_dialog.dart';
import '../widgets/auto_refresh_dialog.dart';
import '../widgets/browser_settings_dialog.dart';
import '../widgets/script_recording_overlay.dart';
import '../widgets/cookie_manager_dialog.dart';
import '../widgets/floating_capsule.dart';
import '../widgets/splash_screen_view.dart';
import '../utils/welcome_manager.dart';

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage>
    with WidgetsBindingObserver {
  final TextEditingController _urlController = TextEditingController();
  bool _isAppStarting = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPermissions();
    _startAppInitFlow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 当应用切回前台（如在 iOS 网络权限弹窗点击“允许”）时，自动探测并静默热刷新欢迎页
      _silentlyRefreshWelcomeIfAvailable();
    }
  }

  Future<void> _silentlyRefreshWelcomeIfAvailable() async {
    final browserProvider = context.read<BrowserProvider>();
    final content = await WelcomeManager.fetchLatestRemoteContent(
      timeout: const Duration(seconds: 3),
    );
    if (content != null && content.isNotEmpty && mounted) {
      for (var tab in browserProvider.tabs) {
        if (tab.url == 'about:blank' ||
            tab.url.isEmpty ||
            tab.url.contains('welcome.html')) {
          tab.controller?.loadData(
            data: content,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri('file:///welcome.html'),
          );
        }
      }
    }
  }

  Future<void> _startAppInitFlow() async {
    final browserProvider = context.read<BrowserProvider>();
    final stopwatch = Stopwatch()..start();

    // 并发启动：1. 网络获取最新欢迎页（留出网络连接和权限弹窗时间）；2. Provider 初始化
    final waitWelcome = WelcomeManager.getWelcomeContent(
      remoteTimeout: const Duration(milliseconds: 2500),
    );

    if (browserProvider.isInitialized) {
      await _initTabs();
    } else {
      browserProvider.addListener(_onProviderInitialized);
    }

    await waitWelcome;
    // 保证动效至少呈现 1100ms（入场动效周期），避免一闪而过的生硬感
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 1100) {
      await Future.delayed(Duration(milliseconds: 1100 - elapsed));
    }

    if (mounted) {
      setState(() {
        _isAppStarting = false;
      });
    }
  }

  void _onProviderInitialized() {
    final browserProvider = context.read<BrowserProvider>();
    if (browserProvider.isInitialized) {
      browserProvider.removeListener(_onProviderInitialized);
      _initTabs();
    }
  }

  Future<void> _initPermissions() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }
  }

  Future<void> _initTabs() async {
    final browserProvider = context.read<BrowserProvider>();
    final scriptProvider = context.read<ScriptProvider>();

    // Set wait for page load callback globally once
    scriptProvider.setWaitForPageLoadCallback(() async {
      if (browserProvider.currentTab == null) return;

      final controller = browserProvider.currentTab!.controller;
      int timeout = 30000;
      int elapsed = 0;

      // 1. 等待 isLoading 变为 false
      while (browserProvider.currentTab!.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
        elapsed += 100;
        if (elapsed >= timeout) break;
      }

      // 2. 等待 DOM readyState 为 complete
      if (controller != null && elapsed < timeout) {
        int domCheckCount = 0;
        const maxDomChecks = 50; // 最多检查 5 秒

        while (domCheckCount < maxDomChecks) {
          try {
            final readyState = await controller.evaluateJavascript(
              source: 'document.readyState',
            );
            if (readyState == 'complete') {
              break;
            }
          } catch (e) {
            // 忽略错误，继续等待
          }
          await Future.delayed(const Duration(milliseconds: 100));
          domCheckCount++;
        }
      }
    });

    if (browserProvider.tabs.isEmpty) {
      await _addNewTab();
    }
  }

  Future<void> _addNewTab({String? initialUrl, String? initialTitle}) async {
    final browserProvider = context.read<BrowserProvider>();

    await browserProvider.addTab(
        initialUrl: initialUrl ?? '', initialTitle: initialTitle);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<BrowserProvider, ScriptProvider, DownloadProvider>(
      builder: (context, browserProvider, scriptProvider, downloadProvider, child) {
        // Update ScriptProvider's current tab when it changes
        if (scriptProvider.currentTab != browserProvider.currentTab) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            scriptProvider.setCurrentTab(browserProvider.currentTab);
          });
        }

        // Update URL controller if needed
        if (browserProvider.currentTab != null) {
          final currentUrl = browserProvider.currentTab!.url;
          final displayUrl = currentUrl.startsWith('file://') ? '' : currentUrl;
          if (_urlController.text != displayUrl &&
              !FocusScope.of(context).hasFocus) {
            _urlController.text = displayUrl;
          }
        }

        DateTime? lastBackPressTime;
        final screenWidth = MediaQuery.of(context).size.width;
        // 脚本面板宽度优化：占屏幕约 40%，避免遮挡过多网页内容，方便查看与复制文本
        final panelWidth = (screenWidth * 0.40).clamp(155.0, 320.0);

        return Stack(
          children: [
            CallbackShortcuts(
              bindings: {
            // Ctrl+R 或 F5: 刷新当前标签页
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
              browserProvider.currentTab?.controller?.reload();
            },
            const SingleActivator(LogicalKeyboardKey.f5): () {
              browserProvider.currentTab?.controller?.reload();
            },
            // Ctrl+T: 新建标签页
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
              _addNewTab();
            },
            // Ctrl+W: 关闭当前标签页
            const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
              if (browserProvider.tabs.length > 1) {
                browserProvider.removeTab(browserProvider.currentIndex);
              }
            },
            // Alt+Left: 网页后退
            const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
              if (browserProvider.currentTab?.canGoBack ?? false) {
                browserProvider.currentTab?.controller?.goBack();
              }
            },
            // Alt+Right: 网页前进
            const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
              if (browserProvider.currentTab?.canGoForward ?? false) {
                browserProvider.currentTab?.controller?.goForward();
              }
            },
          },
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;

              // 1. 如果脚本侧边栏处于展开状态，优先收起
              if (browserProvider.isScriptPanelExpanded) {
                browserProvider.toggleScriptPanel();
                return;
              }

              // 2. 如果当前网页可以后退，执行后退
              final currentTab = browserProvider.currentTab;
              if (currentTab != null && currentTab.canGoBack) {
                if (scriptProvider.isRecording) {
                  scriptProvider.recordAction('网页后退');
                }
                await currentTab.controller?.goBack();
                return;
              }

              // 3. 双击退出防误触
              final now = DateTime.now();
              if (lastBackPressTime == null ||
                  now.difference(lastBackPressTime!) >
                      const Duration(seconds: 2)) {
                lastBackPressTime = now;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(scriptProvider.isExecuting
                        ? '脚本正在运行中，再次按下返回键将退出应用'
                        : '再次按下返回键退出应用'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                return;
              }

              // 退出应用
              SystemNavigator.pop();
            },
            child: Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
            elevation: 0,
            toolbarHeight: 48, // 紧凑型高屏占比工具栏
            titleSpacing:
                0, // Remove default spacing to control layout manually
            title: Row(
              children: [
                const SizedBox(width: 8), // 紧凑型左侧间距
                Expanded(
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Bookmark button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: Icon(
                            browserProvider.currentTab != null &&
                                    browserProvider.isBookmarked(
                                        browserProvider.currentTab!.url)
                                ? Icons.star
                                : Icons.star_border,
                            color: browserProvider.currentTab != null &&
                                    browserProvider.isBookmarked(
                                        browserProvider.currentTab!.url)
                                ? Colors.amber
                                : Colors.white,
                            size: 20,
                          ),
                          onPressed: browserProvider.currentTab != null &&
                                  browserProvider.currentTab!.url !=
                                      'about:blank' &&
                                  !browserProvider.currentTab!.url
                                      .endsWith('welcome.html') &&
                                  !browserProvider.currentTab!.url
                                      .startsWith('file://')
                              ? () {
                                  browserProvider.toggleBookmark(
                                    browserProvider.currentTab!.url,
                                    browserProvider.currentTab!.title,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(browserProvider
                                              .isBookmarked(browserProvider
                                                  .currentTab!.url)
                                          ? '已添加书签'
                                          : '已移除书签'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              : null,
                        ),

                        // Vertical Divider
                        Container(
                          height: 18,
                          width: 1,
                          color: Colors.white38,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                        ),

                        // URL GestureDetector
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (browserProvider.currentTab != null) {
                                Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation,
                                            secondaryAnimation) =>
                                        UrlSearchOverlay(
                                      initialUrl: browserProvider
                                                      .currentTab!.url ==
                                                  'about:blank' ||
                                              browserProvider.currentTab!.url ==
                                                  'file:///welcome.html' ||
                                              browserProvider.currentTab!.url
                                                  .endsWith('welcome.html')
                                          ? ''
                                          : browserProvider.currentTab!.url,
                                      onSubmitted: (value) async {
                                        if (value.trim().isNotEmpty) {
                                          String url = value.trim();
                                          if (url == 'welcome.html') {
                                            await browserProvider
                                                .currentTab!.controller
                                                ?.loadData(
                                                    data: 'assets/welcome.html',
                                                    mimeType: 'text/html',
                                                    encoding: 'utf-8');
                                          } else if (url == 'guide.html' ||
                                              url == 'about:guide') {
                                            final content = await rootBundle
                                                .loadString('assets/guide.html');
                                            await browserProvider
                                                .currentTab!.controller
                                                ?.loadData(
                                                    data: content,
                                                    mimeType: 'text/html',
                                                    encoding: 'utf-8',
                                                    baseUrl: WebUri(
                                                        'file:///guide.html'));
                                          } else if (url == 'test_page.html' ||
                                              url == 'test.html' ||
                                              url == 'about:test') {
                                            final content = await rootBundle
                                                .loadString('assets/test_page.html');
                                            await browserProvider
                                                .currentTab!.controller
                                                ?.loadData(
                                                    data: content,
                                                    mimeType: 'text/html',
                                                    encoding: 'utf-8',
                                                    baseUrl: WebUri(
                                                        'file:///test_page.html'));
                                          } else {
                                            if (!url.startsWith('http://') &&
                                                !url.startsWith('https://') &&
                                                !url.startsWith('file://')) {
                                              if (url.contains('.')) {
                                                url = 'http://$url';
                                              } else {
                                                // Search Engine Logic
                                                final engine = browserProvider
                                                    .searchEngine;
                                                if (engine == 'Bing') {
                                                  url =
                                                      'https://www.bing.com/search?q=$url';
                                                } else if (engine == 'Google') {
                                                  url =
                                                      'https://www.google.com/search?q=$url';
                                                } else {
                                                  // Default to Baidu
                                                  url =
                                                      'https://www.baidu.com/s?wd=$url';
                                                }
                                              }
                                            }

                                            // Record navigation for real URLs
                                            if (scriptProvider.isRecording &&
                                                (value.trim().startsWith(
                                                        'http://') ||
                                                    value.trim().startsWith(
                                                        'https://') ||
                                                    value
                                                        .trim()
                                                        .contains('.'))) {
                                              scriptProvider.recordAction(
                                                  '进入网址', url);
                                            }

                                            await browserProvider
                                                .currentTab!.controller
                                                ?.loadUrl(
                                                    urlRequest: URLRequest(
                                                        url: WebUri(url)));
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              color: Colors.transparent,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                (browserProvider.currentTab?.url ==
                                            'about:blank' ||
                                        browserProvider.currentTab?.url ==
                                            'file:///welcome.html' ||
                                        (browserProvider.currentTab?.url
                                                .endsWith('welcome.html') ??
                                            false))
                                    ? 'Auok浏览器'
                                    : '${browserProvider.currentIndex + 1}. ${(browserProvider.currentTab?.title.isEmpty ?? true) ? '无标题' : browserProvider.currentTab!.title}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),

                        // Refresh button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.refresh,
                              color: Colors.white, size: 20),
                          onPressed: () async {
                            if (scriptProvider.isRecording) {
                              scriptProvider.recordAction('刷新网页');
                            }

                            // Smart refresh: check if on welcome page
                            final currentUrl = await browserProvider
                                .currentTab?.controller
                                ?.getUrl();
                            if (currentUrl == null ||
                                currentUrl.toString() == 'about:blank' ||
                                currentUrl.toString() ==
                                    'file:///welcome.html') {
                              // Reload welcome content with latest version
                              WelcomeManager.getWelcomeContent()
                                  .then((content) {
                                browserProvider.currentTab?.controller
                                    ?.loadData(
                                        data: content,
                                        mimeType: 'text/html',
                                        encoding: 'utf-8',
                                        baseUrl:
                                            WebUri('file:///welcome.html'));
                              });
                            } else {
                              // Normal page reload
                              browserProvider.currentTab?.controller?.reload();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // 快捷下载管理入口（带角标）
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.download_rounded,
                          color: Colors.white, size: 21),
                      tooltip: '下载管理',
                      onPressed: () => DownloadManagerDialog.show(context),
                    ),
                    if (downloadProvider.activeCount > 0)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                              minWidth: 15, minHeight: 15),
                          child: Text(
                            downloadProvider.activeCount > 99
                                ? '99+'
                                : '${downloadProvider.activeCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                // Menu button area
                SizedBox(
                  width: 36,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white, size: 21),
                    onSelected: (value) {
                      if (value == 'downloads') {
                        DownloadManagerDialog.show(context);
                      } else if (value == 'page_info') {
                        if (browserProvider.currentTab != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PageInfoDialog(
                                title: browserProvider.currentTab!.title,
                                url: browserProvider.currentTab!.url,
                                controller:
                                    browserProvider.currentTab!.controller,
                              ),
                            ),
                          );
                        }
                      } else if (value == 'night_mode') {
                        browserProvider
                            .toggleDarkMode(!browserProvider.isDarkMode);
                      } else if (value == 'about') {
                        // 获取应用版本信息
                        PackageInfo.fromPlatform().then((packageInfo) {
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: true,
                            builder: (context) => GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(24),
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.asset(
                                            'assets/app_icon.png',
                                            width: 72,
                                            height: 72,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Auok浏览器',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '版本 ${packageInfo.version}.${packageInfo.buildNumber}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          '支持自动化的跨平台浏览器\nBy Lin.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: 16,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        });
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'downloads',
                        child: Row(
                          children: [
                            Icon(Icons.download_rounded,
                                color: Colors.black87, size: 20),
                            SizedBox(width: 12),
                            Text('下载管理'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'page_info',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.black87, size: 20),
                            SizedBox(width: 12),
                            Text('页面属性'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'night_mode',
                        child: Row(
                          children: [
                            Icon(
                                browserProvider.isDarkMode
                                    ? Icons.light_mode
                                    : Icons.dark_mode,
                                color: Theme.of(context).iconTheme.color ??
                                    Colors.black87,
                                size: 20),
                            const SizedBox(width: 12),
                            Text(browserProvider.isDarkMode ? '日间模式' : '夜间模式'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'about',
                        child: Row(
                          children: [
                            Icon(Icons.help_outline,
                                color: Colors.black87, size: 20),
                            SizedBox(width: 12),
                            Text('关于'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3.0),
              child: (browserProvider.currentTab != null &&
                      browserProvider.currentTab!.progress < 1.0)
                  ? LinearProgressIndicator(
                      value: browserProvider.currentTab!.progress,
                      backgroundColor: Colors.grey[800],
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.blue),
                      minHeight: 3.0,
                    )
                  : Container(
                      height: 3.0,
                      color: Colors.transparent,
                    ),
            ),
            actions: [],
          ),
          body: Stack(
            children: [
              // WebView 区域
              browserProvider.tabs.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : IndexedStack(
                      index: browserProvider.currentIndex,
                      children: browserProvider.tabs
                          .asMap()
                          .entries
                          .map((entry) => BrowserView(
                                key: ValueKey(entry.value.id),
                                tab: entry.value,
                                isActive:
                                    entry.key == browserProvider.currentIndex,
                              ))
                          .toList(),
                    ),

              // 右侧脚本面板
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                right: browserProvider.isScriptPanelExpanded
                    ? 0
                    : -panelWidth,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 脚本面板切换按钮
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // 切换侧边栏时暂时屏蔽并撤销可能被穿透捕获的录制动作
                        scriptProvider.cancelLastRecordingIfRecent();
                        browserProvider.toggleScriptPanel();
                      },
                      child: Container(
                        width: 24,
                        height: 60,
                        margin: EdgeInsets.only(
                          top: MediaQuery.of(context).size.height / 2 - 80,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(-2, 0),
                            ),
                          ],
                        ),
                        child: Icon(
                          browserProvider.isScriptPanelExpanded
                              ? Icons.chevron_right
                              : Icons.chevron_left,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    // 脚本面板
                    Container(
                      width: panelWidth,
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                        borderRadius:
                            BorderRadius.horizontal(left: Radius.circular(12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(-2, 0),
                          ),
                        ],
                      ),
                      child: RightScriptPanel(
                        onAddScript: () async {
                          final result = await showDialog<Script>(
                            context: context,
                            builder: (context) => const AddScriptDialog(),
                          );
                          if (result != null && mounted) {
                            scriptProvider.addScript(result);
                          }
                        },
                        onGlobalSettings: () {
                          showDialog(
                            context: context,
                            builder: (context) =>
                                const GlobalSettingsDialog(),
                          );
                        },
                        onExecute: () {
                          if (scriptProvider.isExecuting) {
                            scriptProvider.stopExecution();
                          } else {
                            if (browserProvider.currentTab != null &&
                                browserProvider.currentTab!.controller !=
                                    null) {
                              scriptProvider.startExecution(
                                browserProvider.currentTab!.controller!,
                                browserProvider.currentIndex,
                              );
                            }
                          }
                        },
                        onLoad: () {
                          _showLoadScriptDialog(context, scriptProvider);
                        },
                        onRecordScript: () {
                          if (browserProvider.currentTab != null) {
                            // 点击录制脚本时自动触发一次收纳脚本管理器的动作，避免遮挡网页
                            browserProvider.closeScriptPanel();
                            scriptProvider.startRecording();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // 脚本录制浮窗
              const ScriptRecordingOverlay(),

              // 脚本执行极简悬浮状态胶囊（侧边栏收起时显示）
              const FloatingCapsule(),
            ],
          ),
          bottomNavigationBar:
              _buildBottomBar(context, browserProvider, scriptProvider, downloadProvider),
        ),
      ),
    ),

    // 开屏启动 Loading 层（等待网络与初始化就绪并平滑淡出）
    AnimatedOpacity(
      opacity: _isAppStarting ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      child: IgnorePointer(
        ignoring: !_isAppStarting,
        child: SplashScreenView(isStarting: _isAppStarting),
      ),
    ),
  ],
);
  },
);
}

  Widget _buildBottomBar(
      BuildContext context,
      BrowserProvider browser,
      ScriptProvider scriptProvider,
      DownloadProvider downloadProvider) {
    return Container(
      color: Colors.grey[850],
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: (browser.currentTab?.canGoBack ?? false)
                      ? Colors.white
                      : Colors.white38,
                ),
                onPressed: (browser.currentTab?.canGoBack ?? false)
                    ? () async {
                        if (scriptProvider.isRecording) {
                          scriptProvider.recordAction('网页后退');
                        }
                        await browser.currentTab!.controller?.goBack();
                      }
                    : null,
              ),
              IconButton(
                icon: Icon(
                  Icons.arrow_forward,
                  color: (browser.currentTab?.canGoForward ?? false)
                      ? Colors.white
                      : Colors.white38,
                ),
                onPressed: (browser.currentTab?.canGoForward ?? false)
                    ? () async {
                        if (scriptProvider.isRecording) {
                          scriptProvider.recordAction('网页前进');
                        }
                        await browser.currentTab!.controller?.goForward();
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (context) => BottomGridMenu(
                      isAutoRefreshActive:
                          browser.currentTab?.isAutoRefreshActive ?? false,
                      isExecuting: scriptProvider.isExecuting,
                      onBookmarksHistory: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const BookmarksHistoryDialog(),
                          ),
                        );
                      },
                      onAutoRefresh: () {
                        Navigator.pop(context);
                        if (browser.currentTab != null) {
                          if (browser.currentTab!.isAutoRefreshActive) {
                            browser.currentTab!.stopAutoRefresh();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已取消自动刷新')),
                            );
                          } else {
                            showDialog(
                              context: context,
                              builder: (context) => AutoRefreshDialog(
                                onConfirm: (interval, count) {
                                  browser.currentTab!
                                      .startAutoRefresh(interval, count);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '已开启自动刷新: $interval秒, ${count == 0 ? "无限" : count}次'),
                                    ),
                                  );
                                },
                              ),
                            );
                          }
                        }
                      },
                      onRecordScript: () async {
                        Navigator.pop(context);
                        if (browser.currentTab != null) {
                          // 点击录制脚本时自动收纳脚本管理器，展示完整网页供录制操作
                          browser.closeScriptPanel();
                          scriptProvider.startRecording();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('开始录制脚本...')),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请先打开一个网页')),
                          );
                        }
                      },
                      onCookieManager: () {
                        Navigator.pop(context);
                        if (browser.currentTab != null &&
                            browser.currentTab!.url.isNotEmpty &&
                            !browser.currentTab!.url.startsWith('file://')) {
                          showDialog(
                            context: context,
                            builder: (context) => CookieManagerDialog(
                              currentUrl: browser.currentTab!.url,
                              onReloadRequired: () {
                                browser.currentTab!.controller?.reload();
                              },
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请先打开目标网页后再管理 Cookie/账号')),
                          );
                        }
                      },
                      activeDownloadCount: downloadProvider.activeCount,
                      onDownloads: () {
                        Navigator.pop(context);
                        DownloadManagerDialog.show(context);
                      },
                      onSettings: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) => const BrowserSettingsDialog(),
                        );
                      },
                    ),
                  );
                },
              ),
              IconButton(
                icon: _buildTabCountIcon(
                  count: browser.tabs.length,
                  bgColor: Colors.grey[850] ?? const Color(0xFF303030),
                ),
                tooltip: '标签页 (${browser.tabs.length})',
                onPressed: () {
                  _showTabsList(context, browser);
                },
              ),
              TextButton(
                onPressed: (browser.currentTab != null &&
                        !browser.currentTab!.url.endsWith('welcome.html') &&
                        browser.currentTab!.url != 'file:///welcome.html' &&
                        browser.currentTab!.title != '欢迎使用')
                    ? () {
                        WelcomeManager.getWelcomeContent().then((content) {
                          browser.currentTab!.controller?.loadData(
                              data: content,
                              mimeType: 'text/html',
                              encoding: 'utf-8',
                              baseUrl: WebUri('file:///welcome.html'));
                        });
                      }
                    : null,
                child: Text(
                  'AU',
                  style: TextStyle(
                      color: (browser.currentTab != null &&
                              !browser.currentTab!.url.endsWith('welcome.html') &&
                              browser.currentTab!.url != 'file:///welcome.html' &&
                              browser.currentTab!.title != '欢迎使用')
                          ? Colors.white
                          : Colors.white38,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 绘制带有当前标签数量的双层叠放标签图标（参考移动端多标签按钮设计）
  Widget _buildTabCountIcon({required int count, required Color bgColor}) {
    final displayText = count > 99 ? '99+' : '$count';
    final fontSize = count > 99
        ? 7.5
        : (count >= 10 ? 9.0 : 10.5);

    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 后层标签框（偏左上）
          Positioned(
            left: 1,
            top: 1,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // 前层标签框（偏右下，带底栏背景色遮盖重叠边缘）
          Positioned(
            left: 4.5,
            top: 4.5,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: Colors.white, width: 1.6),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: Text(
                displayText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTabsList(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) =>
          Consumer2<BrowserProvider, ScriptProvider>(
        builder: (context, currentBrowser, scriptProvider, child) => Container(
          height: 440,
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: currentBrowser.tabs.length,
                    itemBuilder: (context, index) {
                      final tab = currentBrowser.tabs[index];
                      final isSelected = index == currentBrowser.currentIndex;
                      final canClose = currentBrowser.canCloseTab(index);
                      final displayTitle =
                          tab.customName != null && tab.customName!.isNotEmpty
                              ? tab.customName!
                              : (tab.title.isEmpty ? '无标题' : tab.title);

                      final isExecuting = tab.isExecutingScript;
                      final statusSummary = tab.executionStatusSummary;

                      // 脚本文件名（如 【书怪】.zds）
                      final scriptFileName = tab.scriptFilePath != null
                          ? path.basename(tab.scriptFilePath!)
                          : '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF333333),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 1.5)
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              currentBrowser.setCurrentIndex(index);
                              Navigator.pop(context);
                            },
                            onLongPress: () {
                              _showEditTabDialog(context, currentBrowser, index);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 左侧信息展示区
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 正在执行脚本的标签右上角显示：【脚本名】.zds 全局:1/1,列表:241/302
                                        if (isExecuting &&
                                            statusSummary.isNotEmpty) ...[
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 2),
                                              child: Text(
                                                scriptFileName.isNotEmpty
                                                    ? '$scriptFileName $statusSummary'
                                                    : statusSummary,
                                                style: TextStyle(
                                                  color: tab.isPaused
                                                      ? Colors.amberAccent
                                                      : Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.normal,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                        // 序号与标题
                                        Text(
                                          '${index + 1}. $displayTitle',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        // 无论是否执行脚本，均展示该标签页的当前网址
                                        const SizedBox(height: 3),
                                        Text(
                                          tab.url.isEmpty
                                              ? 'about:blank'
                                              : tab.url,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 右侧关闭按钮（与截图完全一致的圆圈叉号）
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (!canClose) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text('该标签页正在执行脚本，无法关闭'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                        return;
                                      }

                                      if (currentBrowser.tabs.length <= 1) {
                                        currentBrowser.removeTab(index);
                                        Navigator.pop(context);
                                        _addNewTab();
                                      } else {
                                        currentBrowser.removeTab(index);
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(
                                        Icons.cancel,
                                        color: canClose
                                            ? Colors.white
                                            : Colors.white60,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  height: 1,
                  color: Colors.white10,
                ),
                // 底部操作栏：取消 | 新建窗口 | 三点更多菜单
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            '取消',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.white24,
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _addNewTab();
                          },
                          child: const Text(
                            '新建窗口',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.white24,
                      ),
                      // 三点更多操作菜单（包含 7 个多窗口批量功能）
                      Theme(
                        data: Theme.of(context).copyWith(
                          cardColor: const Color(0xFF2C2C2C),
                        ),
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          color: const Color(0xFF2C2C2C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.white12),
                          ),
                          offset: const Offset(0, -360),
                          onSelected: (action) {
                            _handleTabsMenuAction(
                              context,
                              bottomSheetContext,
                              currentBrowser,
                              scriptProvider,
                              action,
                            );
                          },
                          itemBuilder: (context) => [
                            _buildTabsMenuItem('stop_multi', '停止执行多个窗口'),
                            _buildTabsMenuItem('pause_multi', '暂停执行多个窗口'),
                            _buildTabsMenuItem('start_multi', '开始执行多个窗口'),
                            _buildTabsMenuItem('refresh_multi', '刷新多个窗口'),
                            _buildTabsMenuItem('close_multi', '关闭多个窗口'),
                            _buildTabsMenuItem('load_script_multi', '读取脚本到多个窗口'),
                            _buildTabsMenuItem('open_bookmarks_multi', '从书签打开多个窗口'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildTabsMenuItem(String value, String text) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 处理标签页底栏三点菜单中的 7 个多窗口功能
  Future<void> _handleTabsMenuAction(
    BuildContext rootContext,
    BuildContext bottomSheetContext,
    BrowserProvider currentBrowser,
    ScriptProvider scriptProvider,
    String action,
  ) async {
    switch (action) {
      case 'stop_multi':
        final executingTabs =
            currentBrowser.tabs.where((t) => t.isExecutingScript).toList();
        if (executingTabs.isEmpty) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            const SnackBar(content: Text('当前没有正在执行脚本的窗口')),
          );
          return;
        }
        final selectedTabs = await _showTabSelectionDialog(
          context: rootContext,
          browser: currentBrowser,
          title: '停止执行多个窗口',
          confirmText: '停止执行',
          confirmColor: Colors.redAccent,
          initialSelectedTabs: executingTabs,
          filterTab: (tab) => tab.isExecutingScript,
        );
        if (selectedTabs != null && selectedTabs.isNotEmpty) {
          for (var tab in selectedTabs) {
            scriptProvider.stopExecution(tab);
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已停止 ${selectedTabs.length} 个窗口的脚本执行')),
            );
          }
        }
        break;

      case 'pause_multi':
        final executingTabs =
            currentBrowser.tabs.where((t) => t.isExecutingScript).toList();
        if (executingTabs.isEmpty) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            const SnackBar(content: Text('当前没有正在执行脚本的窗口')),
          );
          return;
        }
        final selectedTabs = await _showTabSelectionDialog(
          context: rootContext,
          browser: currentBrowser,
          title: '暂停执行多个窗口',
          confirmText: '暂停执行',
          confirmColor: Colors.amberAccent,
          initialSelectedTabs:
              executingTabs.where((t) => !t.isPaused).toList(),
          filterTab: (tab) => tab.isExecutingScript,
        );
        if (selectedTabs != null && selectedTabs.isNotEmpty) {
          for (var tab in selectedTabs) {
            scriptProvider.pauseExecution(tab);
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已暂停 ${selectedTabs.length} 个窗口的脚本执行')),
            );
          }
        }
        break;

      case 'start_multi':
        final readyTabs = currentBrowser.tabs
            .where((t) => t.scripts.isNotEmpty && !t.isExecutingScript)
            .toList();
        if (readyTabs.isEmpty) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            const SnackBar(content: Text('暂无可开始执行脚本的窗口（需先添加或读取脚本）')),
          );
          return;
        }
        final selectedTabs = await _showTabSelectionDialog(
          context: rootContext,
          browser: currentBrowser,
          title: '开始执行多个窗口',
          confirmText: '开始执行',
          confirmColor: Colors.greenAccent,
          initialSelectedTabs: readyTabs,
          filterTab: (tab) =>
              tab.scripts.isNotEmpty && !tab.isExecutingScript,
        );
        if (selectedTabs != null && selectedTabs.isNotEmpty) {
          for (var tab in selectedTabs) {
            if (tab.controller != null) {
              final tabIndex = currentBrowser.tabs.indexOf(tab);
              scriptProvider.startExecution(tab.controller!, tabIndex, tab);
            }
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已开始执行 ${selectedTabs.length} 个窗口的脚本')),
            );
          }
        }
        break;

      case 'refresh_multi':
        final selectedTabs = await _showTabSelectionDialog(
          context: rootContext,
          browser: currentBrowser,
          title: '刷新多个窗口',
          confirmText: '确认刷新',
          confirmColor: Colors.blueAccent,
          initialSelectedTabs: currentBrowser.tabs,
        );
        if (selectedTabs != null && selectedTabs.isNotEmpty) {
          for (var tab in selectedTabs) {
            tab.controller?.reload();
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已刷新 ${selectedTabs.length} 个窗口')),
            );
          }
        }
        break;

      case 'close_multi':
        final nonCurrentTabs = currentBrowser.tabs
            .where((t) => t != currentBrowser.currentTab && !t.isExecutingScript)
            .toList();
        final selectedTabs = await _showTabSelectionDialog(
          context: rootContext,
          browser: currentBrowser,
          title: '关闭多个窗口',
          confirmText: '关闭窗口',
          confirmColor: Colors.redAccent,
          initialSelectedTabs: nonCurrentTabs.isNotEmpty
              ? nonCurrentTabs
              : currentBrowser.tabs.where((t) => !t.isExecutingScript).toList(),
          filterTab: (tab) => !tab.isExecutingScript,
        );
        if (selectedTabs != null && selectedTabs.isNotEmpty) {
          final toClose = List<BrowserTab>.from(selectedTabs);
          for (var tab in toClose) {
            final idx = currentBrowser.tabs.indexOf(tab);
            if (idx != -1) {
              currentBrowser.removeTab(idx);
            }
          }
          if (currentBrowser.tabs.isEmpty) {
            await _addNewTab();
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已关闭 ${toClose.length} 个窗口')),
            );
          }
        }
        break;

      case 'load_script_multi':
        // 1. 先选择脚本文件
        final filePath = await _showPickScriptDialog(rootContext);
        if (filePath == null) return;
        final file = File(filePath);
        if (!await file.exists()) {
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              const SnackBar(content: Text('脚本文件不存在')),
            );
          }
          return;
        }
        final scriptContent = await file.readAsString();
        if (!rootContext.mounted) return;

        // 2. 选择要批量应用的窗口
        final selectedTabs = await _showTabSelectionDialog(
          context: rootContext,
          browser: currentBrowser,
          title: '读取脚本到多个窗口',
          subtitle: '脚本: ${path.basename(filePath)}',
          confirmText: '批量应用',
          confirmColor: Colors.blueAccent,
          initialSelectedTabs: currentBrowser.tabs,
        );
        if (selectedTabs != null && selectedTabs.isNotEmpty) {
          for (var tab in selectedTabs) {
            scriptProvider.importScriptToTab(scriptContent, tab, filePath);
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text(
                    '已将 ${path.basename(filePath)} 读取到 ${selectedTabs.length} 个窗口'),
              ),
            );
          }
        }
        break;

      case 'open_bookmarks_multi':
        if (currentBrowser.bookmarks.isEmpty) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            const SnackBar(content: Text('暂无书签，请先收藏网址')),
          );
          return;
        }
        final selectedBookmarks = await _showBookmarksMultiSelectDialog(
          context: rootContext,
          bookmarks: currentBrowser.bookmarks,
        );
        if (selectedBookmarks != null && selectedBookmarks.isNotEmpty) {
          if (bottomSheetContext.mounted) {
            Navigator.pop(bottomSheetContext);
          }

          final canReuseBlankTab = currentBrowser.tabs.length == 1 &&
              (currentBrowser.tabs.first.url == 'about:blank' ||
                  currentBrowser.tabs.first.url.endsWith('welcome.html')) &&
              !currentBrowser.tabs.first.isExecutingScript &&
              currentBrowser.tabs.first.controller != null;

          for (int i = 0; i < selectedBookmarks.length; i++) {
            final b = selectedBookmarks[i];
            if (i == 0 && canReuseBlankTab) {
              final targetUrl = BrowserProvider.normalizeUrl(b.url);
              final firstTab = currentBrowser.tabs.first;
              firstTab.url = targetUrl;
              firstTab.title = b.title;
              currentBrowser.updateTabInfo(0, targetUrl, b.title);
              firstTab.controller?.loadUrl(
                  urlRequest: URLRequest(url: WebUri(targetUrl)));
            } else {
              await currentBrowser.addTab(
                initialUrl: b.url,
                initialTitle: b.title,
                switchToNewTab: i == selectedBookmarks.length - 1,
              );
            }
          }
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('已从书签打开 ${selectedBookmarks.length} 个新窗口')),
            );
          }
        }
        break;
    }
  }

  /// 通用多窗口选择弹窗（支持全选/全不选、状态展示与批量操作）
  Future<List<BrowserTab>?> _showTabSelectionDialog({
    required BuildContext context,
    required BrowserProvider browser,
    required String title,
    String? subtitle,
    required String confirmText,
    required Color confirmColor,
    required List<BrowserTab> initialSelectedTabs,
    bool Function(BrowserTab)? filterTab,
  }) {
    final candidateTabs = filterTab != null
        ? browser.tabs.where(filterTab).toList()
        : browser.tabs;

    if (candidateTabs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有符合操作条件的窗口')),
      );
      return Future.value(null);
    }

    final selected = Set<BrowserTab>.from(initialSelectedTabs);

    return showDialog<List<BrowserTab>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setState) {
          final isAllSelected = selected.length == candidateTabs.length;

          return AlertDialog(
            backgroundColor: const Color(0xFF2B2B2B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (isAllSelected) {
                        selected.clear();
                      } else {
                        selected.addAll(candidateTabs);
                      }
                    });
                  },
                  child: Text(
                    isAllSelected ? '全不选' : '全选',
                    style: const TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView.builder(
                itemCount: candidateTabs.length,
                itemBuilder: (context, idx) {
                  final tab = candidateTabs[idx];
                  final originalIndex = browser.tabs.indexOf(tab);
                  final isChecked = selected.contains(tab);
                  final displayTitle =
                      tab.customName != null && tab.customName!.isNotEmpty
                          ? tab.customName!
                          : (tab.title.isEmpty ? '无标题' : tab.title);

                  return CheckboxListTile(
                    value: isChecked,
                    activeColor: confirmColor,
                    checkColor: Colors.black,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(
                      '${originalIndex + 1}. $displayTitle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      tab.isExecutingScript
                          ? '正在执行脚本 (${tab.scripts.length}步)'
                          : (tab.url.isEmpty ? 'about:blank' : tab.url),
                      style: TextStyle(
                        color: tab.isExecutingScript
                            ? Colors.amberAccent
                            : Colors.white54,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          selected.add(tab);
                        } else {
                          selected.remove(tab);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, null),
                child: const Text('取消', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialogCtx, selected.toList()),
                child: Text('$confirmText (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 批量从书签选择对话框
  Future<List<dynamic>?> _showBookmarksMultiSelectDialog({
    required BuildContext context,
    required List<dynamic> bookmarks,
  }) {
    final selected = Set<dynamic>.from(bookmarks);

    return showDialog<List<dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setState) {
          final isAllSelected = selected.length == bookmarks.length;

          return AlertDialog(
            backgroundColor: const Color(0xFF2B2B2B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    '从书签打开多个窗口',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (isAllSelected) {
                        selected.clear();
                      } else {
                        selected.addAll(bookmarks);
                      }
                    });
                  },
                  child: Text(
                    isAllSelected ? '全不选' : '全选',
                    style: const TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView.builder(
                itemCount: bookmarks.length,
                itemBuilder: (context, idx) {
                  final b = bookmarks[idx];
                  final isChecked = selected.contains(b);

                  return CheckboxListTile(
                    value: isChecked,
                    activeColor: Colors.blueAccent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(
                      b.title ?? '未命名书签',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      b.url ?? '',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          selected.add(b);
                        } else {
                          selected.remove(b);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, null),
                child: const Text('取消', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialogCtx, selected.toList()),
                child: Text('打开所选 (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 选择脚本文件对话框（供批量读取到多个窗口使用）
  Future<String?> _showPickScriptDialog(BuildContext context) async {
    final savedScripts = await FileManager.getSavedScripts();

    if (!context.mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text(
          '选择要读取的脚本',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: savedScripts.isEmpty
              ? const Center(
                  child: Text(
                    '暂无本地保存的脚本\n可点击下方从外部文件选择',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  itemCount: savedScripts.length,
                  itemBuilder: (context, index) {
                    final file = savedScripts[index];
                    final fileName = path.basename(file.path);
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.description,
                          color: Colors.blueAccent),
                      title: Text(
                        fileName,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(dialogCtx, file.path),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, null),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              FilePickerResult? pickResult = await FilePicker.platform.pickFiles(
                dialogTitle: '选择脚本文件',
                type: FileType.any,
              );
              if (pickResult != null && pickResult.files.single.path != null) {
                final p = pickResult.files.single.path!;
                if (p.toLowerCase().endsWith('.json') ||
                    p.toLowerCase().endsWith('.zds')) {
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx, p);
                  }
                  return;
                }
              }
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx, null);
              }
            },
            child: const Text('从外部文件选择...',
                style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  void _showEditTabDialog(
      BuildContext context, BrowserProvider browser, int index) {
    final tab = browser.tabs[index];
    final nameController = TextEditingController(text: tab.customName);
    String selectedUa = tab.customUserAgent ?? 'Mobile';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('编辑窗口信息', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '窗口名称',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedUa,
                dropdownColor: Colors.grey[800],
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '用户代理 (User Agent)',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'Mobile', child: Text('手机')),
                  DropdownMenuItem(value: 'Desktop', child: Text('电脑')),
                  DropdownMenuItem(value: 'Tablet', child: Text('平板')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedUa = value;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                browser.updateTabCustomSettings(
                    index, nameController.text, selectedUa);
                Navigator.pop(context);
              },
              child: const Text('保存', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    ).then((_) {
      nameController.dispose();
    });
  }

  void _showLoadScriptDialog(
      BuildContext context, ScriptProvider scriptProvider) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '读取脚本',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: '粘贴脚本内容...',
                  hintStyle: TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white24,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child:
                        const Text('取消', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: () {
                      scriptProvider.importScript(controller.text);
                      Navigator.pop(context);
                    },
                    child:
                        const Text('确定', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      controller.dispose();
    });
  }
}

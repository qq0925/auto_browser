import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/browser_provider.dart';
import '../providers/download_provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';
import '../widgets/right_script_panel.dart';
import '../widgets/add_script_dialog.dart';
import '../widgets/global_settings_dialog.dart';
import '../widgets/browser_view.dart';
import '../widgets/download_manager_dialog.dart';

import 'dart:async';
import 'dart:io';

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
    // 稍微等待 300ms 保证 WebView 首次渲染就绪
    await Future.delayed(const Duration(milliseconds: 300));

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
        final panelWidth = (screenWidth * 0.5).clamp(180.0, 420.0);

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
                          .map((tab) => BrowserView(
                                key: ValueKey(tab.id),
                                tab: tab,
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
                top: 50,
                bottom: 50,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 脚本面板切换按钮
                    GestureDetector(
                      onTap: () {
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
                      decoration: BoxDecoration(
                        color: browserProvider.isDarkMode
                            ? Colors.grey[900]
                            : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(-2, 0),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
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
                              scriptProvider.startRecording();
                            }
                          },
                        ),
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

    // 开屏启动 Loading 层（等待网络就绪并平滑淡出）
    AnimatedOpacity(
      opacity: _isAppStarting ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !_isAppStarting,
        child: _buildSplashScreen(),
      ),
    ),
  ],
);
  },
);
}

  Widget _buildSplashScreen() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F172A), // 深邃星夜蓝
            Color(0xFF090D16),
            Color(0xFF05070B),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 顶部轻量极光光晕背景
          Positioned(
            top: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.12),
              ),
            ),
          ),

          // 中心品牌与微动效
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 应用 Logo（带双层外发光环与高质感圆角）
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                      blurRadius: 32,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: Image.asset(
                    'assets/app_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFF1E293B),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        size: 42,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // 品牌主标题
              const Text(
                'Auok',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 6),

              // 品牌副标（现代科技感排版）
              Text(
                '智能自动化极速浏览器',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 36),

              // 极简微光流线加载条（替代生硬转圈圈）
              SizedBox(
                width: 60,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF38BDF8), // 现代霓虹天蓝
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 底部极简版本署名
          Positioned(
            bottom: 36,
            child: Text(
              'FAST · AUTOMATED · PRIVACY',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 10,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
          height: 420,
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
                                        // 正在执行脚本的标签右上角显示：全局延迟，全局循环次数，列表执行情况
                                        if (isExecuting &&
                                            statusSummary.isNotEmpty) ...[
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 2),
                                              child: Text(
                                                statusSummary,
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
                                        // 正在执行脚本时展示该标签页的当前网址
                                        if (isExecuting) ...[
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import '../widgets/right_script_panel.dart';
import '../widgets/add_script_dialog.dart';
import '../widgets/global_settings_dialog.dart';

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
import '../utils/welcome_manager.dart';

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  final TextEditingController _urlController = TextEditingController();
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _initTabs();
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
      int timeout = 30000;
      int elapsed = 0;
      while (browserProvider.currentTab!.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
        elapsed += 100;
        if (elapsed >= timeout) break;
      }
    });

    if (browserProvider.restoredTabsData != null &&
        browserProvider.restoredTabsData!.isNotEmpty) {
      for (var data in browserProvider.restoredTabsData!) {
        final url = data['url'] as String;
        final title = data['title'] as String;
        final scriptFilePath =
            data['scriptFilePath'] as String?; // Restore script file path

        final controller = _createWebViewController(
            browserProvider, scriptProvider,
            initialUrl: url);

        await browserProvider.addTab(
          initialUrl: url,
          initialTitle: title,
          controller: controller,
          scriptFilePath: scriptFilePath, // Pass script file path
        );
      }

      if (browserProvider.restoredIndex != null) {
        browserProvider.setCurrentIndex(browserProvider.restoredIndex!);
      }

      browserProvider.clearRestoredData();
    }

    if (browserProvider.tabs.isEmpty) {
      await _addNewTab();
    }
  }

  WebViewController _createWebViewController(
      BrowserProvider browserProvider, ScriptProvider scriptProvider,
      {String? initialUrl}) {
    final controller = WebViewController();

    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setBackgroundColor(
        browserProvider.isDarkMode ? Colors.black : Colors.white);

    controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          final index = browserProvider.tabs
              .indexWhere((t) => t.controller == controller);
          if (index != -1) {
            if (index == browserProvider.currentIndex) {
              browserProvider.updateTabProgress(progress / 100.0);
            } else {
              browserProvider.tabs[index].progress = progress / 100.0;
            }
          }
        },
        onPageStarted: (String url) {
          final index = browserProvider.tabs
              .indexWhere((t) => t.controller == controller);
          if (index != -1) {
            final tab = browserProvider.tabs[index];
            tab.isLoading = true;
            if (index == browserProvider.currentIndex) {
              browserProvider.updateTabProgress(0.0);
            }

            if (url != 'about:blank' && !url.endsWith('welcome.html')) {
              tab.url = url;
              try {
                final historyItem = browserProvider.history.firstWhere(
                  (item) => item.url == url,
                );
                tab.title = historyItem.title;
              } catch (_) {}
            }

            if (url.startsWith('http')) {
              tab.url = url;
              if (index == browserProvider.currentIndex &&
                  !FocusScope.of(context).hasFocus) {
                final displayUrl = url.startsWith('file://') ? '' : url;
                _urlController.text = displayUrl;
              }
            }
          }
        },
        onPageFinished: (String url) async {
          final index = browserProvider.tabs
              .indexWhere((t) => t.controller == controller);
          if (index != -1) {
            final tab = browserProvider.tabs[index];
            tab.isLoading = false;
            if (index == browserProvider.currentIndex) {
              browserProvider.updateTabProgress(1.0);
            }

            browserProvider.injectNightModeIfEnabled(controller);

            if (scriptProvider.isRecording &&
                index == browserProvider.currentIndex) {
              controller.runJavaScript(ScriptProvider.recordingJs);
            }

            // Get title with retry for background tabs
            String? title = await controller.getTitle();

            // Retry if title is null or empty (common for background tabs)
            if ((title == null || title.isEmpty) && url.startsWith('http')) {
              for (int i = 0; i < 3; i++) {
                await Future.delayed(const Duration(milliseconds: 500));
                title = await controller.getTitle();
                if (title != null && title.isNotEmpty) break;
              }
            }

            // Use URL as fallback if still no title
            if (title == null || title.isEmpty) {
              title = url;
            }

            browserProvider.updateTabInfo(index, url, title);
            if (url.startsWith('http')) {
              browserProvider.addToHistory(url, title);
            }

            // Update navigation state for forward/back buttons
            _updateNavigationState();
          }
        },
        onNavigationRequest: (NavigationRequest request) {
          return NavigationDecision.navigate;
        },
      ),
    );

    controller.addJavaScriptChannel(
      'ScriptRunner',
      onMessageReceived: (JavaScriptMessage message) {
        scriptProvider.handleScriptMessage(message.message);
      },
    );

    controller.setOnJavaScriptAlertDialog(
        (JavaScriptAlertDialogRequest request) async {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(request.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    });

    controller.setOnJavaScriptConfirmDialog(
        (JavaScriptConfirmDialogRequest request) async {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text(request.message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定'),
                ),
              ],
            ),
          ) ??
          false;
    });

    controller.setOnJavaScriptTextInputDialog(
        (JavaScriptTextInputDialogRequest request) async {
      final textController = TextEditingController(text: request.defaultText);
      return await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              content: TextField(
                controller: textController,
                decoration: InputDecoration(hintText: request.message),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, textController.text),
                  child: const Text('确定'),
                ),
              ],
            ),
          ) ??
          '';
    });

    if (initialUrl != null && initialUrl.isNotEmpty) {
      controller.loadRequest(Uri.parse(initialUrl));
    } else {
      // Load welcome.html by default for new tabs
      // Use updated version if available, fallback to bundled asset
      WelcomeManager.getWelcomeContent().then((content) {
        // Use file:// URL to ensure proper navigation history
        controller.loadHtmlString(content, baseUrl: 'file:///welcome.html');
      });
    }

    return controller;
  }

  Future<void> _addNewTab({String? initialUrl, String? initialTitle}) async {
    final browserProvider = context.read<BrowserProvider>();
    final scriptProvider = context.read<ScriptProvider>();

    final controller = _createWebViewController(browserProvider, scriptProvider,
        initialUrl: initialUrl);

    await browserProvider.addTab(
        initialUrl: initialUrl ?? '',
        initialTitle: initialTitle,
        controller: controller);
  }

  Future<void> _updateNavigationState() async {
    final browserProvider = context.read<BrowserProvider>();
    if (browserProvider.currentTab != null && mounted) {
      final canGoBack =
          await browserProvider.currentTab!.controller.canGoBack();
      final canGoForward =
          await browserProvider.currentTab!.controller.canGoForward();

      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BrowserProvider, ScriptProvider>(
      builder: (context, browserProvider, scriptProvider, child) {
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

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
            elevation: 0,
            toolbarHeight: 60, // Flatter toolbar
            titleSpacing:
                0, // Remove default spacing to control layout manually
            title: Row(
              children: [
                const SizedBox(width: 10), // Small left margin
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 6, bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius:
                          BorderRadius.circular(4), // Slightly smaller radius
                      border: Border.all(
                        color: Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Bookmark button
                        IconButton(
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
                            size: 28, // Larger star icon
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
                          height: 24,
                          width: 1,
                          color: Colors.white38,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                        ),

                        // URL GestureDetector
                        Expanded(
                          child: GestureDetector(
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
                                                .loadFlutterAsset(
                                                    'assets/welcome.html');
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
                                            await browserProvider
                                                .currentTab!.controller
                                                .loadRequest(Uri.parse(url));
                                          }
                                          Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                            if (mounted) {
                                              _updateNavigationState();
                                            }
                                          });
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
                                  const EdgeInsets.symmetric(horizontal: 8),
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
                                    : (browserProvider
                                                .currentTab?.title.isEmpty ??
                                            true)
                                        ? '无标题'
                                        : browserProvider.currentTab!.title,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),

                        // Refresh button
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              color: Colors.white, size: 24),
                          onPressed: () async {
                            if (scriptProvider.isRecording) {
                              scriptProvider.recordAction('刷新网页');
                            }

                            // Smart refresh: check if on welcome page
                            final currentUrl = await browserProvider
                                .currentTab?.controller
                                .currentUrl();
                            if (currentUrl == null ||
                                currentUrl == 'about:blank' ||
                                currentUrl == 'file:///welcome.html') {
                              // Reload welcome content with latest version
                              WelcomeManager.getWelcomeContent()
                                  .then((content) {
                                browserProvider.currentTab?.controller
                                    .loadHtmlString(content,
                                        baseUrl: 'file:///welcome.html');
                              });
                            } else {
                              // Normal page reload
                              browserProvider.currentTab?.controller.reload();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Menu button area - centered between box and screen edge
                SizedBox(
                  width: 48,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'page_info') {
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
                                        borderRadius: BorderRadius.circular(12),
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
                                      const Text(
                                        'Version 1.0.0',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      const Text(
                                        '一个支持自动化的iOS浏览器\nBy Lin.',
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
                      }
                    },
                    itemBuilder: (context) => [
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
            actions: [], // Empty actions as menu is moved to title
          ),
          body: Stack(
            children: [
              // WebView 区域 - 全屏，不挤压
              browserProvider.tabs.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : IndexedStack(
                      index: browserProvider.currentIndex,
                      children: browserProvider.tabs
                          .map((tab) =>
                              WebViewWidget(controller: tab.controller))
                          .toList(),
                    ),

              // 右侧脚本面板（可折叠）- 浮在WebView上方
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                right: browserProvider.isScriptPanelExpanded
                    ? 0
                    : -(MediaQuery.of(context).size.width * 0.5),
                top: 50, // Margin from top
                bottom: 50, // Margin from bottom
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 脚本面板切换按钮 - 和面板一体
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
                      width: MediaQuery.of(context).size.width * 0.5,
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
                          onAddScript: () {
                            showDialog(
                              context: context,
                              builder: (context) => const AddScriptDialog(),
                            );
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
                              if (browserProvider.currentTab != null) {
                                scriptProvider.startExecution(
                                  browserProvider.currentTab!.controller,
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
                              browserProvider.currentTab!.controller
                                  .runJavaScript(ScriptProvider.recordingJs);
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
            ],
          ),
          bottomNavigationBar:
              _buildBottomBar(context, browserProvider, scriptProvider),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, BrowserProvider browser,
      ScriptProvider scriptProvider) {
    return Container(
      height: 50,
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: _canGoBack ? Colors.white : Colors.white38,
            ),
            onPressed: _canGoBack && browser.currentTab != null
                ? () async {
                    if (scriptProvider.isRecording) {
                      scriptProvider.recordAction('网页后退');
                    }
                    await browser.currentTab!.controller.goBack();
                    await _updateNavigationState();
                  }
                : null,
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_forward,
              color: _canGoForward ? Colors.white : Colors.white38,
            ),
            onPressed: _canGoForward && browser.currentTab != null
                ? () async {
                    if (scriptProvider.isRecording) {
                      scriptProvider.recordAction('网页前进');
                    }
                    await browser.currentTab!.controller.goForward();
                    await _updateNavigationState();
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
                        builder: (context) => const BookmarksHistoryDialog(),
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
                      // Inject script immediately
                      await browser.currentTab!.controller
                          .runJavaScript(ScriptProvider.recordingJs);
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
            icon: const Icon(Icons.tab, color: Colors.white),
            onPressed: () {
              _showTabsList(context, browser);
            },
          ),
          TextButton(
            onPressed: () {
              // AU按钮功能 - 回到初始页面
              if (browser.currentTab != null) {
                WelcomeManager.getWelcomeContent().then((content) {
                  browser.currentTab!.controller
                      .loadHtmlString(content, baseUrl: 'file:///welcome.html');
                });
              }
            },
            child: const Text(
              'AU',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showTabsList(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => Container(
        height: 400,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '标签页',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.white, size: 28),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _addNewTab();
                  },
                  tooltip: '新建标签',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: browser.tabs.length,
                itemBuilder: (context, index) {
                  final tab = browser.tabs[index];
                  final isSelected = index == browser.currentIndex;
                  final canClose = browser.canCloseTab(index);

                  return ListTile(
                    title: Text(
                      tab.title,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tab.url != 'about:blank' &&
                            !tab.url.endsWith('welcome.html'))
                          Text(
                            tab.url,
                            style: const TextStyle(color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (tab.isExecutingScript)
                          const Text(
                            '正在执行脚本...',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    selected: isSelected,
                    onTap: () {
                      browser.setCurrentIndex(index);
                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: canClose ? Colors.white : Colors.grey.shade600,
                      ),
                      onPressed: () {
                        if (!canClose) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('该标签页正在执行脚本，无法关闭'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          return;
                        }

                        if (browser.tabs.length == 1) {
                          // Last tab - remove and create new default tab
                          browser.removeTab(index);
                          Navigator.pop(context);
                          _addNewTab();
                        } else {
                          browser.removeTab(index);
                          if (browser.tabs.isEmpty) {
                            Navigator.pop(context);
                            _addNewTab();
                          }
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
    );
  }
}

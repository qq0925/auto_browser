import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';
import '../widgets/right_script_panel.dart';
import '../widgets/add_script_dialog.dart';
import '../widgets/global_settings_dialog.dart';
import '../widgets/browser_view.dart';

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

  @override
  void initState() {
    super.initState();
    _initPermissions();

    // Wait for provider to be initialized
    final browserProvider = context.read<BrowserProvider>();
    if (browserProvider.isInitialized) {
      _initTabs();
    } else {
      browserProvider.addListener(_onProviderInitialized);
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
      int timeout = 30000;
      int elapsed = 0;
      while (browserProvider.currentTab!.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
        elapsed += 100;
        if (elapsed >= timeout) break;
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
                    height: 48,
                    margin: const EdgeInsets.only(top: 6, bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            size: 28,
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
                                    : '${browserProvider.currentIndex + 1}. ${(browserProvider.currentTab?.title.isEmpty ?? true) ? '无标题' : browserProvider.currentTab!.title}',
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
                // Menu button area
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
                    : -(MediaQuery.of(context).size.width * 0.5),
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
                              !browser.currentTab!.url
                                  .endsWith('welcome.html') &&
                              browser.currentTab!.url !=
                                  'file:///welcome.html' &&
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

  void _showTabsList(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 400,
        decoration: const BoxDecoration(
          color: Color(0xFF222222),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: browser.tabs.length,
                itemBuilder: (context, index) {
                  final tab = browser.tabs[index];
                  final isSelected = index == browser.currentIndex;
                  final canClose = browser.canCloseTab(index);
                  final displayTitle =
                      tab.customName != null && tab.customName!.isNotEmpty
                          ? tab.customName!
                          : (tab.title.isEmpty ? '无标题' : tab.title);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 1.5)
                          : null,
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: Text(
                        '${index + 1}. $displayTitle',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.close,
                          color:
                              canClose ? Colors.white70 : Colors.grey.shade600,
                          size: 20,
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
                      onTap: () {
                        browser.setCurrentIndex(index);
                        Navigator.pop(context);
                      },
                      onLongPress: () {
                        _showEditTabDialog(context, browser, index);
                      },
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
    );
  }

  void _showEditTabDialog(
      BuildContext context, BrowserProvider browser, int index) {
    final tab = browser.tabs[index];
    final nameController = TextEditingController(text: tab.customName);
    String selectedUa = tab.customUserAgent ?? 'Mobile';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
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
                  labelText: 'User Agent',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'Mobile', child: Text('Mobile')),
                  DropdownMenuItem(value: 'Desktop', child: Text('Desktop')),
                  DropdownMenuItem(value: 'Tablet', child: Text('Tablet')),
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
                Navigator.pop(context);
                _showTabsList(context, browser);
              },
              child: const Text('保存', style: TextStyle(color: Colors.blue)),
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

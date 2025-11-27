import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import '../widgets/right_script_panel.dart';
import '../widgets/add_script_dialog.dart';
import '../widgets/global_settings_dialog.dart';
import '../models/browser_data.dart';
import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/url_search_overlay.dart';

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
    if (browserProvider.tabs.isEmpty) {
      await _addNewTab();
    }
  }

  Future<void> _addNewTab({String? initialUrl, String? initialTitle}) async {
    final browserProvider = context.read<BrowserProvider>();
    final scriptProvider = context.read<ScriptProvider>();

    WebViewController? webViewController;

    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (url.startsWith('http')) {
              browserProvider.currentTab?.url = url;
              if (!FocusScope.of(context).hasFocus) {
                final displayUrl = url.startsWith('file://') ? '' : url;
                _urlController.text = displayUrl;
              }
            }
          },
          onPageFinished: (String url) async {
            final title = await webViewController!.getTitle() ?? url;
            browserProvider.currentTab?.title = title;
            browserProvider.currentTab?.url = url;

            if (!url.startsWith('file://') && url != 'about:blank') {
              // Add to history - using internal method
              browserProvider.history.insert(
                0,
                HistoryItem(
                  title: title,
                  url: url,
                  visitedAt: DateTime.now(),
                ),
              );
            }

            await _updateNavigationState();
          },
          onNavigationRequest: (NavigationRequest request) {
            if (scriptProvider.isRecording && request.url.startsWith('http')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'ScriptRecorder',
        onMessageReceived: (JavaScriptMessage message) {
          scriptProvider.handleScriptMessage(message.message);
        },
      );

    if (initialUrl != null && initialUrl != 'about:blank') {
      await webViewController.loadRequest(Uri.parse(initialUrl));
    } else {
      await webViewController.loadFlutterAsset('assets/welcome.html');
    }

    await browserProvider.addTab(
        initialUrl: initialUrl ?? '',
        initialTitle: initialTitle,
        controller: webViewController);
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
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.grey[800],
            elevation: 0,
            toolbarHeight: 60, // Flatter toolbar
            title: Stack(
              children: [
                // Framed container for controls
                Container(
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
                                    content: Text(browserProvider.isBookmarked(
                                            browserProvider.currentTab!.url)
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
                                MaterialPageRoute(
                                  builder: (context) => UrlSearchOverlay(
                                    initialUrl:
                                        browserProvider.currentTab!.url ==
                                                    'about:blank' ||
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
                                            url = 'http://$url';
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
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 8),
                            // Removed decoration to match screenshot (no inner box)
                            child: Text(
                              _urlController.text.isEmpty
                                  ? 'Auok浏览器'
                                  : (_urlController.text
                                          .endsWith('welcome.html')
                                      ? 'welcome.html'
                                      : _urlController.text),
                              style: TextStyle(
                                color: _urlController.text.isEmpty
                                    ? Colors.white70
                                    : Colors.white,
                                fontSize: 16, // Slightly larger font
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      // Refresh button
                      IconButton(
                        icon: const Icon(Icons.refresh,
                            color: Colors.white, size: 24),
                        onPressed: () {
                          browserProvider.currentTab?.controller.reload();
                        },
                      ),
                    ],
                  ),
                ),
                // Progress bar positioned at the bottom of the framed container area
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: browserProvider.currentTab != null &&
                          browserProvider.currentTab!.progress < 1.0
                      ? LinearProgressIndicator(
                          value: browserProvider.currentTab!.progress,
                          backgroundColor: Colors.transparent,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.blue),
                          minHeight: 3.0,
                        )
                      : const SizedBox(height: 3.0),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  // 处理菜单选项
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'settings', child: Text('设置')),
                  const PopupMenuItem(value: 'about', child: Text('关于')),
                ],
              ),
            ],
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
                      decoration: const BoxDecoration(
                        color: Colors.white, // Ensure background is white
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomBar(context, browserProvider),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, BrowserProvider browser) {
    return Container(
      height: 50,
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _canGoBack && browser.currentTab != null
                ? () async {
                    await browser.currentTab!.controller.goBack();
                    await _updateNavigationState();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            onPressed: _canGoForward && browser.currentTab != null
                ? () async {
                    await browser.currentTab!.controller.goForward();
                    await _updateNavigationState();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              // 显示菜单
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
                browser.currentTab!.controller
                    .loadFlutterAsset('assets/welcome.html');
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
            const Text(
              '标签页',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: browser.tabs.length,
                itemBuilder: (context, index) {
                  final tab = browser.tabs[index];
                  final isSelected = index == browser.currentIndex;
                  return ListTile(
                    title: Text(
                      tab.title,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      tab.url,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    selected: isSelected,
                    onTap: () {
                      browser.setCurrentIndex(index);
                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        browser.removeTab(index);
                        if (browser.tabs.isEmpty) {
                          Navigator.pop(context);
                          _addNewTab();
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

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
            leading: IconButton(
              icon: Icon(
                browserProvider.currentTab != null &&
                        browserProvider
                            .isBookmarked(browserProvider.currentTab!.url)
                    ? Icons.star
                    : Icons.star_border,
                color: browserProvider.currentTab != null &&
                        browserProvider
                            .isBookmarked(browserProvider.currentTab!.url)
                    ? Colors.amber
                    : Colors.white,
              ),
              onPressed: () {
                if (browserProvider.currentTab != null) {
                  final currentUrl = browserProvider.currentTab!.url;
                  final currentTitle = browserProvider.currentTab!.title;

                  // Skip bookmark for special URLs
                  if (currentUrl.startsWith('file://') ||
                      currentUrl == 'about:blank' ||
                      currentUrl.isEmpty) {
                    return;
                  }

                  final wasBookmarked =
                      browserProvider.isBookmarked(currentUrl);
                  browserProvider.toggleBookmark(currentUrl, currentTitle);

                  // Show feedback
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        wasBookmarked ? '书签已移除' : '书签已添加',
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            title: TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: '仙侣情缘',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
              onSubmitted: (value) async {
                if (browserProvider.currentTab != null &&
                    value.trim().isNotEmpty) {
                  String url = value.trim();
                  if (!url.startsWith('http://') &&
                      !url.startsWith('https://')) {
                    url = 'https://$url';
                  }

                  FocusScope.of(context).unfocus();

                  await browserProvider.currentTab!.controller
                      .loadRequest(Uri.parse(url));

                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      _updateNavigationState();
                    }
                  });
                }
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  browserProvider.currentTab?.controller.reload();
                },
              ),
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
              // WebView 区域
              Padding(
                padding: EdgeInsets.only(
                  right: browserProvider.isScriptPanelExpanded ? 100 : 0,
                ),
                child: browserProvider.tabs.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : IndexedStack(
                        index: browserProvider.currentIndex,
                        children: browserProvider.tabs
                            .map((tab) =>
                                WebViewWidget(controller: tab.controller))
                            .toList(),
                      ),
              ),

              // 右侧脚本面板（可折叠）
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                right: browserProvider.isScriptPanelExpanded ? 0 : -100,
                top: 0,
                bottom: 50, // Leave space for bottom bar
                width: 100,
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
                      builder: (context) => const GlobalSettingsDialog(),
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

              // 脚本面板切换按钮
              Positioned(
                right: browserProvider.isScriptPanelExpanded ? 100 : 0,
                top: MediaQuery.of(context).size.height / 2 - 80,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      browserProvider.toggleScriptPanel();
                    },
                    child: Container(
                      width: 24,
                      height: 60,
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
              // ZD按钮功能
            },
            child: const Text(
              'ZD',
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

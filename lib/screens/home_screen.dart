import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import '../widgets/browser_view.dart';
import '../widgets/script_panel.dart';
import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'menu_page.dart';

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  final TextEditingController _urlController = TextEditingController();
  bool _showScriptPanel = false;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    // Initial setup if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      _initTabs();
    });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      await [
        Permission.photos,
        Permission.mediaLibrary,
      ].request();
    }
  }

  Future<void> _initTabs() async {
    final browserProvider = context.read<BrowserProvider>();
    // If no tabs, add one
    if (browserProvider.tabs.isEmpty) {
      // Check if we have restored data
      if (browserProvider.restoredTabsData != null) {
        for (var tabData in browserProvider.restoredTabsData!) {
          final url = tabData['url'] as String;
          final title = tabData['title'] as String;
          await _addNewTab(initialUrl: url, initialTitle: title);
        }
        // Restore index
        if (browserProvider.restoredIndex != null) {
          browserProvider.setCurrentIndex(browserProvider.restoredIndex!);
        }
        browserProvider.clearRestoredData();
      } else {
        await _addNewTab();
      }
    }
  }

  Future<void> _addNewTab({String? initialUrl, String? initialTitle}) async {
    if (!mounted) return;

    final browserProvider = context.read<BrowserProvider>();
    final scriptProvider = context.read<ScriptProvider>();

    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            if (url.startsWith('file:///')) {
              // Handle internal pages if needed
            }
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            final title = await controller.getTitle() ?? 'New Tab';

            // Update provider
            final index = browserProvider.tabs
                .indexWhere((t) => t.controller == controller);
            if (index != -1) {
              browserProvider.updateTabInfo(index, url, title);
              browserProvider.addToHistory(url, title);
            }

            // Update navigation state
            if (!mounted) return;
            _updateNavigationState();

            // Inject script recording listener
            await controller.runJavaScript('''
                document.addEventListener('click', function(e) {
                  let text = '';
                  let type = '';
                  
                  if (e.target.closest('a')) {
                    type = '点击文字';
                    text = e.target.textContent || e.target.innerText;
                  }
                  
                  if (text.trim()) {
                    ScriptRecorder.postMessage(type + '|' + text.trim());
                  }
                });

                document.addEventListener('submit', function(e) {
                  const form = e.target;
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"]');
                  if (!submitButton) return;
                  
                  let data = {};
                  const inputs = Array.from(form.querySelectorAll('input:not([type="hidden"]):not([type="submit"]), textarea'))
                    .filter(input => {
                      const rect = input.getBoundingClientRect();
                      return rect.width > 0 && rect.height > 0;
                    });
                  
                  inputs.forEach((input, index) => {
                    if (input.value) {
                      data['输入框' + (index + 1)] = input.value;
                    }
                  });
                  
                  if (Object.keys(data).length > 0) {
                    ScriptRecorder.postMessage('输入框提交|' + JSON.stringify(data));
                  }
                });
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            String url = request.url;
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              // Handle special schemes
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
      await controller.loadRequest(Uri.parse(initialUrl));
    } else {
      await controller.loadFlutterAsset('assets/welcome.html');
    }

    await browserProvider.addTab(
        initialUrl: initialUrl ?? '', // Use empty string instead of about:blank
        initialTitle: initialTitle,
        controller: controller);
  }

  Future<void> _updateNavigationState() async {
    final browserProvider = context.read<BrowserProvider>();
    if (browserProvider.currentTab != null) {
      final canBack = await browserProvider.currentTab!.controller.canGoBack();
      final canForward =
          await browserProvider.currentTab!.controller.canGoForward();
      if (mounted) {
        setState(() {
          _canGoBack = canBack;
          _canGoForward = canForward;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _canGoBack = false;
          _canGoForward = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BrowserProvider, ScriptProvider>(
      builder: (context, browserProvider, scriptProvider, child) {
        // Update URL controller if needed
        if (browserProvider.currentTab != null) {
          final currentUrl = browserProvider.currentTab!.url;
          // Don't show file:// URLs in the address bar
          final displayUrl = currentUrl.startsWith('file://') ? '' : currentUrl;
          if (_urlController.text != displayUrl &&
              !FocusScope.of(context).hasFocus) {
            _urlController.text = displayUrl;
          }
        }

        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: CupertinoTextField(
              controller: _urlController,
              placeholder: 'Search or enter website name',
              onSubmitted: (value) async {
                if (browserProvider.currentTab != null &&
                    value.trim().isNotEmpty) {
                  String url = value.trim();
                  if (!url.startsWith('http://') &&
                      !url.startsWith('https://')) {
                    url = 'https://$url';
                  }

                  // Unfocus the text field first
                  FocusScope.of(context).unfocus();

                  // Load the URL
                  await browserProvider.currentTab!.controller
                      .loadRequest(Uri.parse(url));

                  // Update navigation state after a short delay
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      _updateNavigationState();
                    }
                  });
                }
              },
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(CupertinoIcons.search, size: 16),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Icon(browserProvider.isDarkMode
                      ? CupertinoIcons.sun_max
                      : CupertinoIcons.moon),
                  onPressed: () {
                    browserProvider.toggleDarkMode(!browserProvider.isDarkMode);
                  },
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.add),
                  onPressed: () => _addNewTab(),
                ),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    if (browserProvider.tabs.isNotEmpty)
                      Expanded(
                        child: IndexedStack(
                          index: browserProvider.currentIndex,
                          children: browserProvider.tabs.map((tab) {
                            // We need to keep the WebView alive
                            return BrowserView(tab: tab);
                          }).toList(),
                        ),
                      )
                    else
                      const Expanded(
                        child: Center(child: Text('No Tabs')),
                      ),

                    // Bottom Toolbar
                    _buildBottomBar(context, browserProvider, scriptProvider),
                  ],
                ),
                if (_showScriptPanel)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 400,
                    child: ScriptPanel(
                      onClose: () => setState(() => _showScriptPanel = false),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(
      BuildContext context, BrowserProvider browser, ScriptProvider script) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CupertinoColors.separator)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: browser.currentTab != null && _canGoBack
                ? () async {
                    await browser.currentTab!.controller.goBack();
                    _updateNavigationState();
                  }
                : null,
            child: const Icon(CupertinoIcons.back),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: browser.currentTab != null && _canGoForward
                ? () async {
                    await browser.currentTab!.controller.goForward();
                    _updateNavigationState();
                  }
                : null,
            child: const Icon(CupertinoIcons.forward),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _showScriptPanel = !_showScriptPanel;
              });
            },
            child: const Icon(CupertinoIcons.list_bullet),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              // Show tabs list
              _showTabsList(context, browser);
            },
            child: const Icon(CupertinoIcons.square_on_square),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              final url = await Navigator.push<String>(
                context,
                CupertinoPageRoute(
                  builder: (context) => MenuPage(browserProvider: browser),
                ),
              );
              if (url != null && browser.currentTab != null) {
                browser.currentTab!.controller.loadRequest(Uri.parse(url));
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    _updateNavigationState();
                  }
                });
              }
            },
            child: const Icon(CupertinoIcons.ellipsis),
          ),
        ],
      ),
    );
  }

  void _showTabsList(BuildContext context, BrowserProvider browser) {
    final isDark = browser.isDarkMode;
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 400,
        decoration: BoxDecoration(
          color: isDark ? CupertinoColors.black : CupertinoColors.white,
          border: const Border(
            top: BorderSide(color: CupertinoColors.separator),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: CupertinoColors.separator)),
              ),
              child: Text(
                'Tabs (${browser.tabs.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: browser.tabs.length,
                itemBuilder: (context, index) {
                  final tab = browser.tabs[index];
                  final isSelected = index == browser.currentIndex;
                  return Container(
                    color: isSelected
                        ? CupertinoColors.activeBlue.withOpacity(0.1)
                        : null,
                    child: ListTile(
                      title: Text(
                        tab.title,
                        style: TextStyle(
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                      ),
                      subtitle: Text(
                        tab.url,
                        style: TextStyle(
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemGrey2,
                        ),
                      ),
                      selected: isSelected,
                      onTap: () {
                        browser.setCurrentIndex(index);
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        icon: Icon(
                          CupertinoIcons.xmark,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                        onPressed: () {
                          browser.removeTab(index);
                          if (browser.tabs.isEmpty) {
                            Navigator.pop(context);
                            _addNewTab();
                          }
                        },
                      ),
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
}

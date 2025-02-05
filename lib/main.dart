import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'Auto Browser',
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.systemBlue,
        brightness: Brightness.dark,
      ),
      home: BrowserHomePage(),
    );
  }
}

class BrowserTab {
  final String id;
  final WebViewController controller;
  String title;
  String url;

  BrowserTab({
    required this.id,
    required this.controller,
    this.title = 'New Tab',
    this.url = 'about:blank',
  });
}

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final TextEditingController _urlController = TextEditingController();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _addNewTab();
  }

  void _addNewTab() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          setState(() {
            isLoading = true;
          });
        },
        onPageFinished: (url) {
          setState(() {
            isLoading = false;
          });
          _updateTabInfo(_currentIndex);
        },
      ))
      ..loadRequest(Uri.parse('https://www.google.com'));

    final newTab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      controller: controller,
    );

    setState(() {
      _tabs.add(newTab);
      _currentIndex = _tabs.length - 1;
    });
  }

  void _updateTabInfo(int index) async {
    if (index >= 0 && index < _tabs.length) {
      final tab = _tabs[index];
      final url = await tab.controller.currentUrl() ?? '';
      final title = await tab.controller.getTitle() ?? 'New Tab';
      setState(() {
        tab.url = url;
        tab.title = title;
        _urlController.text = url;
      });
    }
  }

  void _removeTab(int index) {
    if (_tabs.length > 1) {
      setState(() {
        _tabs.removeAt(index);
        if (_currentIndex >= _tabs.length) {
          _currentIndex = _tabs.length - 1;
        }
        _updateTabInfo(_currentIndex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: CupertinoTextField(
          controller: _urlController,
          placeholder: '输入网址',
          onSubmitted: (url) {
            String finalUrl = url;
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              finalUrl = 'https://$url';
            }
            _tabs[_currentIndex].controller.loadRequest(Uri.parse(finalUrl));
          },
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 网页内容
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentIndex,
                    children: _tabs
                        .map((tab) => WebViewWidget(controller: tab.controller))
                        .toList(),
                  ),
                  if (isLoading)
                    const Center(
                      child: CupertinoActivityIndicator(),
                    ),
                ],
              ),
            ),
            // 底部导航栏
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6.withOpacity(0.9),
                border: const Border(
                  top: BorderSide(
                    color: CupertinoColors.systemGrey4,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 后退按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      final controller = _tabs[_currentIndex].controller;
                      if (await controller.canGoBack()) {
                        controller.goBack();
                      }
                    },
                    child: const Icon(
                      CupertinoIcons.chevron_left,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                  // 前进按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      final controller = _tabs[_currentIndex].controller;
                      if (await controller.canGoForward()) {
                        controller.goForward();
                      }
                    },
                    child: const Icon(
                      CupertinoIcons.chevron_right,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                  // 标签切换按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      showCupertinoModalPopup(
                        context: context,
                        builder: (context) => Container(
                          height: 200,
                          color: CupertinoColors.systemBackground,
                          child: Column(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _tabs.length,
                                  itemBuilder: (context, index) {
                                    final tab = _tabs[index];
                                    return CupertinoListTile(
                                      title: Text(tab.title),
                                      subtitle: Text(tab.url),
                                      trailing: _tabs.length > 1
                                          ? CupertinoButton(
                                              padding: EdgeInsets.zero,
                                              onPressed: () => _removeTab(index),
                                              child: const Icon(
                                                CupertinoIcons.clear_circled,
                                              ),
                                            )
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _currentIndex = index;
                                        });
                                        Navigator.pop(context);
                                      },
                                    );
                                  },
                                ),
                              ),
                              CupertinoButton(
                                child: const Text('新建标签页'),
                                onPressed: () {
                                  _addNewTab();
                                  Navigator.pop(context);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey4,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        '${_tabs.length}',
                        style: const TextStyle(
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                  ),
                  // 菜单按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      showCupertinoModalPopup(
                        context: context,
                        builder: (context) => CupertinoActionSheet(
                          actions: [
                            CupertinoActionSheetAction(
                              onPressed: () {
                                _tabs[_currentIndex].controller.reload();
                                Navigator.pop(context);
                              },
                              child: const Text('刷新'),
                            ),
                            CupertinoActionSheetAction(
                              onPressed: () {
                                _addNewTab();
                                Navigator.pop(context);
                              },
                              child: const Text('新建标签页'),
                            ),
                          ],
                          cancelButton: CupertinoActionSheetAction(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                        ),
                      );
                    },
                    child: const Icon(
                      CupertinoIcons.ellipsis,
                      color: CupertinoColors.systemGrey,
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

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}

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

class Script {
  String name;
  bool isEnabled;
  String content;

  Script({
    required this.name,
    this.isEnabled = false,
    required this.content,
  });
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final TextEditingController _urlController = TextEditingController();
  bool isLoading = false;
  bool _showScriptPanel = false;
  final List<Script> _scripts = [
    Script(name: "脚本1", content: "console.log('script 1')"),
    Script(name: "脚本2", content: "console.log('script 2')"),
    Script(name: "脚本3", content: "console.log('script 3')"),
    Script(name: "脚本4", content: "console.log('script 4')"),
    Script(name: "脚本5", content: "console.log('script 5')"),
    Script(name: "脚本6", content: "console.log('script 6')"),
    Script(name: "脚本7", content: "console.log('script 7')"),
    Script(name: "脚本8", content: "console.log('script 8')"),
  ];
  int _currentScriptIndex = 0;
  int _executionDelay = 1000; // 默认延迟1000ms
  int _loopCount = 1; // 默认循环1次

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
        if (_currentIndex >= index) {
          _currentIndex = _currentIndex > 0 ? _currentIndex - 1 : 0;
        }
        _updateTabInfo(_currentIndex);
      });
      Navigator.pop(context);
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
        child: Stack(
          children: [
            Column(
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
                              height: 300,
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemBackground.darkColor,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: CupertinoColors.systemGrey.withOpacity(0.3),
                                        ),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '标签页',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _tabs.length,
                                      itemBuilder: (context, index) {
                                        final tab = _tabs[index];
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: _currentIndex == index
                                                ? CupertinoColors.systemGrey6.darkColor
                                                : null,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: CupertinoColors.systemGrey.withOpacity(0.3),
                                              ),
                                            ),
                                          ),
                                          child: CupertinoListTile(
                                            title: Text(
                                              tab.title,
                                              style: const TextStyle(
                                                color: CupertinoColors.white,
                                              ),
                                            ),
                                            subtitle: Text(
                                              tab.url,
                                              style: TextStyle(
                                                color: CupertinoColors.systemGrey.color,
                                                fontSize: 12,
                                              ),
                                            ),
                                            trailing: _tabs.length > 1
                                                ? CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () => _removeTab(index),
                                                    child: const Icon(
                                                      CupertinoIcons.clear_circled_solid,
                                                      color: CupertinoColors.systemGrey,
                                                    ),
                                                  )
                                                : null,
                                            onTap: () {
                                              setState(() {
                                                _currentIndex = index;
                                              });
                                              Navigator.pop(context);
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: CupertinoColors.systemGrey.withOpacity(0.3),
                                        ),
                                      ),
                                    ),
                                    child: CupertinoButton(
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            CupertinoIcons.add,
                                            color: CupertinoColors.activeBlue,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '新建标签页',
                                            style: TextStyle(
                                              color: CupertinoColors.activeBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      onPressed: () {
                                        _addNewTab();
                                        Navigator.pop(context);
                                      },
                                    ),
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
            // 脚本管理器面板
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              right: _showScriptPanel ? 0 : -300,
              top: 0,
              bottom: 0,
              width: 300,
              child: Container(
                color: CupertinoColors.black.withOpacity(0.9),
                child: Column(
                  children: [
                    // 收起按钮
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: () {
                          setState(() {
                            _showScriptPanel = false;
                          });
                        },
                        child: const Icon(
                          CupertinoIcons.right_chevron,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                    // 全局设置
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '全局设置',
                            style: TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                '执行延迟(ms):',
                                style: TextStyle(color: CupertinoColors.white),
                              ),
                              Expanded(
                                child: CupertinoTextField(
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: CupertinoColors.white),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  onChanged: (value) {
                                    _executionDelay = int.tryParse(value) ?? 1000;
                                  },
                                  controller: TextEditingController(
                                      text: _executionDelay.toString()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                '循环次数:',
                                style: TextStyle(color: CupertinoColors.white),
                              ),
                              Expanded(
                                child: CupertinoTextField(
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: CupertinoColors.white),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  onChanged: (value) {
                                    _loopCount = int.tryParse(value) ?? 1;
                                  },
                                  controller: TextEditingController(
                                      text: _loopCount.toString()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: CupertinoColors.white),
                    // 脚本进度
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        '脚本列表: $_currentScriptIndex/${_scripts.length}',
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Divider(color: CupertinoColors.white),
                    // 脚本列表
                    Expanded(
                      child: ListView.separated(
                        itemCount: _scripts.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: CupertinoColors.white),
                        itemBuilder: (context, index) {
                          final script = _scripts[index];
                          return ListTile(
                            title: Text(
                              script.name,
                              style: const TextStyle(color: CupertinoColors.white),
                            ),
                            trailing: CupertinoSwitch(
                              value: script.isEnabled,
                              onChanged: (value) {
                                setState(() {
                                  script.isEnabled = value;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 展开按钮
            if (!_showScriptPanel)
              Positioned(
                right: 0,
                top: MediaQuery.of(context).size.height / 2 - 25,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showScriptPanel = true;
                    });
                  },
                  child: Container(
                    width: 25,
                    height: 50,
                    decoration: const BoxDecoration(
                      color: CupertinoColors.black,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(8),
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.left_chevron,
                      color: CupertinoColors.white,
                      size: 20,
                    ),
                  ),
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

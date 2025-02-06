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
  String type;      // 脚本类型
  String? content;  // 点击文字内容
  bool isEnabled;
  bool exactMatch;  // 完全匹配点击

  Script({
    required this.type,
    this.content,
    this.isEnabled = false,
    this.exactMatch = true,
  });

  // 转换为 JSON 字符串
  String toJson(int executionDelay, int loopCount) {
    if (type == "全局变量") {
      return '{"脚本类型":"全局变量","执行延迟":$executionDelay,"时间单位":"毫秒","循环次数":$loopCount}';
    } else {
      return '{"脚本类型":"点击文字","点击文字":"$content","完全匹配点击":"${exactMatch ? "是" : "否"}"}';
    }
  }
}

class _BrowserHomePageState extends State<BrowserHomePage> with WidgetsBindingObserver {
  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final TextEditingController _urlController = TextEditingController();
  bool isLoading = false;
  bool _showScriptPanel = false;
  final List<Script> _scripts = [];
  int _executionDelay = 1000; // 默认延迟1000ms
  int _loopCount = 1; // 默认循环1次
  bool _isRecording = false;  // 录制状态
  bool _isExecuting = false;  // 执行状态

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBrowser();
  }

  Future<void> _initBrowser() async {
    try {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 100));
      _addNewTab();
    } catch (e) {
      debugPrint('Init browser error: $e');
    }
  }

  void _addNewTab() {
    if (!mounted) return;
    
    try {
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'ScriptRecorder',
          onMessageReceived: (JavaScriptMessage message) {
            if (mounted) {
              _recordClick(message.message);
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              if (!mounted) return;
              setState(() {
                isLoading = true;
              });
            },
            onPageFinished: (String url) async {
              if (!mounted) return;
              setState(() {
                isLoading = false;
              });
              _updateTabInfo(_currentIndex);
              
              await controller.runJavaScript('''
                document.addEventListener('click', function(e) {
                  let text = '';
                  if (e.target.tagName === 'A') {
                    text = e.target.textContent || e.target.innerText;
                  } else {
                    text = e.target.textContent || e.target.innerText;
                  }
                  if (text.trim()) {
                    ScriptRecorder.postMessage(text.trim());
                  }
                });
              ''');
            },
            onNavigationRequest: (NavigationRequest request) {
              // 处理导航请求
              String url = request.url;
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }
              // 确保URL有效
              try {
                Uri.parse(url);
                return NavigationDecision.navigate;
              } catch (e) {
                return NavigationDecision.prevent;
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('Web resource error: ${error.description}');
              if (mounted) {
                setState(() {
                  isLoading = false;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse('https://www.google.com')); // 使用更稳定的默认页面

      setState(() {
        _tabs.add(BrowserTab(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          controller: controller,
        ));
        _currentIndex = _tabs.length - 1;
      });
    } catch (e) {
      debugPrint('Add tab error: $e');
    }
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
        // 清理要移除的标签页资源
        final tab = _tabs[index];
        tab.controller.clearCache();
        tab.controller.clearLocalStorage();
        
        _tabs.removeAt(index);
        if (_currentIndex >= index) {
          _currentIndex = _currentIndex > 0 ? _currentIndex - 1 : 0;
        }
        _updateTabInfo(_currentIndex);
      });
      Navigator.pop(context);
    }
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _showScriptPanel = false;  // 收起脚本管理器
    });
  }

  void _stopRecording() {
    setState(() {
      _isRecording = false;
    });
  }

  void _recordClick(String text) {
    if (_isRecording && mounted) {
      final script = Script(
        type: "点击文字",
        content: text,
        isEnabled: true,
        exactMatch: true,
      );
      
      setState(() {
        _scripts.add(script);
        // 强制脚本列表刷新
        if (_showScriptPanel) {
          _showScriptPanel = false;
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              setState(() {
                _showScriptPanel = true;
              });
            }
          });
        }
      });
    }
  }

  // 添加导出脚本方法
  String exportScript() {
    final List<String> lines = [];
    
    // 添加全局信息
    final globalScript = Script(
      type: "全局变量",
      isEnabled: true,
    );
    lines.add(globalScript.toJson(_executionDelay, _loopCount));
    
    // 添加所有已启用的脚本
    for (var script in _scripts) {
      if (script.isEnabled) {
        lines.add(script.toJson(_executionDelay, _loopCount));
      }
    }
    
    return lines.join('\n');
  }

  void _addScript() {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        String content = '';
        return CupertinoAlertDialog(
          title: const Text('添加脚本'),
          content: Column(
            children: [
              const SizedBox(height: 8),
              CupertinoTextField(
                placeholder: '输入要点击的文字',
                onChanged: (value) => content = value,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () {
                if (content.isNotEmpty) {
                  setState(() {
                    _scripts.add(Script(
                      type: "点击文字",
                      content: content,
                      isEnabled: true,
                    ));
                  });
                }
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // 添加编辑脚本方法
  void _editScript(int index) {
    final script = _scripts[index];
    showCupertinoDialog(
      context: context,
      builder: (context) {
        String content = script.content ?? '';
        return CupertinoAlertDialog(
          title: const Text('编辑脚本'),
          content: Column(
            children: [
              const SizedBox(height: 8),
              CupertinoTextField(
                placeholder: '输入要点击的文字',
                onChanged: (value) => content = value,
                controller: TextEditingController(text: content),
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () {
                if (content.isNotEmpty) {
                  setState(() {
                    _scripts[index].content = content;
                  });
                }
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // 修改脚本进度显示
  Widget _buildScriptProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '脚本列表: ${_scripts.length}',  // 只显示总数
        style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 16,
        ),
      ),
    );
  }

  Future<void> _executeScripts() async {
    if (_scripts.isEmpty) return;
    
    setState(() {
      _isExecuting = true;
    });

    try {
      do {
        for (var script in _scripts) {
          if (!script.isEnabled) continue;
          
          if (script.type == "点击文字") {
            // 等待执行延迟
            await Future.delayed(Duration(milliseconds: _executionDelay));
            
            await _tabs[_currentIndex].controller.runJavaScript('''
              (function() {
                const elements = document.querySelectorAll('a');
                for (const element of elements) {
                  if (element.textContent.trim() === "${script.content}") {
                    element.click();
                    return;
                  }
                }
              })();
            ''');
          }
        }
        
        if (_loopCount > 0) _loopCount--;
      } while (_loopCount == 0 || _loopCount > 0);  // 0表示无限循环
      
    } finally {
      setState(() {
        _isExecuting = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _cleanupWebViews();
        break;
      case AppLifecycleState.resumed:
        _initBrowser();
        break;
      default:
        break;
    }
  }

  void _cleanupWebViews() {
    try {
      for (var tab in _tabs) {
        tab.controller.clearCache();
      }
      if (mounted) {
        setState(() {
          _tabs.clear();
          _currentIndex = 0;
        });
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
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
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                _tabs[_currentIndex].controller.reload();
              },
              child: const Icon(
                CupertinoIcons.refresh,
                color: CupertinoColors.systemGrey,
                size: 22,
              ),
            ),
          ],
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
                    color: CupertinoColors.systemGrey6.withAlpha(230),
                    border: const Border(
                      top: BorderSide(
                        color: Color(0x4D8E8E93),  // 使用固定的 ARGB 值
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
                                color: const Color.fromARGB(255, 28, 28, 30),  // 使用固定的深色值
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
                                          color: CupertinoColors.systemGrey.withAlpha(77),
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
                                                ? const Color.fromARGB(255, 44, 44, 46)  // 固定深色值
                                                : null,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: CupertinoColors.systemGrey.withAlpha(77),
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
                                                color: const Color(0xFF8E8E93),  // 使用固定的灰色值
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
                                          color: CupertinoColors.systemGrey.withAlpha(77),
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
              curve: Curves.easeInOut,
              right: _showScriptPanel ? 0 : -MediaQuery.of(context).size.width / 2,
              width: MediaQuery.of(context).size.width / 2,
              top: 0,
              bottom: 50,  // 与底部栏对齐
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    color: CupertinoColors.black.withAlpha(230),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        // 全局设置
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),  // 缩小padding
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,  // 居中对齐
                            children: [
                              const Text(
                                '全局设置',
                                style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 14,  // 调小字体
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),  // 减小间距
                              Row(
                                children: [
                                  const Text(
                                    '执行延迟:',
                                    style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 12,  // 调小字体
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: CupertinoTextField(
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(
                                        color: CupertinoColors.white,
                                        fontSize: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.systemGrey6,
                                        borderRadius: BorderRadius.circular(4),  // 调小圆角
                                      ),
                                      onChanged: (value) {
                                        _executionDelay = int.tryParse(value) ?? 1000;
                                      },
                                      controller: TextEditingController(
                                          text: _executionDelay.toString()),
                                    ),
                                  ),
                                  const Text(
                                    'ms',
                                    style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Text(
                                    '循环次数:',
                                    style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: CupertinoTextField(
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(
                                        color: CupertinoColors.white,
                                        fontSize: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.systemGrey6,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      onChanged: (value) {
                                        _loopCount = int.tryParse(value) ?? 1;
                                      },
                                      controller: TextEditingController(
                                          text: _loopCount.toString()),
                                    ),
                                  ),
                                  const Text(
                                    '次',
                                    style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: CupertinoColors.white),
                        // 脚本进度
                        _buildScriptProgress(),
                        const Divider(color: CupertinoColors.white),
                        // 脚本列表区域
                        Expanded(
                          child: _scripts.isEmpty
                              // 空列表时显示两个按钮
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CupertinoButton(
                                      color: CupertinoColors.systemBlue,
                                      onPressed: _startRecording,
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            CupertinoIcons.smallcircle_fill_circle_fill,
                                            color: CupertinoColors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '录制脚本',
                                            style: TextStyle(color: CupertinoColors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    CupertinoButton(
                                      color: CupertinoColors.systemGreen,
                                      onPressed: _addScript,
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            CupertinoIcons.plus_circle_fill,
                                            color: CupertinoColors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '添加脚本',
                                            style: TextStyle(color: CupertinoColors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              // 有脚本时显示列表和添加按钮
                              : ListView.builder(
                                  itemCount: _scripts.length + 1, // +1 为添加按钮
                                  itemBuilder: (context, index) {
                                    if (index == _scripts.length) {
                                      // 最后一项显示添加按钮
                                      return Column(
                                        children: [
                                          const Divider(color: CupertinoColors.white),
                                          CupertinoButton(
                                            padding: const EdgeInsets.all(16),
                                            onPressed: _addScript,
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  CupertinoIcons.plus_circle_fill,
                                                  color: CupertinoColors.systemGreen,
                                                  size: 16,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  '添加脚本',
                                                  style: TextStyle(
                                                    color: CupertinoColors.systemGreen,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    // 显示脚本项
                                    final script = _scripts[index];
                                    return GestureDetector(
                                      onTap: () => _editScript(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemGrey6.withAlpha(30),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Stack(
                                          children: [
                                            Row(
                                              children: [
                                                // 左侧脚本类型
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: CupertinoColors.systemBlue.withAlpha(50),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    script.type,
                                                    style: const TextStyle(
                                                      color: CupertinoColors.white,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                // 右侧脚本内容
                                                Expanded(
                                                  child: Text(
                                                    script.content ?? '',
                                                    style: const TextStyle(
                                                      color: CupertinoColors.white,
                                                      fontSize: 14,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 40),  // 为角标预留空间
                                              ],
                                            ),
                                            // 右上角角标
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: CupertinoColors.systemGrey.withAlpha(100),
                                                  borderRadius: const BorderRadius.only(
                                                    topRight: Radius.circular(8),
                                                    bottomLeft: Radius.circular(8),
                                                  ),
                                                ),
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    color: CupertinoColors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 控制按钮放在外层 Stack 中，与脚本管理器面板平级
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              right: _showScriptPanel 
                  ? MediaQuery.of(context).size.width / 2  // 修改位置，确保在面板外
                  : 0,
              bottom: MediaQuery.of(context).size.height / 8,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showScriptPanel = !_showScriptPanel;
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
                  child: Icon(
                    _showScriptPanel 
                        ? CupertinoIcons.right_chevron
                        : CupertinoIcons.left_chevron,
                    color: CupertinoColors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // 在外层 Stack 中添加录制提示
            if (_isRecording)
              Positioned(
                left: 16,
                bottom: 66,  // 在底部导航栏上方
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.withAlpha(230),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.smallcircle_fill_circle_fill,
                        color: CupertinoColors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '录制中',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _stopRecording,
                        child: const Icon(
                          CupertinoIcons.clear_circled_solid,
                          color: CupertinoColors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 添加底部操作按钮
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: MediaQuery.of(context).size.width / 2,
                height: 50,
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withAlpha(230),
                  border: const Border(
                    top: BorderSide(color: Color(0x4D8E8E93)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 执行按钮
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _isExecuting ? null : _executeScripts,
                      child: Text(
                        '执行',
                        style: TextStyle(
                          color: _isExecuting 
                              ? CupertinoColors.systemGrey 
                              : CupertinoColors.systemBlue,
                        ),
                      ),
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 20,
                      color: const Color(0x4D8E8E93),
                    ),
                    // 读取按钮
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _isExecuting ? null : () {
                        // TODO: 实现读取功能
                      },
                      child: Text(
                        '读取',
                        style: TextStyle(
                          color: _isExecuting 
                              ? CupertinoColors.systemGrey 
                              : CupertinoColors.white,
                        ),
                      ),
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 20,
                      color: const Color(0x4D8E8E93),
                    ),
                    // 清除按钮
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _isExecuting ? null : () {
                        setState(() {
                          _scripts.clear();
                        });
                      },
                      child: Text(
                        '清除',
                        style: TextStyle(
                          color: _isExecuting 
                              ? CupertinoColors.systemGrey 
                              : CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                  ],
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
    _cleanupWebViews();
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }
}

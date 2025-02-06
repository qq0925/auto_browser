import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';  // 添加分享功能的包
import 'package:path_provider/path_provider.dart';  // 添加这行导入

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

class Bookmark {
  final String title;
  final String url;
  final DateTime createdAt;

  Bookmark({
    required this.title,
    required this.url,
    required this.createdAt,
  });
}

class HistoryItem {
  final String title;
  final String url;
  final DateTime visitedAt;

  HistoryItem({
    required this.title,
    required this.url,
    required this.visitedAt,
  });
}

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class Script {
  String type;      // 脚本类型: 点击文字、点击链接、输入提交、刷新网页、进入网址、网页后退、网页前进
  String? content;  // 内容（URL、文字等）
  bool isEnabled;
  bool exactMatch;

  Script({
    required this.type,
    this.content,
    this.isEnabled = false,
    this.exactMatch = true,
  });

  // 修改 toJson 方法
  String toJson(int executionDelay, int loopCount) {
    if (type == "全局变量") {
      return '{"脚本类型":"全局变量","执行延迟":$executionDelay,"时间单位":"毫秒","循环次数":$loopCount}';
    } else {
      return '{"脚本类型":"$type","内容":"$content","完全匹配":"${exactMatch ? "是" : "否"}"}';
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
  int _originalLoopCount = 1;  // 原始循环次数
  int _remainingLoopCount = 1; // 剩余循环次数
  bool _isRecording = false;  // 录制状态
  bool _isExecuting = false;  // 执行状态
  bool _showMenuPanel = false; // 菜单管理器状态
  final List<Bookmark> _bookmarks = [];
  final List<HistoryItem> _history = [];
  double _loadingProgress = 0;  // 加载进度
  bool _isPaused = false;  // 暂停状态
  int _successCount = 0;   // 成功次数
  int _failureCount = 0;   // 失败次数

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
              final data = message.message.split('|');
              final type = data[0];
              final content = data[1];
              _recordAction(type, content);
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              if (!mounted) return;
              setState(() {
                isLoading = true;
                _loadingProgress = 0;
              });
            },
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _loadingProgress = progress / 100;
              });
            },
            onPageFinished: (String url) async {
              if (!mounted) return;
              final title = await controller.getTitle() ?? 'New Tab';
              setState(() {
                isLoading = false;
                _loadingProgress = 1;
                
                // 添加空值检查
                if (mounted && _tabs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _tabs.length) {
                  _history.insert(0, HistoryItem(
                    title: title,
                    url: url,
                    visitedAt: DateTime.now(),
                  ));
                }
              });
              _updateTabInfo(_currentIndex);
              
              await controller.runJavaScript('''
                document.addEventListener('click', function(e) {
                  let text = '';
                  let type = '';
                  
                  if (e.target.tagName === 'A') {
                    type = '点击链接';
                    text = e.target.textContent || e.target.innerText;
                  } else {
                    type = '点击文字';
                    text = e.target.textContent || e.target.innerText;
                  }
                  
                  if (text.trim()) {
                    ScriptRecorder.postMessage(type + '|' + text.trim());
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

  void _recordAction(String type, String content) {
    if (_isRecording && mounted) {
      setState(() {
        _scripts.add(Script(
          type: type,
          content: content,
          isEnabled: true,
        ));
        
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
    lines.add(globalScript.toJson(_executionDelay, _originalLoopCount));
    
    // 添加所有已启用的脚本
    for (var script in _scripts) {
      if (script.isEnabled) {
        lines.add(script.toJson(_executionDelay, _originalLoopCount));
      }
    }
    
    return lines.join('\n');
  }

  void _addScript() {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        String type = "点击文字";
        String content = '';
        return CupertinoAlertDialog(
          title: const Text('添加脚本'),
          content: Column(
            children: [
              const SizedBox(height: 8),
              // 脚本类型选择
              Row(
                children: [
                  const Text('脚本类型'),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Row(
                      children: [
                        Text(type),
                        const Text(' 简易'),
                        const Icon(CupertinoIcons.question_circle, size: 16),
                      ],
                    ),
                    onPressed: () {
                      // TODO: 显示类型选择
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 点击文字输入
              CupertinoTextField(
                placeholder: '点击文字',
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
                      type: type,
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
        String type = script.type;
        String content = script.content ?? '';
        return CupertinoAlertDialog(
          title: const Text('编辑脚本'),
          content: Column(
            children: [
              const SizedBox(height: 8),
              // 脚本类型显示
              Row(
                children: [
                  const Text('脚本类型'),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Row(
                      children: [
                        Text(type),
                        const Text(' 简易'),
                        const Icon(CupertinoIcons.question_circle, size: 16),
                      ],
                    ),
                    onPressed: () {
                      // TODO: 显示类型选择
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 点击文字输入
              CupertinoTextField(
                placeholder: '点击文字',
                controller: TextEditingController(text: content),
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
                    _scripts[index].type = type;
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

  // 修改循环次数设置
  void _setLoopCount(String value) {
    final count = int.tryParse(value) ?? 1;
    setState(() {
      _originalLoopCount = count;
      _remainingLoopCount = count;
    });
  }

  // 修改执行脚本的逻辑
  Future<void> _executeScripts() async {
    if (_scripts.isEmpty) return;
    
    setState(() {
      _isExecuting = true;
      _isPaused = false;
      _remainingLoopCount = _originalLoopCount;
      _successCount = 0;
      _failureCount = 0;
    });

    try {
      do {
        for (var script in _scripts) {
          while (_isPaused) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (!_isExecuting) return;  // 检查是否停止执行
          }
          
          if (!_isExecuting) return;  // 检查是否停止执行
          if (!script.isEnabled) continue;
          
          try {
            switch (script.type) {
              case "点击文字":
                await _executeClickText(script.content ?? '');
                break;
              case "点击链接":
                await _executeClickLink(script.content ?? '');
                break;
              case "输入提交":
                await _executeFormSubmit(script.content ?? '');
                break;
              case "刷新网页":
                await _tabs[_currentIndex].controller.reload();
                break;
              case "进入网址":
                await _tabs[_currentIndex].controller.loadRequest(Uri.parse(script.content ?? ''));
                break;
              case "网页后退":
                await _tabs[_currentIndex].controller.goBack();
                break;
              case "网页前进":
                await _tabs[_currentIndex].controller.goForward();
                break;
            }
            setState(() => _successCount++);
          } catch (e) {
            setState(() => _failureCount++);
          }
          await Future.delayed(Duration(milliseconds: _executionDelay));
        }
        
        if (_originalLoopCount > 0) {
          _remainingLoopCount--;
        }
      } while (_originalLoopCount == 0 || _remainingLoopCount > 0);
      
    } finally {
      setState(() {
        _isExecuting = false;
        _isPaused = false;
      });
    }
  }

  // 添加具体的执行方法
  Future<void> _executeClickText(String text) async {
    final result = await _tabs[_currentIndex].controller.runJavaScriptReturningResult('''
      (function() {
        const elements = document.querySelectorAll('*');
        for (const element of elements) {
          if (element.textContent.trim() === "$text") {
            element.click();
            return true;
          }
        }
        return false;
      })();
    ''');
    if (result.toString() != 'true') throw Exception('Text not found');
  }

  Future<void> _executeClickLink(String url) async {
    final result = await _tabs[_currentIndex].controller.runJavaScriptReturningResult('''
      (function() {
        const links = document.querySelectorAll('a');
        for (const link of links) {
          if (link.href === "$url") {
            link.click();
            return true;
          }
        }
        return false;
      })();
    ''');
    if (result.toString() != 'true') throw Exception('Link not found');
  }

  Future<void> _executeFormSubmit(String formData) async {
    final result = await _tabs[_currentIndex].controller.runJavaScriptReturningResult('''
      (function() {
        try {
          const data = JSON.parse('$formData');
          for (let [key, value] of Object.entries(data)) {
            const input = document.querySelector(`[name="\${key}"]`);
            if (input) input.value = value;
          }
          const form = document.querySelector('form');
          if (form) {
            form.submit();
            return true;
          }
          return false;
        } catch (e) {
          return false;
        }
      })();
    ''');
    if (result.toString() != 'true') throw Exception('Form submit failed');
  }

  // 修改菜单管理器样式
  Widget _buildMenuPanel() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      right: 16,  // 右边留出间距
      left: 16,   // 左边留出间距
      bottom: _showMenuPanel ? 50 : -200,
      height: 200,
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.black.withAlpha(230),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: CupertinoColors.systemGrey4.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            _buildMenuItem(
              icon: CupertinoIcons.bookmark,
              title: '书签',
              onTap: () {
                setState(() => _showMenuPanel = false);
                _showBookmarks();
              },
            ),
            _buildMenuItem(
              icon: CupertinoIcons.clock,
              title: '历史',
              onTap: () {
                setState(() => _showMenuPanel = false);
                _showHistory();
              },
            ),
            _buildMenuItem(
              icon: CupertinoIcons.refresh,
              title: '刷新页面',
              onTap: () {
                _tabs[_currentIndex].controller.reload();
                setState(() => _showMenuPanel = false);
              },
            ),
            _buildMenuItem(
              icon: CupertinoIcons.settings,
              title: '设置',
              onTap: () {
                // TODO: 实现设置功能
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: CupertinoColors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 修改书签管理界面
  void _showBookmarks() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(  // 使用 StatefulBuilder
        builder: (context, setState) => Container(
          height: 400,
          decoration: BoxDecoration(
            color: CupertinoColors.black.withAlpha(230),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '书签',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        final url = await _tabs[_currentIndex].controller.currentUrl() ?? '';
                        final title = await _tabs[_currentIndex].controller.getTitle() ?? 'New Bookmark';
                        setState(() {  // 使用 StatefulBuilder 的 setState
                          _bookmarks.add(Bookmark(
                            title: title,
                            url: url,
                            createdAt: DateTime.now(),
                          ));
                        });
                        // 同时更新外层状态
                        this.setState(() {});
                      },
                      child: const Icon(
                        CupertinoIcons.add_circled_solid,
                        color: CupertinoColors.systemBlue,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = _bookmarks[index];
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: CupertinoColors.systemGrey.withOpacity(0.2),
                          ),
                        ),
                      ),
                      child: CupertinoListTile(
                        title: Text(
                          bookmark.title,
                          style: const TextStyle(color: CupertinoColors.white),
                        ),
                        subtitle: Text(
                          bookmark.url,
                          style: const TextStyle(color: CupertinoColors.systemGrey),
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setState(() {
                              _bookmarks.removeAt(index);
                            });
                          },
                          child: const Icon(
                            CupertinoIcons.delete,
                            color: CupertinoColors.systemRed,
                          ),
                        ),
                        onTap: () {
                          _tabs[_currentIndex].controller.loadRequest(
                            Uri.parse(bookmark.url),
                          );
                          Navigator.pop(context);
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
    );
  }

  void _showHistory() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 400,
        decoration: BoxDecoration(
          color: CupertinoColors.black.withAlpha(230),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '历史记录',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      _clearHistory();
                      Navigator.pop(context);
                    },
                    child: const Text('清除'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final item = _history[index];
                  return CupertinoListTile(
                    title: Text(
                      item.title,
                      style: const TextStyle(color: CupertinoColors.white),
                    ),
                    subtitle: Text(
                      item.url,
                      style: const TextStyle(color: CupertinoColors.systemGrey),
                    ),
                    trailing: Text(
                      _formatTime(item.visitedAt),
                      style: const TextStyle(color: CupertinoColors.systemGrey),
                    ),
                    onTap: () {
                      _tabs[_currentIndex].controller.loadRequest(
                        Uri.parse(item.url),
                      );
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
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
                  color: const Color(0xFF1C1C1E),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,  // 均匀分布
                    children: [
                      // 后退按钮
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          if (_currentIndex > 0) {
                            _tabs[_currentIndex].controller.goBack();
                            _recordAction("网页后退", "");
                          }
                        },
                        child: const Icon(
                          CupertinoIcons.back,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                      // 前进按钮
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          if (_currentIndex < _tabs.length - 1) {
                            _tabs[_currentIndex].controller.goForward();
                            _recordAction("网页前进", "");
                          }
                        },
                        child: const Icon(
                          CupertinoIcons.forward,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                      // 菜单按钮
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() => _showMenuPanel = !_showMenuPanel);
                        },
                        child: Icon(
                          _showMenuPanel ? CupertinoIcons.line_horizontal_3 : CupertinoIcons.line_horizontal_3,
                          color: _showMenuPanel ? CupertinoColors.activeBlue : CupertinoColors.systemGrey,
                        ),
                      ),
                      // 标签页切换按钮
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          showCupertinoModalPopup(
                            context: context,
                            builder: (context) => Container(
                              height: 200,
                              color: const Color(0xFF1C1C1E),
                              child: ListView.builder(
                                itemCount: _tabs.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == _tabs.length) {
                                    return CupertinoButton(
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(CupertinoIcons.add, color: CupertinoColors.systemBlue),
                                          SizedBox(width: 8),
                                          Text('新建标签页'),
                                        ],
                                      ),
                                      onPressed: () {
                                        _addNewTab();
                                        Navigator.pop(context);
                                      },
                                    );
                                  }
                                  final tab = _tabs[index];
                                  return CupertinoButton(
                                    onPressed: () {
                                      setState(() => _currentIndex = index);
                                      Navigator.pop(context);
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          CupertinoIcons.globe,
                                          color: _currentIndex == index
                                              ? CupertinoColors.activeBlue
                                              : CupertinoColors.systemGrey,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            tab.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _currentIndex == index
                                                  ? CupertinoColors.activeBlue
                                                  : CupertinoColors.white,
                                            ),
                                          ),
                                        ),
                                        if (_tabs.length > 1)  // 只有多个标签页时显示删除按钮
                                          CupertinoButton(
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _removeTab(index),
                                            child: const Icon(
                                              CupertinoIcons.clear_circled_solid,
                                              color: CupertinoColors.systemGrey,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                        child: const Icon(
                          CupertinoIcons.square_stack,
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
                                      onChanged: _setLoopCount,
                                      controller: TextEditingController(
                                          text: _originalLoopCount.toString()),
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
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),  // 减小内边距
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemGrey6.withAlpha(30),
                                          borderRadius: BorderRadius.circular(6),  // 减小圆角
                                        ),
                                        child: Stack(
                                          children: [
                                            Row(
                                              children: [
                                                // 左侧脚本类型
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),  // 减小内边距
                                                  decoration: BoxDecoration(
                                                    color: CupertinoColors.systemBlue.withAlpha(50),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    script.type,
                                                    style: const TextStyle(
                                                      color: CupertinoColors.white,
                                                      fontSize: 12,  // 减小字体
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),  // 减小间距
                                                // 右侧脚本内容
                                                Expanded(
                                                  child: Text(
                                                    script.content ?? '',
                                                    style: const TextStyle(
                                                      color: CupertinoColors.white,
                                                      fontSize: 12,  // 减小字体
                                                    ),
                                                    maxLines: 1,  // 限制为单行
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 24),  // 减小角标预留空间
                                              ],
                                            ),
                                            // 右上角角标
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),  // 减小内边距
                                                decoration: BoxDecoration(
                                                  color: CupertinoColors.systemGrey.withAlpha(100),
                                                  borderRadius: const BorderRadius.only(
                                                    topRight: Radius.circular(6),
                                                    bottomLeft: Radius.circular(6),
                                                  ),
                                                ),
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    color: CupertinoColors.white,
                                                    fontSize: 10,  // 减小字体
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
                        // 添加执行功能区
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: CupertinoColors.black,
                            border: const Border(
                              top: BorderSide(color: Color(0x4D8E8E93)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (_isExecuting)
                                Row(
                                  children: [
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        setState(() => _isPaused = !_isPaused);
                                      },
                                      child: Icon(
                                        _isPaused 
                                            ? CupertinoIcons.play_fill
                                            : CupertinoIcons.pause_fill,
                                        color: CupertinoColors.systemBlue,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        setState(() {
                                          _isExecuting = false;
                                          _isPaused = false;
                                        });
                                      },
                                      child: const Icon(
                                        CupertinoIcons.stop_fill,
                                        color: CupertinoColors.systemRed,
                                        size: 20,
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '成功: $_successCount',
                                          style: const TextStyle(
                                            color: CupertinoColors.systemGreen,
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          '失败: $_failureCount',
                                          style: const TextStyle(
                                            color: CupertinoColors.systemRed,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _executeScripts,
                                      child: const Icon(
                                        CupertinoIcons.play_fill,
                                        color: CupertinoColors.systemBlue,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _exportScripts,
                                      child: const Icon(
                                        CupertinoIcons.arrow_down_doc_fill,
                                        color: CupertinoColors.white,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _importScripts,
                                      child: const Icon(
                                        CupertinoIcons.doc_text_fill,
                                        color: CupertinoColors.white,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        setState(() => _scripts.clear());
                                      },
                                      child: const Icon(
                                        CupertinoIcons.clear_fill,
                                        color: CupertinoColors.systemRed,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
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
                    _showScriptPanel ? CupertinoIcons.right_chevron : CupertinoIcons.left_chevron,
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
            // 添加菜单管理器
            if (_showMenuPanel) _buildMenuPanel(),
            // 在 WebViewWidget 下方添加进度条
            if (isLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: CupertinoColors.systemGrey6,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    CupertinoColors.activeBlue,
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

  // 修改导出方法
  void _exportScripts() async {
    try {
      final content = exportScript();
      
      if (Platform.isIOS) {
        // 使用 Share.share 来分享/保存文件内容
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/script.zds');
        await file.writeAsString(content);
        
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: '导出脚本',
        );
      } else {
        // Android 上使用 FilePicker
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '保存脚本',
          fileName: 'script.zds',
          allowedExtensions: ['zds'],
          type: FileType.custom,
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(content);
          
          if (mounted) {
            showCupertinoDialog(
              context: context,
              builder: (context) => CupertinoAlertDialog(
                title: const Text('导出成功'),
                content: Text('脚本已保存到：$outputFile'),
                actions: [
                  CupertinoDialogAction(
                    child: const Text('确定'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('导出失败'),
            content: Text('错误信息：$e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    }
  }

  // 添加读取方法
  void _importScripts() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zds'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final lines = content.split('\n');
        
        if (lines.isEmpty) throw Exception('文件为空');
        
        // 解析全局配置
        final globalConfig = lines.first;
        // 使用你的 JSON 解析逻辑
        // 示例：从 JSON 中提取延迟和循环次数
        if (globalConfig.contains('"执行延迟"')) {
          final match = RegExp(r'"执行延迟":(\d+)').firstMatch(globalConfig);
          if (match != null) {
            _executionDelay = int.parse(match.group(1)!);
          }
        }
        if (globalConfig.contains('"循环次数"')) {
          final match = RegExp(r'"循环次数":(\d+)').firstMatch(globalConfig);
          if (match != null) {
            _originalLoopCount = int.parse(match.group(1)!);
            _remainingLoopCount = _originalLoopCount;
          }
        }

        // 解析脚本
        setState(() {
          _scripts.clear();
          for (var i = 1; i < lines.length; i++) {
            final line = lines[i];
            if (line.isEmpty) continue;
            
            // 从 JSON 中提取脚本信息
            final typeMatch = RegExp(r'"脚本类型":"([^"]+)"').firstMatch(line);
            final contentMatch = RegExp(r'"内容":"([^"]+)"').firstMatch(line);
            
            if (typeMatch != null) {
              _scripts.add(Script(
                type: typeMatch.group(1)!,
                content: contentMatch?.group(1),
                isEnabled: true,
              ));
            }
          }
        });

        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('导入成功'),
              content: Text('已导入 ${_scripts.length} 个脚本'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('确定'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('导入失败'),
            content: Text('错误信息：$e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    }
  }

  // 修改清除历史记录的方法
  void _clearHistory() {
    setState(() {
      _history.clear();
    });
    // 可选：保存当前标签页的信息作为最新历史
    if (_tabs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _tabs.length) {
      _tabs[_currentIndex].controller.getTitle().then((title) {
        _tabs[_currentIndex].controller.currentUrl().then((url) {
          if (mounted && title != null && url != null) {
            setState(() {
              _history.add(HistoryItem(
                title: title,
                url: url,
                visitedAt: DateTime.now(),
              ));
            });
          }
        });
      });
    }
  }
}

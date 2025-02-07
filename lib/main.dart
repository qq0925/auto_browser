import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';  // 添加分享功能的包
import 'package:path_provider/path_provider.dart';  // 添加这行导入
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'Auok浏览器',
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
  String title;    // 网页标题
  String url;      // 网页URL
  bool isLoading;  // 加载状态

  BrowserTab({
    required this.id,
    required this.controller,
    this.title = 'auok浏览器',  // 修改默认标题
    this.url = 'about:blank',
    this.isLoading = false,
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
  String type;
  Map<String, dynamic> params;
  bool isEnabled;

  Script({
    required this.type,
    this.params = const {},
    this.isEnabled = true,
  });

  // 从 JSON 字符串创建脚本
  factory Script.fromJson(String jsonStr) {
    final data = json.decode(jsonStr);
    return Script(
      type: data['脚本类型'],
      params: Map<String, dynamic>.from(data)..remove('脚本类型'),
      isEnabled: true,
    );
  }

  // 转换为 JSON 字符串
  String toJson() {
    final data = {'脚本类型': type, ...params};
    return json.encode(data);
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
  int _currentScriptIndex = 0;  // 添加当前执行位次

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBookmarksAndHistory();
    _initBrowser();
  }

  Future<void> _loadBookmarksAndHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarksJson = prefs.getStringList('bookmarks') ?? [];
      final historyJson = prefs.getStringList('history') ?? [];

      setState(() {
        _bookmarks.clear();
        _bookmarks.addAll(bookmarksJson.map((json) {
          final data = jsonDecode(json);
          return Bookmark(
            title: data['title'],
            url: data['url'],
            createdAt: DateTime.parse(data['createdAt']),
          );
        }));

        _history.clear();
        _history.addAll(historyJson.map((json) {
          final data = jsonDecode(json);
          return HistoryItem(
            title: data['title'],
            url: data['url'],
            visitedAt: DateTime.parse(data['visitedAt']),
          );
        }));
      });
    } catch (e) {
      debugPrint('Load bookmarks and history error: $e');
    }
  }

  Future<void> _saveBookmarksAndHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('bookmarks', _bookmarks.map((bookmark) => 
        jsonEncode({
          'title': bookmark.title,
          'url': bookmark.url,
          'createdAt': bookmark.createdAt.toIso8601String(),
        })
      ).toList());

      await prefs.setStringList('history', _history.map((item) =>
        jsonEncode({
          'title': item.title,
          'url': item.url,
          'visitedAt': item.visitedAt.toIso8601String(),
        })
      ).toList());
    } catch (e) {
      debugPrint('Save bookmarks and history error: $e');
    }
  }

  Future<void> _initBrowser() async {
    try {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 100));
      // 只在首次启动时添加新标签页
      if (_tabs.isEmpty) {
        _addNewTab();
      }
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
        ..setBackgroundColor(const Color(0x00000000))
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
                  
                  if (e.target.closest('a')) {
                    type = '点击文字';
                    text = e.target.textContent || e.target.innerText;
                  }
                  
                  if (text.trim()) {
                    ScriptRecorder.postMessage(type + '|' + text.trim());
                  }
                });

                // 监听表单提交
                document.addEventListener('submit', function(e) {
                  const formData = new FormData(e.target);
                  let data = {};
                  const inputs = Array.from(e.target.querySelectorAll('input:not([type="hidden"]):not([type="submit"]), textarea'));
                  inputs.forEach((input, index) => {
                    if (input.value) {
                      data['输入框' + (index + 1)] = input.value;
                    }
                  });
                  ScriptRecorder.postMessage('输入提交|' + JSON.stringify(data));
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
        ..addJavaScriptChannel(
          'ContextMenu',
          onMessageReceived: (JavaScriptMessage message) {
            showCupertinoModalPopup(
              context: context,
              builder: (context) => CupertinoActionSheet(
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () {
                      controller.runJavaScript('document.execCommand("copy")');
                      Navigator.pop(context);
                    },
                    child: const Text('复制'),
                  ),
                  CupertinoActionSheetAction(
                    onPressed: () {
                      // 实现查找功能
                      Navigator.pop(context);
                    },
                    child: const Text('查找'),
                  ),
                  CupertinoActionSheetAction(
                    onPressed: () {
                      // 实现翻译功能
                      Navigator.pop(context);
                    },
                    child: const Text('翻译'),
                  ),
                  CupertinoActionSheetAction(
                    onPressed: () {
                      // 实现分享功能
                      Navigator.pop(context);
                    },
                    child: const Text('分享'),
                  ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            );
          },
        )
        ..runJavaScript('''
          document.addEventListener('contextmenu', function(e) {
            e.preventDefault();
            ContextMenu.postMessage('');
          });
        ''')
        ..addJavaScriptChannel(
          'ScriptRecorder',
          onMessageReceived: (JavaScriptMessage message) {
            if (!_isRecording) return;
            
            final parts = message.message.split('|');
            if (parts.length != 2) return;
            
            final type = parts[0];
            final content = parts[1];
            
            setState(() {
              switch (type) {
                case '点击文字':
                  _scripts.add(Script(
                    type: type,
                    params: {'点击文字': content},
                    isEnabled: true,
                  ));
                  break;
                case '输入提交':
                  try {
                    final data = json.decode(content) as Map<String, dynamic>;
                    _scripts.add(Script(
                      type: type,
                      params: data,
                      isEnabled: true,
                    ));
                  } catch (e) {
                    debugPrint('Parse input data error: $e');
                  }
                  break;
              }
            });
          },
        )
        ..loadFlutterAsset('assets/welcome.html');  // 修改这里，加载本地HTML文件

      setState(() {
        _tabs.add(BrowserTab(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          controller: controller,
          title: '欢迎',  // 设置默认标题
          url: 'about:blank',
          isLoading: false,
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
    if (!_isRecording || !mounted) return;

    setState(() {
      if (type == '输入提交') {
        try {
          final data = json.decode(content) as Map<String, dynamic>;
          _scripts.add(Script(
            type: type,
            params: data,
            isEnabled: true,
          ));
        } catch (e) {
          debugPrint('Parse input data error: $e');
        }
      } else {
        _scripts.add(Script(
          type: type,
          params: {'点击文字': content},
          isEnabled: true,
        ));
      }
    });
  }

  // 添加导出脚本方法
  String exportScript() {
    final List<String> lines = [];
    
    // 添加全局信息
    final globalScript = Script(
      type: "全局变量",
      params: {
        '执行延迟': _executionDelay,
        '循环次数': _originalLoopCount,
      },
      isEnabled: true,
    );
    lines.add(globalScript.toJson());
    
    // 添加所有已启用的脚本
    for (var script in _scripts) {
      if (script.isEnabled) {
        lines.add(script.toJson());
      }
    }
    
    return lines.join('\n');
  }

  void _addScript() {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        String type = "点击文字";
        String clickText = '';
        List<String> inputValues = [''];  // 输入框的值
        int executionDelay = 800;  // 默认延迟

        return StatefulBuilder(
          builder: (context, setState) => CupertinoAlertDialog(
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
                          const Icon(CupertinoIcons.chevron_down, size: 16),
                      ],
                    ),
                    onPressed: () {
                        showCupertinoModalPopup(
                          context: context,
                          builder: (context) => Container(
                            height: 200,
                            color: CupertinoColors.systemBackground.darkColor,
                            child: SafeArea(
                              child: CupertinoPicker(
                                backgroundColor: CupertinoColors.black,
                                itemExtent: 32,
                                onSelectedItemChanged: (index) {
                                  setState(() {
                                    type = index == 0 ? "点击文字" : "输入框提交";
                                  });
                                },
                                children: const [
                                  Text("点击文字", style: TextStyle(color: CupertinoColors.white)),
                                  Text("输入框提交", style: TextStyle(color: CupertinoColors.white)),
                                ],
                              ),
                            ),
                          ),
                        );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
                
                // 根据类型显示不同的输入选项
                if (type == "点击文字")
              CupertinoTextField(
                placeholder: '点击文字',
                    controller: TextEditingController(text: clickText),
                    onChanged: (value) => clickText = value,
                  )
                else
                  Column(
                    children: [
                      // 执行延迟输入
                      Row(
                        children: [
                          const Text('执行延迟'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoTextField(
                              placeholder: '毫秒',
                              keyboardType: TextInputType.number,
                              controller: TextEditingController(text: executionDelay.toString()),
                              onChanged: (value) => executionDelay = int.tryParse(value) ?? 800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 输入框列表
                      ...List.generate(inputValues.length, (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: CupertinoTextField(
                                placeholder: '输入框${index + 1}',
                                controller: TextEditingController(text: inputValues[index]),
                                onChanged: (value) => inputValues[index] = value,
                              ),
                            ),
                            if (index == inputValues.length - 1)
                              CupertinoButton(
                                padding: const EdgeInsets.only(left: 8),
                                child: const Icon(CupertinoIcons.add_circled),
                                onPressed: () {
                                  setState(() {
                                    inputValues.add('');
                                  });
                                },
                              ),
                            if (inputValues.length > 1)
                              CupertinoButton(
                                padding: const EdgeInsets.only(left: 8),
                                child: const Icon(CupertinoIcons.minus_circle_fill, color: CupertinoColors.destructiveRed),
                                onPressed: () {
                                  setState(() {
                                    inputValues.removeAt(index);
                                  });
                                },
                              ),
                          ],
                        ),
                      )),
                    ],
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
                  if (type == "点击文字" && clickText.isNotEmpty) {
                    this.setState(() {
                    _scripts.add(Script(
                      type: type,
                      params: {
                          '点击文字': clickText,
                      },
                      isEnabled: true,
                    ));
                  });
                  } else if (type == "输入框提交" && inputValues.any((value) => value.isNotEmpty)) {
                    final params = <String, dynamic>{
                      '执行延迟': executionDelay,
                    };
                    for (var i = 0; i < inputValues.length; i++) {
                      if (inputValues[i].isNotEmpty) {
                        params['输入框${i + 1}'] = inputValues[i];
                      }
                    }
                    this.setState(() {
                      _scripts.add(Script(
                        type: type,
                        params: params,
                        isEnabled: true,
                      ));
                    });
                }
                Navigator.pop(context);
              },
            ),
          ],
          ),
        );
      },
    );
  }

  // 修改脚本进度显示
  Widget _buildScriptProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '脚本列表: ${_scripts.length}',
        style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 16,
        ),
          ),
          if (_isExecuting)
            Text(
              '  当前: ${_currentScriptIndex + 1}',  // 添加当前执行位次
              style: const TextStyle(
                color: CupertinoColors.activeBlue,
                fontSize: 16,
              ),
            ),
        ],
      ),
    );
  }

  // 修改执行脚本的逻辑
  Future<void> _executeScripts() async {
    if (_scripts.isEmpty) return;
    
    setState(() {
      _isExecuting = true;
      _successCount = 0;
      _failureCount = 0;
      _currentScriptIndex = 0;
    });
    
    _remainingLoopCount = _originalLoopCount;
    
    while (_originalLoopCount == 0 || _remainingLoopCount > 0) {  // 修改循环条件
      if (!_isExecuting) break;  // 允许中断执行
      
      for (var i = 0; i < _scripts.length && _isExecuting; i++) {
        setState(() => _currentScriptIndex = i);
      if (!_scripts[i].isEnabled) continue;
        if (_isPaused) {
          await Future.doWhile(() async {
            await Future.delayed(const Duration(milliseconds: 100));
            return _isPaused;
          });
        }
        
        try {
          final success = await executeScript(_scripts[i]);
          setState(() {
            if (success) {_successCount++;} else {_failureCount++;}
          });
        await Future.delayed(Duration(milliseconds: _executionDelay));
      } catch (e) {
          setState(() => _failureCount++);
        debugPrint('Execute script error: $e');
      }
    }
      
      if (_originalLoopCount > 0) {  // 只在非无限循环时减少计数
        _remainingLoopCount--;
      }
    }
    
    setState(() {
      _isExecuting = false;
      _currentScriptIndex = 0;
    });
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
            color: CupertinoColors.systemGrey4.withAlpha(51),
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
                            color: CupertinoColors.systemGrey.withAlpha(51),
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
    if (state == AppLifecycleState.paused) {
      _saveBookmarksAndHistory();
    }
    super.didChangeAppLifecycleState(state);
  }

  void _cleanupWebViews() {
    try {
      for (var tab in _tabs) {
        tab.controller.clearCache();
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
              child: GestureDetector(
                onTap: () => _showUrlInput(),
                child: AbsorbPointer(
                  child: CupertinoTextField(
                    controller: _urlController,
                    enabled: false,
                    textAlign: TextAlign.left,
                    placeholder: _getDisplayTitle(),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey6,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            // 添加分隔线
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: CupertinoColors.systemGrey4,
            ),
            // 添加书签按钮
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _toggleBookmark(),
              child: Icon(
                _isBookmarked() ? CupertinoIcons.star_fill : CupertinoIcons.star,
                color: _isBookmarked() ? CupertinoColors.systemBlue : CupertinoColors.systemGrey,
                size: 22,
              ),
            ),
            // 刷新按钮
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                if (_tabs.isNotEmpty && _tabs[_currentIndex].url != 'about:blank') {
                  _tabs[_currentIndex].controller.reload();
                }
              },
              child: const Icon(
                CupertinoIcons.refresh,
                color: CupertinoColors.systemGrey,
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
                              _buildGlobalSettings(),
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
                                    return _buildScriptItem(script, index);
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
                                        _clearScripts();
                                        Navigator.pop(context);  // If it's in a dialog
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
      FilePickerResult? result;
      if (Platform.isIOS) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zds'],
          allowMultiple: false,
          withData: true,
          allowCompression: false,
          dialogTitle: '选择脚本文件',
          onFileLoading: (FilePickerStatus status) => debugPrint(status.toString()),
          lockParentWindow: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zds'],
          allowMultiple: false,
          withData: true,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content;
        
        if (Platform.isIOS) {
          if (file.bytes != null) {
            content = utf8.decode(file.bytes!);
          } else {
            throw Exception('无法读取文件内容');
          }
        } else {
          content = await File(file.path!).readAsString(encoding: utf8);
        }

        final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.isEmpty) throw Exception('文件为空');

        setState(() {
          _scripts.clear();
          for (var line in lines) {
            _scripts.add(Script.fromJson(line));
          }
        });
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

  // 修改 URL 输入状态处理
  void _showUrlInput() {
    if (!_tabs.isNotEmpty || _currentIndex < 0 || _currentIndex >= _tabs.length) return;
    
    final tab = _tabs[_currentIndex];
    final isDefaultPage = tab.url == 'about:blank';
    final currentContext = context; // Capture the current context
    
    showCupertinoModalPopup(
      context: currentContext,
      barrierColor: CupertinoColors.black.withAlpha(204),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height,
        color: CupertinoColors.black,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: TextEditingController(
                          text: isDefaultPage ? '' : tab.url,
                        )..selection = isDefaultPage ? 
                            const TextSelection.collapsed(offset: 0) :
                            TextSelection(
                              baseOffset: 0,
                              extentOffset: tab.url.length,
                            ),
                        autofocus: true,
                        placeholder: '搜索或输入网址',
                        onSubmitted: (url) async {
                          if (url.isEmpty) {
                            Navigator.pop(context);
                            return;
                          }
                          String finalUrl = url;
                          if (!url.startsWith('http://') && !url.startsWith('https://')) {
                            finalUrl = 'https://$url';
                          }
                          try {
                            final uri = Uri.parse(finalUrl);
                            await tab.controller.loadRequest(uri);
                            if (mounted && context.mounted) { // Check both State and BuildContext
                          Navigator.pop(context);
                            }
                          } catch (e) {
                            debugPrint('Load URL error: $e');
                          }
                        },
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: const Text('取消'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: CupertinoColors.systemGrey4),
              Expanded(
                child: ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return Column(
                      children: [
                        CupertinoListTile(
                          title: Text(
                            item.title,
                            style: const TextStyle(color: CupertinoColors.white),
                          ),
                          subtitle: Text(
                            item.url,
                            style: const TextStyle(color: CupertinoColors.systemGrey),
                          ),
                          onTap: () {
                            _tabs[_currentIndex].controller.loadRequest(
                              Uri.parse(item.url),
                            );
                            Navigator.pop(context);
                          },
                        ),
                        const Divider(color: CupertinoColors.systemGrey4),
                      ],
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

  // 添加获取显示文本的方法
  String _getDisplayTitle() {
    if (!_tabs.isNotEmpty || _currentIndex < 0 || _currentIndex >= _tabs.length) {
      return '欢迎使用';
    }
    
    final tab = _tabs[_currentIndex];
    if (tab.url == 'about:blank') {
      return '欢迎使用';
    }
    
    return tab.title.isEmpty ? '无标题页面' : tab.title;
  }

  // 添加书签相关方法
  bool _isBookmarked() {
    if (!_tabs.isNotEmpty || _currentIndex < 0 || _currentIndex >= _tabs.length) {
      return false;
    }
    final tab = _tabs[_currentIndex];
    if (tab.url == 'about:blank') return false;
    
    return _bookmarks.any((bookmark) => bookmark.url == tab.url);
  }

  void _toggleBookmark() async {
    if (!_tabs.isNotEmpty || _currentIndex < 0 || _currentIndex >= _tabs.length) return;
    
    final tab = _tabs[_currentIndex];
    if (tab.url == 'about:blank') return;

    setState(() {
      if (_isBookmarked()) {
        _bookmarks.removeWhere((bookmark) => bookmark.url == tab.url);
      } else {
        _bookmarks.add(Bookmark(
          title: tab.title,
          url: tab.url,
          createdAt: DateTime.now(),
        ));
      }
    });
  }

  // 添加脚本执行方法
  Future<bool> executeScript(Script script) async {
    try {
      switch (script.type) {
        case "点击文字":
          return await _executeClickText(script);
        case "输入框提交":
          return await _executeFormSubmit(script);
        case "刷新网页":
          await _tabs[_currentIndex].controller.reload();
          return true;
        case "延时脚本":
          await Future.delayed(Duration(milliseconds: script.params['执行延迟'] ?? 800));
          return true;
        case "逻辑脚本-出现文字":
          return await _executeLogicScript(script);
        case "执行本地脚本集":
          return await _executeLocalScript(script);
        case "脚本替换":
          return await _executeScriptReplace(script);
        default:
          return false;
      }
    } catch (e) {
      debugPrint('Script execution error: $e');
      return false;
    }
  }

  Future<bool> _executeClickText(Script script) async {
    if (!mounted || _tabs.isEmpty || _currentIndex < 0) return false;
    final result = await _tabs[_currentIndex].controller.runJavaScriptReturningResult('''
      (function() {
        const text = "${script.params['点击文字'] ?? ''}";
        // 优先查找链接
        const links = Array.from(document.querySelectorAll('a')).filter(a => 
          a.textContent.trim() === text.trim()
        );
        if (links.length > 0) {
          links[0].click();
            return true;
        }
        return false;
      })();
    ''');
    return result.toString() == 'true';
  }

  Future<bool> _executeFormSubmit(Script script) async {
    if (!mounted || _tabs.isEmpty || _currentIndex < 0) return false;
    final formInputs = Map<String, String>.from(script.params)
      ..removeWhere((key, value) => !key.startsWith('输入框'));
    final executionDelay = script.params['执行延迟'] ?? 800;
    
    final result = await _tabs[_currentIndex].controller.runJavaScriptReturningResult('''
      (function() {
        const forms = document.querySelectorAll('form');
        if (forms.length === 0) return false;
        
        let targetForm = null;
        for (const form of forms) {
          if (form.querySelector('input[type="submit"], button[type="submit"]')) {
            targetForm = form;
            break;
          }
        }
        if (!targetForm) return false;

        // 修改输入框选择逻辑，排除 hidden 类型
        const inputs = Array.from(targetForm.querySelectorAll('input:not([type="hidden"]):not([type="submit"]), textarea'));
        
        ${formInputs.entries.map((e) => '''
          if (inputs[${int.parse(e.key.substring(3)) - 1}]) {
            const input = inputs[${int.parse(e.key.substring(3)) - 1}];
            input.value = "$e.value";
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
          }
        ''').join('\n')}

        setTimeout(() => {
          const submitButton = targetForm.querySelector('input[type="submit"], button[type="submit"]');
          if (submitButton) submitButton.click();
          else targetForm.submit();
        }, $executionDelay);
        
        return true;
      })();
    ''');
    
    await Future.delayed(Duration(milliseconds: executionDelay));
    return result.toString() == 'true';
  }

  Future<bool> _executeLogicScript(Script script) async {
    if (!mounted || _tabs.isEmpty || _currentIndex < 0) return false;
    final targetText = script.params['出现文字'];
    final result = await _tabs[_currentIndex].controller.runJavaScriptReturningResult(
      'document.body.textContent.includes("$targetText")'
    );
    
    if (result.toString() == 'true') {
      final thenScript = Script.fromJson(json.encode(script.params['出现文字,则执行:']));
      return await executeScript(thenScript);
    } else {
      final elseScript = Script.fromJson(json.encode(script.params['未出现文字,则执行:']));
      return await executeScript(elseScript);
    }
  }

  Future<bool> _executeLocalScript(Script script) async {
    try {
      final scriptPath = script.params['本地脚本'] as String;
      final file = File(scriptPath);
      if (!await file.exists()) return false;

      // 保存当前状态
      final currentScripts = List<Script>.from(_scripts);
      final currentIndex = _currentIndex;

      // 加载并执行新脚本
      final content = await file.readAsString();
      final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      _scripts.clear();
      for (var line in lines) {
        _scripts.add(Script.fromJson(line));
      }
      await _executeScripts();

      // 恢复原始状态
      _scripts
        ..clear()
        ..addAll(currentScripts);
      _currentIndex = currentIndex;
      return true;
    } catch (e) {
      debugPrint('Execute local script error: $e');
      return false;
    }
  }

  Future<bool> _executeScriptReplace(Script script) async {
    try {
      final scriptPath = script.params['替换为:'] as String;
      final file = File(scriptPath);
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      // 替换当前脚本
      _scripts.removeAt(_currentIndex);
      for (var line in lines) {
        _scripts.insert(_currentIndex, Script.fromJson(line));
      }
      return true;
    } catch (e) {
      debugPrint('Script replace error: $e');
      return false;
    }
  }

  void _clearScripts() {
    if (!mounted) return;
    
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有脚本吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              setState(() {
                _scripts.clear();
                _executionDelay = 1000;
                _originalLoopCount = 1;
                _remainingLoopCount = 1;
                _isRecording = false;
                _isExecuting = false;
                _successCount = 0;
                _failureCount = 0;
                _currentScriptIndex = 0;
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalSettings() {
    return Column(
      children: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _showDelaySettingDialog,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '执行延迟',
                style: TextStyle(color: CupertinoColors.white, fontSize: 14),
              ),
              Text(
                '$_executionDelay ms',
                style: TextStyle(
                  color: CupertinoColors.white.withAlpha(153),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _showLoopCountDialog,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '循环次数',
                style: TextStyle(color: CupertinoColors.white, fontSize: 14),
              ),
              Text(
                _originalLoopCount == 0 ? '无限循环' : '$_originalLoopCount 次',
                style: TextStyle(
                  color: CupertinoColors.white.withAlpha(153),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showScriptOptions(int index) {
    final script = _scripts[index];
    showCupertinoModalPopup(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('编辑脚本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (script.type == "点击文字")
              CupertinoTextField(
                controller: TextEditingController(text: script.params['点击文字']),
                placeholder: '点击文字',
                onChanged: (value) => script.params['点击文字'] = value,
              )
            else
              Column(
                children: [
                  ...List.generate(
                    (script.params.length / 2).ceil(),
                    (i) {
                      final key = '输入框${i + 1}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: CupertinoTextField(
                          controller: TextEditingController(text: script.params[key]),
                          placeholder: key,
                          onChanged: (value) => script.params[key] = value,
                        ),
                      );
                    },
                  ),
                ],
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
              Navigator.pop(context);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  void _showDelaySettingDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('执行延迟'),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: CupertinoTextField(
            controller: TextEditingController(text: _executionDelay.toString()),
            keyboardType: TextInputType.number,
            autofocus: true,
            placeholder: '请输入延迟时间(毫秒)',
            onChanged: (value) {
              final delay = int.tryParse(value);
              if (delay != null && delay > 0) {
                setState(() => _executionDelay = delay);
              }
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showLoopCountDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('循环次数'),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: CupertinoTextField(
            controller: TextEditingController(text: _originalLoopCount.toString()),
            keyboardType: TextInputType.number,
            autofocus: true,
            placeholder: '请输入循环次数(0表示无限循环)',
            onChanged: (value) {
              final count = int.tryParse(value);
              if (count != null) {
                setState(() {
                  _originalLoopCount = count;
                  _remainingLoopCount = count;
                });
              }
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showRepeatCountDialog(int index) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('设置重复次数'),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: CupertinoTextField(
            controller: TextEditingController(
              text: (_scripts[index].params['重复次数'] ?? 1).toString(),
            ),
            keyboardType: TextInputType.number,
            autofocus: true,
            placeholder: '请输入重复次数',
            onChanged: (value) {
              final count = int.tryParse(value);
              if (count != null && count > 0) {
                setState(() {
                  _scripts[index].params['重复次数'] = count;
                });
              }
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptItem(Script script, int index) {
    return GestureDetector(
      onTap: () => _editScript(index),  // 短按编辑
      onLongPress: () => _showScriptOptions(index),  // 长按显示选项
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                // 左侧脚本类型
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBlue.withAlpha(50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    script.type,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 脚本内容
                Expanded(
                  child: Text(
                    script.type == "点击文字" ? script.params['点击文字'] ?? '' : '输入表单',
                    style: TextStyle(
                      color: script.isEnabled ? CupertinoColors.white : CupertinoColors.systemGrey,
                      fontSize: 12,
                    ),
                  ),
                ),
                // 重复次数
                Text(
                  '${script.params['重复次数'] ?? 1}次',
                  style: const TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            // 右上角角标
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

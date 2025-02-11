import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';  // 添加分享功能的包
import 'package:path_provider/path_provider.dart';  // 添加这行导入
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';  // 添加这行导入
import 'package:wakelock_plus/wakelock_plus.dart';  // 替换 flutter_screen_wake 的导入
import 'package:permission_handler/permission_handler.dart';  // 添加权限处理包

void main() async {  // 改为异步函数
  WidgetsFlutterBinding.ensureInitialized();  // 确保Flutter绑定初始化
  
  // 请求网络权限
  if (Platform.isIOS) {
    await Permission.photos.request();  // iOS需要先请求照片权限
    await Permission.mediaLibrary.request();  // 媒体库权限
  }
  
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

// 添加脚本模式枚举
enum ScriptMode {
  simple('简单'),
  normal('普通'),
  expert('专家');

  final String label;
  const ScriptMode(this.label);
}

// 修改 Script 类，添加模式属性
class Script {
  final String type;
  final Map<String, dynamic> params;
  bool isEnabled;
  ScriptMode mode;  // 添加模式属性

  Script({
    required this.type,
    required this.params,
    this.isEnabled = true,
    this.mode = ScriptMode.simple,  // 默认简单模式
  });

  // 修改 fromJson 和 toJson 方法以包含模式
  factory Script.fromJson(String json) {
    final data = jsonDecode(json);
    return Script(
      type: data['脚本类型'],
      params: Map<String, dynamic>.from(data['参数']),
      isEnabled: data['启用'] ?? true,
      mode: ScriptMode.values.firstWhere(
        (m) => m.label == (data['模式'] ?? '简单'),
        orElse: () => ScriptMode.simple,
      ),
    );
  }

  String toJson() {
    return jsonEncode({
      '脚本类型': type,
      '参数': params,
      '启用': isEnabled,
      '模式': mode.label,
    });
  }

  Map<String, dynamic> getClickParams() {
    if (type != "点击文字") return {};
    
    switch (mode) {
      case ScriptMode.simple:
        return {
          '点击文字': params['点击文字'] ?? '',
        };
      case ScriptMode.normal:
        return {
          '执行延迟': params['执行延迟'] ?? 0,
          '时间单位': params['时间单位'] ?? '毫秒',
          '出现文字': params['出现文字'] ?? '',
          '点击文字': params['点击文字'] ?? '',
          '完全匹配': params['完全匹配'] ?? false,
        };
      case ScriptMode.expert:
        return {
          '执行延迟': params['执行延迟'] ?? 0,
          '时间单位': params['时间单位'] ?? '毫秒',
          '出现文字': params['出现文字'] ?? '',
          '在此之后': params['在此之后'] ?? '',
          '在此之前': params['在此之前'] ?? '',
          '点击文字': params['点击文字'] ?? '',
          '完全匹配': params['完全匹配'] ?? false,
          '多个筛选': params['多个筛选'] ?? 1,
        };
    }
  }
}

// 添加时间单位枚举
enum TimeUnit {
  milliseconds('毫秒', 1),
  seconds('秒', 1000),
  minutes('分钟', 60000);

  final String label;
  final int multiplier;
  const TimeUnit(this.label, this.multiplier);
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
  bool _isFullScreen = false;
  bool _isDarkMode = false;
  bool _keepScreenOn = false;
  bool _autoLeaveMode = false;
  bool _showLeaveModeOverlay = false;
  // 添加计时器变量
  Timer? _inactivityTimer;
  // 添加时间单位状态
  TimeUnit _delayTimeUnit = TimeUnit.milliseconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 使用 Future.delayed 确保界面初始化完成后再恢复状态
    Future.delayed(Duration.zero, () async {
      await _loadBookmarksAndHistory();
      await _restoreTabsState();
    });
    
    // 监听所有用户交互
    GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent event) {
      if (!_isExecuting) {  // 只在非执行状态下重置计时器
        _resetInactivityTimer();
      }
    });
  }

  // 重置不活动计时器
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_autoLeaveMode && !_showLeaveModeOverlay) {  // 移除 !_isExecuting 条件
      _inactivityTimer = Timer(const Duration(minutes: 3), () {
        if (mounted && _autoLeaveMode) {
          _showLeaveMode();
        }
      });
    }
  }

  // 修改离开模式开关的处理
  void _toggleLeaveMode(bool value) {
    setState(() {
      _autoLeaveMode = value;
    });
    if (value) {
      _resetInactivityTimer();
    } else {
      _inactivityTimer?.cancel();
      _hideLeaveMode();
    }
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

  // 修改保存标签页状态的方法
  Future<void> _saveTabsState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tabsData = await Future.wait(_tabs.map((tab) async {
        final url = await tab.controller.currentUrl() ?? 'about:blank';
        final title = await tab.controller.getTitle() ?? '新标签页';
        return {
          'url': url.startsWith('file:///') ? 'about:blank' : url,
          'title': title,
        };
      }));
      
      await prefs.setString('last_tabs', jsonEncode({
        'tabs': tabsData,
        'currentIndex': _currentIndex,
        'isDarkMode': _isDarkMode,
        'keepScreenOn': _keepScreenOn,
      }));
    } catch (e) {
      debugPrint('Save tabs state error: $e');
    }
  }

  // 修改恢复标签页状态的方法
  Future<void> _restoreTabsState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tabsJson = prefs.getString('last_tabs');
      
      if (tabsJson != null) {
        final data = jsonDecode(tabsJson);
        final tabsList = List<Map<String, dynamic>>.from(data['tabs']);
        final savedIndex = data['currentIndex'] as int;
        
        // 恢复设置
        setState(() {
          _isDarkMode = data['isDarkMode'] ?? false;
          _keepScreenOn = data['keepScreenOn'] ?? false;
        });
        
        // 恢复标签页
        for (var tabData in tabsList) {
          final url = tabData['url'] as String;
          if (url != 'about:blank') {
            await _addNewTab(
              initialUrl: url,
              initialTitle: tabData['title'] as String,
            );
          } else {
            await _addNewTab();
          }
        }
        
        if (savedIndex >= 0 && savedIndex < _tabs.length) {
          setState(() => _currentIndex = savedIndex);
        }
        
        // 应用设置
        if (_keepScreenOn) {
          await WakelockPlus.enable();
        }
      } else {
        await _addNewTab();
      }
    } catch (e) {
      debugPrint('Restore tabs state error: $e');
      await _addNewTab();
    }
  }

  // 修改 _addNewTab 方法以支持初始 URL 和标题
  Future<void> _addNewTab({String? initialUrl, String? initialTitle}) async {
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
                if (url.startsWith('file:///')) {
                  _tabs[_currentIndex].url = 'about:blank';
                }
              });
              if (_isDarkMode) {
                _applyDarkMode(true);
              }
            },
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _loadingProgress = progress / 100;
              });
            },
            onPageFinished: (url) async {
              if (!mounted) return;
              final title = await controller.getTitle() ?? 'New Tab';
              setState(() {
                isLoading = false;
                _loadingProgress = 1;
                if (mounted && _tabs.isNotEmpty && _currentIndex >= 0 && 
                    _currentIndex < _tabs.length && 
                    !url.startsWith('file:///') && url != 'about:blank') {
                  _history.insert(0, HistoryItem(
                    title: title,
                    url: url,
                    visitedAt: DateTime.now(),
                  ));
                  _saveBookmarksAndHistory();
                }
              });
              _updateTabInfo(_currentIndex);
              
              // 重新应用设置
              if (_isDarkMode) {
                _applyDarkMode(true);
              }
              if (_keepScreenOn) {
                await WakelockPlus.enable();
              }

              // 添加脚本录制的事件监听器
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
                  const form = e.target;
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"]');
                  if (!submitButton) return;
                  
                  let data = {};
                  const inputs = Array.from(form.querySelectorAll('input:not([type="hidden"]):not([type="submit"]), textarea'))
                    .filter(input => {
                      const rect = input.getBoundingClientRect();
                      return rect.width > 0 && rect.height > 0; // 确保元素是可见的
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
                case '输入框提交':
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
        );

      if (initialUrl != null && initialUrl != 'about:blank') {
        await controller.loadRequest(Uri.parse(initialUrl));
      } else {
        await controller.loadFlutterAsset('assets/welcome.html');
      }

      setState(() {
        _tabs.add(BrowserTab(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          controller: controller,
          title: initialTitle ?? '欢迎',
          url: initialUrl ?? 'about:blank',
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

  // 修改导出脚本方法
  String exportScript() {
    final List<String> lines = [];
    
    // 添加全局信息
    final globalScript = Script(
      type: "全局变量",
      params: {
        '执行延迟': _executionDelay ~/ _delayTimeUnit.multiplier,
        '时间单位': _delayTimeUnit.label,
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
  Future<bool> executeScript(Script script) async {
    if (!script.isEnabled || _tabs.isEmpty || _currentIndex < 0) return false;
    
    final currentController = _tabs[_currentIndex].controller;
    final repeatCount = script.params['重复次数'] ?? 1;
    bool success = true;
    
    for (var i = 0; i < repeatCount; i++) {
      if (!_isExecuting) break;
      
      bool result = false;
      switch (script.type) {
        case "点击文字":
          result = await _executeClickScript(script, currentController);
          break;
        case "输入框提交":
          result = await _executeFormSubmit(script, currentController);
          break;
      }
      
      if (!result) {
        success = false;
        break;
      }
      
      // 如果不是最后一次重复，则等待执行延迟
      if (i < repeatCount - 1) {
        // 使用全局延迟设置
        await Future.delayed(Duration(milliseconds: _executionDelay));
      }
    }
    
    // 在脚本执行完成后，如果不是最后一个脚本，添加全局延迟
    if (success && _currentScriptIndex < _scripts.length - 1) {
      await Future.delayed(Duration(milliseconds: _executionDelay));
    }
    
    return success;
  }

  // 修改点击脚本执行方法
  Future<bool> _executeClickScript(Script script, WebViewController controller) async {
    if (!mounted) return false;
    
    final params = script.getClickParams();
    final clickText = params['点击文字'] ?? '';
    if (clickText.isEmpty) return false;

    // 处理延迟
    if (script.mode != ScriptMode.simple) {
      final delay = params['执行延迟'] ?? 0;
      final timeUnit = params['时间单位'] ?? '毫秒';
      final multiplier = TimeUnit.values.firstWhere(
        (unit) => unit.label == timeUnit,
        orElse: () => TimeUnit.milliseconds,
      ).multiplier;
      
      await Future.delayed(Duration(milliseconds: delay * multiplier));
    }

    // 构建 JavaScript 代码
    final result = await controller.runJavaScriptReturningResult('''
      (function() {
        ${_buildClickScriptLogic(script.mode, params)}
      })();
    ''');
    
    return result.toString() == 'true';
  }

  // 根据不同模式构建点击逻辑
  String _buildClickScriptLogic(ScriptMode mode, Map<String, dynamic> params) {
    switch (mode) {
      case ScriptMode.simple:
        return '''
          const text = "${params['点击文字']}";
          const links = Array.from(document.querySelectorAll('a')).filter(a => 
            a.textContent.trim() === text.trim()
          );
          if (links.length > 0) {
            links[0].click();
            return true;
          }
          return false;
        ''';
        
      case ScriptMode.normal:
        return '''
          // 检查是否存在触发条件的文字
          const triggerTexts = "${params['出现文字'] ?? ''}".split(';').filter(t => t.trim());
          if (triggerTexts.length > 0) {
            const pageText = document.body.textContent;
            const hasText = triggerTexts.some(text => 
              text && pageText.includes(text.trim())
            );
            if (!hasText) return false;
          }
          
          // 查找可点击的文字
          const clickTexts = "${params['点击文字']}".split(';').filter(t => t.trim());
          const isExactMatch = ${params['完全匹配'] ? 'true' : 'false'};
          
          for (const text of clickTexts) {
            const links = Array.from(document.querySelectorAll('a')).filter(a => {
              const linkText = a.textContent.trim();
              return isExactMatch ? linkText === text.trim() : linkText.includes(text.trim());
            });
            
            if (links.length > 0) {
              links[0].click();
              return true;
            }
          }
          return false;
        ''';
        
      case ScriptMode.expert:
        return '''
          // 检查是否存在触发条件的文字
          const triggerTexts = "${params['出现文字'] ?? ''}".split(';').filter(t => t.trim());
          if (triggerTexts.length > 0) {
            const pageText = document.body.textContent;
            const hasText = triggerTexts.some(text => 
              text && pageText.includes(text.trim())
            );
            if (!hasText) return false;
          }
          
          // 获取搜索范围
          let content = document.body.innerHTML;
          const afterText = "${params['在此之后'] ?? ''}".trim();
          const beforeText = "${params['在此之前'] ?? ''}".trim();
          
          if (afterText) {
            const afterIndex = content.indexOf(afterText);
            if (afterIndex === -1) return false;
            content = content.substring(afterIndex + afterText.length);
          }
          
          if (beforeText) {
            const beforeIndex = content.indexOf(beforeText);
            if (beforeIndex === -1) return false;
            content = content.substring(0, beforeIndex);
          }
          
          // 创建临时容器来解析HTML
          const temp = document.createElement('div');
          temp.innerHTML = content;
          
          // 查找可点击的文字
          const clickTexts = "${params['点击文字']}".split(';').filter(t => t.trim());
          const isExactMatch = ${params['完全匹配'] ? 'true' : 'false'};
          const selectionIndex = ${params['多个筛选'] ?? 1};
          
          for (const text of clickTexts) {
            const links = Array.from(temp.querySelectorAll('a')).filter(a => {
              const linkText = a.textContent.trim();
              return isExactMatch ? linkText === text.trim() : linkText.includes(text.trim());
            });
            
            if (links.length > 0) {
              let targetIndex = 0;
              if (selectionIndex === 0) {
                // 随机选择
                targetIndex = Math.floor(Math.random() * links.length);
              } else if (selectionIndex > 0) {
                // 正向选择
                targetIndex = Math.min(selectionIndex - 1, links.length - 1);
              } else {
                // 反向选择
                targetIndex = Math.max(links.length + selectionIndex, 0);
              }
              
              // 在实际页面中找到并点击对应的链接
              const targetText = links[targetIndex].textContent.trim();
              const actualLinks = Array.from(document.querySelectorAll('a')).filter(a => 
                a.textContent.trim() === targetText
              );
              if (actualLinks.length > 0) {
                actualLinks[0].click();
                return true;
              }
            }
          }
          return false;
        ''';
    }
  }

  // 修改表单提交脚本执行方法
  Future<bool> _executeFormSubmit(Script script, WebViewController controller) async {
    if (!mounted) return false;
    final formInputs = Map<String, String>.from(script.params)
      ..removeWhere((key, value) => !key.startsWith('输入框'));
    final executionDelay = script.params['执行延迟'] ?? 800;
    
    final result = await controller.runJavaScriptReturningResult('''
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
        
        const inputs = Array.from(targetForm.querySelectorAll('input:not([type="hidden"]):not([type="submit"]), textarea'));
        ${formInputs.entries.map((e) => '''
          if (inputs[${int.parse(e.key.substring(3)) - 1}]) {
            inputs[${int.parse(e.key.substring(3)) - 1}].value = "${e.value}";
            inputs[${int.parse(e.key.substring(3)) - 1}].dispatchEvent(new Event('input', { bubbles: true }));
            inputs[${int.parse(e.key.substring(3)) - 1}].dispatchEvent(new Event('change', { bubbles: true }));
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
                _showSettings();
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
                        _saveBookmarksAndHistory();
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
                          bookmark.title.isEmpty ? '无标题' : bookmark.title,
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
                            _saveBookmarksAndHistory();
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
                      item.title.isEmpty ? '无标题' : item.title,
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveBookmarksAndHistory();
      _saveTabsState();
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
                    controller: TextEditingController(text: _getDisplayTitle()),
                    enabled: false,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.white,  // 文字颜色改为白色
                    ),
                    decoration: BoxDecoration(
                      color: CupertinoColors.black.withAlpha(204),  // 背景色改为黑色半透明
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
            // 设置按钮
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showSettings,
              child: const Icon(
                CupertinoIcons.settings,
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
                        onPressed: () async {
                          if (await _canGoBack()) {
                            await _tabs[_currentIndex].controller.goBack();
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
                        onPressed: () async {
                          if (await _canGoForward()) {
                            await _tabs[_currentIndex].controller.goForward();
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
                      // 返回默认页按钮
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          if (_tabs.isNotEmpty && _currentIndex >= 0) {
                            await _tabs[_currentIndex].controller.loadFlutterAsset('assets/welcome.html');
                            setState(() {
                              _tabs[_currentIndex].url = 'about:blank';
                              _tabs[_currentIndex].title = '欢迎';
                            });
                          }
                        },
                        child: const Icon(
                          CupertinoIcons.home,
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
                                      onPressed: () => _showAddOrEditScript(),  // 修改这里
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
                                            onPressed: () => _showAddOrEditScript(),  // 修改这里
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
                                      onPressed: _isRecording ? null : _executeScripts,  // 录制时禁用
                                      child: Icon(
                                        CupertinoIcons.play_fill,
                                        color: _isRecording ? CupertinoColors.systemGrey : CupertinoColors.white,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _isRecording ? null : _exportScripts,  // 录制时禁用
                                      child: Icon(
                                        CupertinoIcons.arrow_down_doc_fill,
                                        color: _isRecording ? CupertinoColors.systemGrey : CupertinoColors.white,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _isRecording ? null : _importScripts,  // 录制时禁用
                                      child: Icon(
                                        CupertinoIcons.doc_text_fill,
                                        color: _isRecording ? CupertinoColors.systemGrey : CupertinoColors.white,
                                        size: 20,
                                      ),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: _isRecording ? null : _clearScripts,  // 录制时禁用
                                      child: Icon(
                                        CupertinoIcons.clear_fill,
                                        color: _isRecording ? CupertinoColors.systemGrey : CupertinoColors.systemRed,
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
            // 离开模式遮罩
            if (_showLeaveModeOverlay)
              Container(
                color: CupertinoColors.black.withAlpha(180),
                child: Stack(
                  children: [
                    // 中间的提示文字
                    const Center(
                      child: Text(
                        '离开模式',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 右下角的返回按钮
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(16),
                        color: CupertinoColors.black.withAlpha(100),
                        child: const Text('返回'),
                        onPressed: () {
                          setState(() {
                            _autoLeaveMode = false;
                            _showLeaveModeOverlay = false;
                          });
                        },
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
    _inactivityTimer?.cancel();
    _cleanupWebViews();
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  // 修改导出脚本的方法
  void _exportScripts() {
    String scriptName = '新脚本集';  // 默认名称
    
            showCupertinoDialog(
              context: context,
              builder: (context) => CupertinoAlertDialog(
        title: const Text('导出脚本集'),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              CupertinoTextField(
                controller: TextEditingController(text: scriptName),
                autofocus: true,
                placeholder: '请输入脚本集名称',
                onChanged: (value) => scriptName = value,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
                actions: [
                  CupertinoDialogAction(
            child: const Text('取消'),
                    onPressed: () => Navigator.pop(context),
                  ),
          CupertinoDialogAction(
            child: const Text('导出'),
            onPressed: () async {
              final currentContext = context;
              Navigator.pop(currentContext);
              final scriptContent = exportScript();
              
              try {
                final directory = await getTemporaryDirectory();
                final file = File('${directory.path}/${scriptName.isEmpty ? "新脚本集" : scriptName}.zds');
                await file.writeAsString(scriptContent);
                
                if (!mounted) return;
                await Share.shareXFiles([XFile(file.path)], subject: scriptName);
    } catch (e) {
                debugPrint('Export script error: $e');
                // 使用同步方式显示错误
      if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
        showCupertinoDialog(
                      context: currentContext,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('导出失败'),
                        content: Text('错误信息: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
                  });
      }
    }
            },
          ),
        ],
      ),
    );
  }

  // 添加读取方法
  void _importScripts() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zds'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content = Platform.isIOS 
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();

        final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.isEmpty) throw Exception('文件为空');
        
        setState(() {
          _scripts.clear();
          for (var line in lines) {
            try {
              final data = json.decode(line);
              if (data['脚本类型'] == '全局变量') {
                // 更新全局设置
                _executionDelay = data['执行延迟'] ?? 1000;
                // 处理时间单位
                final timeUnitLabel = data['时间单位'] ?? '毫秒';
                _delayTimeUnit = TimeUnit.values.firstWhere(
                  (unit) => unit.label == timeUnitLabel,
                  orElse: () => TimeUnit.milliseconds,
                );
                // 转换延迟值
                _executionDelay *= _delayTimeUnit.multiplier;
                _originalLoopCount = data['循环次数'] ?? 1;
            _remainingLoopCount = _originalLoopCount;
              } else {
                _scripts.add(Script.fromJson(line));
              }
            } catch (e) {
              debugPrint('Parse script error: $e');
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
    _saveBookmarksAndHistory();
  }

  // 修改 URL 输入状态处理
  void _showUrlInput() {
    if (!_tabs.isNotEmpty || _currentIndex < 0 || _currentIndex >= _tabs.length) return;
    
    final tab = _tabs[_currentIndex];
    // 检查是否是默认页面或本地文件
    final isDefaultPage = tab.url == 'about:blank' || tab.url.startsWith('file:///');
    
    showCupertinoModalPopup(
      context: context,
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
                        )..selection = TextSelection(
                              baseOffset: 0,
                          extentOffset: isDefaultPage ? 0 : tab.url.length,
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
                            item.title.isEmpty ? '无标题' : item.title,
                            style: const TextStyle(color: CupertinoColors.white),
                          ),
                          subtitle: Text(
                            item.url,
                            style: const TextStyle(color: CupertinoColors.systemGrey),
                          ),
                          onTap: () {
                            _tabs[_currentIndex].controller.loadRequest(Uri.parse(item.url));
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

  // 修改获取显示文本的方法
  String _getDisplayTitle() {
    if (!_tabs.isNotEmpty || _currentIndex < 0 || _currentIndex >= _tabs.length) {
      return '欢迎使用';
    }
    
    final tab = _tabs[_currentIndex];
    final url = tab.url;
    
    // 处理默认页面
    if (url == 'about:blank' || url.startsWith('file:///')) {
      return '欢迎使用';
    }
    
    // 使用网页标题，如果没有则显示"无标题"
    return tab.title.isNotEmpty ? tab.title : '无标题';
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
    _saveBookmarksAndHistory();
  }

  void _clearScripts() {
    if (!mounted) return;
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
                '${_executionDelay ~/ _delayTimeUnit.multiplier} ${_delayTimeUnit.label}',
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


  void _showDelaySettingDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: const Text('执行延迟'),
          content: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: CupertinoTextField(
                  controller: TextEditingController(text: (_executionDelay ~/ _delayTimeUnit.multiplier).toString()),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  placeholder: '请输入延迟时间',
                  onChanged: (value) {
                    final delay = int.tryParse(value);
                    if (delay != null && delay > 0) {
                      this.setState(() => _executionDelay = delay * _delayTimeUnit.multiplier);
                    }
                  },
                ),
              ),
              CupertinoButton(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_delayTimeUnit.label),
                    const Icon(CupertinoIcons.chevron_down, size: 16),
                  ],
                ),
                onPressed: () {
                  showCupertinoModalPopup(
                    context: context,
                    builder: (context) => Container(
                      height: 200,
                      color: CupertinoColors.systemBackground.darkColor,
                      child: CupertinoPicker(
                        backgroundColor: CupertinoColors.black,
                        itemExtent: 32,
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _delayTimeUnit = TimeUnit.values[index];
                            // 转换当前延迟值到新单位
                            _executionDelay = (_executionDelay ~/ _delayTimeUnit.multiplier) * _delayTimeUnit.multiplier;
                          });
                        },
                        children: TimeUnit.values.map((unit) => 
                          Text(unit.label, style: const TextStyle(color: CupertinoColors.white))
                        ).toList(),
                      ),
                    ),
                  );
                },
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
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
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


  Widget _buildScriptItem(Script script, int index) {
    return GestureDetector(
      onTap: () => _showAddOrEditScript(script: script),  // 添加短按编辑功能
      onLongPress: () {
        // 保持原有的长按菜单功能
        showCupertinoModalPopup(
          context: context,
          builder: (context) => CupertinoActionSheet(
            actions: [
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _scripts.removeAt(index);
                  });
                },
                isDestructiveAction: true,
                child: const Text('删除'),
              ),
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _scripts.insert(index + 1, Script(
                      type: script.type,
                      params: Map<String, dynamic>.from(script.params),
                      mode: script.mode,
                    ));
                  });
                },
                child: const Text('复制'),
              ),
              if (index > 0)
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      final item = _scripts.removeAt(index);
                      _scripts.insert(index - 1, item);
                    });
                  },
                  child: const Text('上移'),
                ),
              if (index < _scripts.length - 1)
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      final item = _scripts.removeAt(index);
                      _scripts.insert(index + 1, item);
                    });
                  },
                  child: const Text('下移'),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
        );
      },
      child: Container(
        // 保持原有的脚本项UI不变
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.white.withAlpha(200),
            ),
          ),
        ),
        child: Row(
          children: [
            CupertinoSwitch(
              value: script.isEnabled,
              onChanged: (value) {
                setState(() => script.isEnabled = value);
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    script.type,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${script.mode.label} - ${_getScriptDescription(script)}',
                    style: TextStyle(
                      color: CupertinoColors.white.withAlpha(200),
                      fontSize: 14,
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

  // 添加辅助方法来生成脚本描述
  String _getScriptDescription(Script script) {
    if (script.type == "点击文字") {
      switch (script.mode) {
        case ScriptMode.simple:
          return '点击: ${script.params['点击文字']}';
        case ScriptMode.normal:
          return '点击: ${script.params['点击文字']}, 延迟: ${script.params['执行延迟']}${script.params['时间单位']}';
        case ScriptMode.expert:
          return '点击: ${script.params['点击文字']}, 筛选: ${script.params['多个筛选']}';
      }
    }
    return '';
  }


  Future<bool> _canGoBack() async {
    if (_tabs.isEmpty || _currentIndex < 0) return false;
    return await _tabs[_currentIndex].controller.canGoBack();
  }

  Future<bool> _canGoForward() async {
    if (_tabs.isEmpty || _currentIndex < 0) return false;
    return await _tabs[_currentIndex].controller.canGoForward();
  }

  void _showSettings() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: CupertinoColors.black.withAlpha(230),  // 修改背景色为半透明黑色
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              // 顶部标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.white,  // 添加文字颜色
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Text('完成'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 1,
                color: CupertinoColors.systemGrey4,  // 添加分割线颜色
              ),
              // 设置项列表
              Expanded(
                child: ListView(
                  children: [
                    // 显示设置组
                    _buildSettingGroup(children: [
                      _buildSettingItem(
                        title: '全屏',
                        trailing: CupertinoSwitch(
                          value: _isFullScreen,
                          onChanged: (value) {
                            setState(() => _isFullScreen = value);
                            this.setState(() {});
                            // 立即应用全屏效果
                            SystemChrome.setEnabledSystemUIMode(
                              value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
                            );
                          },
                        ),
                      ),
                      _buildSettingItem(
                        title: '夜间模式',
                        trailing: CupertinoSwitch(
                          value: _isDarkMode,
                          onChanged: (value) {
                            setState(() => _isDarkMode = value);
                            this.setState(() {});
                            // 立即应用夜间模式
                            _applyDarkMode(value);
                          },
                        ),
                      ),
                      _buildSettingItem(
                        title: '屏幕常亮',
                        trailing: CupertinoSwitch(
                          value: _keepScreenOn,
                          onChanged: (value) async {
                            setState(() => _keepScreenOn = value);
                            if (value) {
                              await WakelockPlus.enable();
    } else {
                              await WakelockPlus.disable();
                            }
                          },
                        ),
                        subtitle: const Text(
                          '建议开启，以避免黑屏可能导致脚本执行变慢等情况',
                          style: TextStyle(
                            color: CupertinoColors.systemGrey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      _buildSettingItem(
                        title: '离开模式',
                        trailing: CupertinoSwitch(
                          value: _autoLeaveMode,
                          onChanged: (value) {
                            setState(() => _autoLeaveMode = value);
                            this.setState(() {});
                            _toggleLeaveMode(value);
                          },
                        ),
                        subtitle: const Text(
                          '主页面3分钟无操作后，自动进入离开模式(脚本仍正常运行)，可省电、防止浏览器假死',
                          style: TextStyle(
                            color: CupertinoColors.systemGrey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ]),

                    // 关于
                    _buildSettingGroup(children: [
                      _buildSettingItem(
                        title: '关于Auok浏览器',
                        trailing: const Icon(
                          CupertinoIcons.forward,
                          color: CupertinoColors.systemGrey,
                          size: 20,
                        ),
                        onTap: () {
                          Navigator.pop(context);  // 先关闭设置页面
                          _showAboutDialog();     // 再显示关于弹窗
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingGroup({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),  // 添加水平边距
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.withOpacity(0.2),  // 修改组背景色
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingItem({
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    Widget? subtitle,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.systemGrey5,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: CupertinoColors.white,  // 修改标题文字颜色
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    subtitle,
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Future<String> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  // 修改 _showAboutDialog 方法为异步方法
  void _showAboutDialog() async {
    final version = await _getAppVersion();
    if (!mounted) return;
    
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Auok浏览器'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              '版本：$version',
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Auok浏览器是一个iOS端脚本自动化的浏览器，你可以用它在wap游戏页面中实现自动化的功能。',
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // 修改夜间模式的实现
  void _applyDarkMode(bool isDark) {
    if (_tabs.isEmpty || _currentIndex < 0) return;
    
    _tabs[_currentIndex].controller.runJavaScript('''
      (function() {
        const existingStyle = document.getElementById('dark-mode-style');
        if (existingStyle) {
          existingStyle.remove();
        }
        
        if ($isDark) {
          const style = document.createElement('style');
          style.id = 'dark-mode-style';
          style.textContent = `
            /* 基础样式 */
            html, body {
              background: #292929 !important;
              color: #a7a7a7 !important;
            }
            
            /* 移除所有阴影效果 */
            * {
              text-shadow: none !important;
              box-shadow: none !important;
            }
            
            /* 文本元素 */
            h1, h2, h3, h4, h5, h6, p, span, div, 
            li, td, th, label, input, textarea, 
            button, select, option {
              background-color: #292929 !important;
              color: #a7a7a7 !important;
            }
            
            /* 链接样式 */
            a, a * {
              color: #6d97d5 !important;
            }
            
            a:visited, a:visited * {
              color: #bd8cff !important;
            }
            
            /* 输入框和按钮 */
            input, textarea, select, button {
              background-color: #292929 !important;
              color: #b0b0b0 !important;
              border-color: #45484c !important;
            }
            
            /* 表格边框 */
            table, th, td {
              border-color: #45484c !important;
            }
            
            /* 图片和背景图片 */
            img, video, [style*="background-image"] {
              filter: brightness(0.8);
            }
            
            /* 伪元素 */
            :after, :before {
              -webkit-filter: brightness(0.4);
            }
            
            /* 透明背景元素 */
            [style*="background-color: transparent"] {
              background-color: transparent !important;
            }
            
            /* 确保所有背景色 */
            div:not([style*="background-color: transparent"]),
            section:not([style*="background-color: transparent"]),
            nav:not([style*="background-color: transparent"]),
            header:not([style*="background-color: transparent"]),
            footer:not([style*="background-color: transparent"]) {
              background-color: #292929 !important;
            }
          `;
          document.head.appendChild(style);
        }
      })();
    ''');
  }

  // 显示离开模式遮罩
  void _showLeaveMode() {
    setState(() {
      _showLeaveModeOverlay = true;
    });
  }

  // 隐藏离开模式遮罩
  void _hideLeaveMode() {
    setState(() {
      _showLeaveModeOverlay = false;
    });
  }

  // 修改执行脚本的方法
  Future<bool> _executeScripts() async {
    if (_scripts.isEmpty) return true;
    
    setState(() {
      _isExecuting = true;
      _successCount = 0;
      _failureCount = 0;
      _currentScriptIndex = 0;
      _remainingLoopCount = _originalLoopCount;  // 重置剩余循环次数
    });
    
    _resetInactivityTimer();
    
    while (_originalLoopCount == 0 || _remainingLoopCount > 0) {
      if (!_isExecuting) break;
      
      for (var i = 0; i < _scripts.length && _isExecuting; i++) {
        await Future.delayed(Duration(milliseconds: _executionDelay));
        
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
        } catch (e) {
          setState(() => _failureCount++);
          debugPrint('Execute script error: $e');
        }
      }
      
      if (_originalLoopCount > 0) {
        setState(() {
          _remainingLoopCount--;
        });
      }
    }
    
    setState(() {
      _isExecuting = false;
      _currentScriptIndex = 0;
    });
    
    _resetInactivityTimer();
    return _successCount > 0;
  }

  // 添加脚本编辑对话框
  void _showAddOrEditScript({Script? script}) {
    String type = script?.type ?? "点击文字";
    ScriptMode mode = script?.mode ?? ScriptMode.simple;
    Map<String, dynamic> params = script?.params ?? {};
    
    showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: Text(script == null ? '添加脚本' : '编辑脚本'),
          content: Column(
            children: [
              // 类型和模式选择行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 类型选择
                  Expanded(
                    child: _buildTypeSelector(
                      type,
                      (newType) => setState(() {
                        type = newType;
                        // 重置模式和参数
                        mode = ScriptMode.simple;
                        params = {};
                      }),
                    ),
                  ),
                  // 模式选择
                  Expanded(
                    child: _buildModeSelector(
                      type,
                      mode,
                      (newMode) => setState(() => mode = newMode),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 根据类型和模式显示不同的参数输入界面
              if (type == "点击文字") ...[
                // 简单模式
                if (mode == ScriptMode.simple)
                  _buildSimpleClickParams(params, (key, value) {
                    setState(() => params[key] = value);
                  }),
                
                // 普通模式
                if (mode == ScriptMode.normal)
                  _buildNormalClickParams(params, (key, value) {
                    setState(() => params[key] = value);
                  }),
                
                // 专家模式
                if (mode == ScriptMode.expert)
                  _buildExpertClickParams(params, (key, value) {
                    setState(() => params[key] = value);
                  }),
              ],
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
                final newScript = Script(
                  type: type,
                  params: params,
                  mode: mode,
                  isEnabled: script?.isEnabled ?? true,
                );
                
                setState(() {
                  if (script == null) {
                    _scripts.add(newScript);
                  } else {
                    final index = _scripts.indexOf(script);
                    _scripts[index] = newScript;
                  }
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 构建不同模式的参数输入界面
  Widget _buildSimpleClickParams(Map<String, dynamic> params, Function(String, dynamic) onChanged) {
    return CupertinoTextField(
      placeholder: '点击文字',
      controller: TextEditingController(text: params['点击文字'] ?? ''),
      onChanged: (value) => onChanged('点击文字', value),
    );
  }

  Widget _buildNormalClickParams(Map<String, dynamic> params, Function(String, dynamic) onChanged) {
    return Column(
      children: [
        _buildDelayInput(params, onChanged),
        const SizedBox(height: 8),
        _buildTextField('出现文字', params['出现文字'] ?? '', 
          '多个关键词用;分隔', onChanged),
        const SizedBox(height: 8),
        _buildTextField('点击文字', params['点击文字'] ?? '',
          '多个文字用;分隔', onChanged),
        const SizedBox(height: 8),
        _buildSwitch('完全匹配', params['完全匹配'] ?? false, onChanged),
      ],
    );
  }

  Widget _buildExpertClickParams(Map<String, dynamic> params, Function(String, dynamic) onChanged) {
    return Column(
      children: [
        _buildDelayInput(params, onChanged),
        const SizedBox(height: 8),
        _buildTextField('出现文字', params['出现文字'] ?? '',
          '多个关键词用;分隔', onChanged),
        const SizedBox(height: 8),
        _buildTextField('在此之后', params['在此之后'] ?? '',
          '留空表示从头开始', onChanged),
        const SizedBox(height: 8),
        _buildTextField('在此之前', params['在此之前'] ?? '',
          '留空表示到结尾', onChanged),
        const SizedBox(height: 8),
        _buildTextField('点击文字', params['点击文字'] ?? '',
          '多个文字用;分隔', onChanged),
        const SizedBox(height: 8),
        _buildSwitch('完全匹配', params['完全匹配'] ?? false, onChanged),
        const SizedBox(height: 8),
        _buildTextField('多个筛选', params['多个筛选']?.toString() ?? '1',
          '正数第几个,0随机,负数倒数', onChanged),
      ],
    );
  }

  // 添加辅助方法来构建界面组件
  Widget _buildTypeSelector(String currentType, Function(String) onChanged) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Text(currentType),
          const Icon(CupertinoIcons.chevron_down, size: 16),
        ],
      ),
      onPressed: () {
        showCupertinoModalPopup(
          context: context,
          builder: (context) => Container(
            height: 200,
            color: CupertinoColors.systemBackground.darkColor,
            child: CupertinoPicker(
              backgroundColor: CupertinoColors.black,
              itemExtent: 32,
              onSelectedItemChanged: (index) {
                onChanged(index == 0 ? "点击文字" : "输入框提交");
              },
              children: const [
                Text("点击文字", style: TextStyle(color: CupertinoColors.white)),
                Text("输入框提交", style: TextStyle(color: CupertinoColors.white)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeSelector(String type, ScriptMode currentMode, Function(ScriptMode) onChanged) {
    final modes = type == "点击文字" 
      ? ScriptMode.values 
      : [ScriptMode.simple, ScriptMode.normal];
      
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(currentMode.label),
          const Icon(CupertinoIcons.chevron_down, size: 16),
        ],
      ),
      onPressed: () {
        showCupertinoModalPopup(
          context: context,
          builder: (context) => Container(
            height: 200,
            color: CupertinoColors.systemBackground.darkColor,
            child: CupertinoPicker(
              backgroundColor: CupertinoColors.black,
              itemExtent: 32,
              onSelectedItemChanged: (index) {
                onChanged(modes[index]);
              },
              children: modes.map((m) => Text(
                m.label,
                style: const TextStyle(color: CupertinoColors.white),
              )).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(String label, String value, String placeholder, Function(String, String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: CupertinoColors.white)),
        const SizedBox(height: 4),
        CupertinoTextField(
          placeholder: placeholder,
          controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(
            TextPosition(offset: value.length),  // 保持光标在文本末尾
          ),
          onChanged: (newValue) => onChanged(label, newValue),
          autocorrect: false,  // 禁用自动更正
          enableSuggestions: false,  // 禁用输入建议
          keyboardAppearance: Brightness.dark,  // 使用深色键盘
        ),
      ],
    );
  }

  Widget _buildSwitch(String label, bool value, Function(String, bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: CupertinoColors.white)),
        CupertinoSwitch(
          value: value,
          onChanged: (newValue) => onChanged(label, newValue),
        ),
      ],
    );
  }

  Widget _buildDelayInput(Map<String, dynamic> params, Function(String, dynamic) onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('执行延迟', style: TextStyle(color: CupertinoColors.white)),
              const SizedBox(height: 4),
              CupertinoTextField(
                placeholder: '延迟时间',
                keyboardType: TextInputType.number,
                controller: TextEditingController(
                  text: (params['执行延迟'] ?? 0).toString(),
                )..selection = TextSelection.fromPosition(
                  TextPosition(offset: (params['执行延迟'] ?? 0).toString().length),
                ),
                onChanged: (value) => onChanged('执行延迟', int.tryParse(value) ?? 0),
                autocorrect: false,
                enableSuggestions: false,
                keyboardAppearance: Brightness.dark,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        CupertinoButton(
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              Text(params['时间单位'] ?? '毫秒'),
              const Icon(CupertinoIcons.chevron_down, size: 16),
            ],
          ),
          onPressed: () {
            showCupertinoModalPopup(
              context: context,
              builder: (context) => Container(
                height: 200,
                color: CupertinoColors.systemBackground.darkColor,
                child: CupertinoPicker(
                  backgroundColor: CupertinoColors.black,
                  itemExtent: 32,
                  onSelectedItemChanged: (index) {
                    onChanged('时间单位', TimeUnit.values[index].label);
                  },
                  children: TimeUnit.values.map((unit) => Text(
                    unit.label,
                    style: const TextStyle(color: CupertinoColors.white),
                  )).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

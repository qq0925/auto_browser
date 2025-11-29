import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/script.dart';
import '../services/script_executor.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/browser_tab.dart';

class ScriptProvider extends ChangeNotifier {
  BrowserTab? _currentTab;
  bool _isRecording = false;
  // Removed global _isExecuting - now using per-tab isExecutingScript
  bool _isPaused = false;
  int _currentScriptIndex = 0;
  int _executionDelay = 1000;
  int _originalLoopCount = 1;
  int _remainingLoopCount = 1;
  TimeUnit _delayTimeUnit = TimeUnit.milliseconds;

  int _successCount = 0;
  int _failureCount = 0;

  Future<void> Function()? _waitForPageLoadCallback;

  final ScriptExecutor _executor = ScriptExecutor();

  // Get scripts from current tab
  List<Script> get scripts => _currentTab?.scripts ?? [];
  BrowserTab? get currentTab =>
      _currentTab; // Expose current tab for comparison
  bool get isRecording => _isRecording;
  // Use per-tab execution state instead of global state
  bool get isExecuting => _currentTab?.isExecutingScript ?? false;
  bool get isPaused => _isPaused;
  int get currentScriptIndex => _currentScriptIndex;
  int get executionDelay => _executionDelay;
  int get originalLoopCount => _originalLoopCount;
  int get remainingLoopCount => _remainingLoopCount;
  TimeUnit get delayTimeUnit => _delayTimeUnit;
  int get successCount => _successCount;
  int get failureCount => _failureCount;
  String? get currentScriptFilePath => _currentTab?.scriptFilePath;

  void setWaitForPageLoadCallback(Future<void> Function() callback) {
    _waitForPageLoadCallback = callback;
  }

  // Set current tab to work with
  void setCurrentTab(BrowserTab? tab) {
    _currentTab = tab;
    notifyListeners();
  }

  ScriptProvider() {
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load global settings only (scripts are now tab-specific)
      _executionDelay = prefs.getInt('script_global_delay') ?? 1000;
      _originalLoopCount = prefs.getInt('script_global_loop') ?? 1;
      final unitIndex = prefs.getInt('script_global_unit') ?? 0;
      if (unitIndex >= 0 && unitIndex < TimeUnit.values.length) {
        _delayTimeUnit = TimeUnit.values[unitIndex];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading global settings: $e');
    }
  }

  Future<void> _saveScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save global settings only (scripts are now tab-specific)
      await prefs.setInt('script_global_delay', _executionDelay);
      await prefs.setInt('script_global_loop', _originalLoopCount);
      await prefs.setInt('script_global_unit', _delayTimeUnit.index);
    } catch (e) {
      debugPrint('Error saving global settings: $e');
    }
  }

  void setExecutionDelay(int delay) {
    _executionDelay = delay;
    _saveScripts();
    notifyListeners();
  }

  void setDelayTimeUnit(TimeUnit unit) {
    _delayTimeUnit = unit;
    _saveScripts();
    notifyListeners();
  }

  void setLoopCount(int count) {
    _originalLoopCount = count;
    _remainingLoopCount = count;
    _saveScripts();
    notifyListeners();
  }

  UserScript? _recordingUserScript;

  UserScript get recordingUserScript {
    _recordingUserScript ??= UserScript(
      source: recordingJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
    return _recordingUserScript!;
  }

  void startRecording() {
    // Prevent recording while any tab is executing
    if (_currentTab?.isExecutingScript ?? false) return;
    _isRecording = true;

    // Inject recording script immediately if controller is available
    if (_currentTab?.controller != null) {
      _currentTab!.controller!.evaluateJavascript(source: recordingJs);
      _currentTab!.controller!.addUserScript(userScript: recordingUserScript);
    }

    notifyListeners();
  }

  void stopRecording() {
    _isRecording = false;
    if (_currentTab?.controller != null) {
      _currentTab!.controller!
          .removeUserScript(userScript: recordingUserScript);
    }
    notifyListeners();
  }

  void clearScripts() {
    if (_currentTab != null) {
      _currentTab!.scripts.clear();
      notifyListeners();
    }
  }

  void addScript(Script script) {
    if (_currentTab != null) {
      _currentTab!.scripts.add(script);
      notifyListeners();
    }
  }

  void removeScript(int index) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      _currentTab!.scripts.removeAt(index);
      notifyListeners();
    }
  }

  void toggleScriptEnabled(int index, bool value) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      _currentTab!.scripts[index].isEnabled = value;
      notifyListeners();
    }
  }

  // Insert script at specific index
  void insertScript(int index, Script script) {
    if (_currentTab != null &&
        index >= 0 &&
        index <= _currentTab!.scripts.length) {
      _currentTab!.scripts.insert(index, script);
      notifyListeners();
    }
  }

  // Duplicate (copy) a script
  Script? duplicateScript(int index) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      final original = _currentTab!.scripts[index];
      return Script(
        type: original.type,
        params: Map<String, dynamic>.from(original.params),
        isEnabled: original.isEnabled,
      );
    }
    return null;
  }

  // Update the script file path for the current tab
  void updateScriptFilePath(String? filePath) {
    if (_currentTab != null) {
      _currentTab!.scriptFilePath = filePath;
      notifyListeners();
    }
  }

  // Stream controller for last recorded action to trigger UI animation
  final _lastRecordedActionController = StreamController<String>.broadcast();
  Stream<String> get lastRecordedActionStream =>
      _lastRecordedActionController.stream;

  void recordAction(String actionType, [String? detail]) {
    if (!_isRecording) return;

    String actionDescription = '';

    switch (actionType) {
      case '网页后退':
        addScript(Script(type: '网页后退', params: {}, isEnabled: true));
        actionDescription = '网页后退';
        break;
      case '网页前进':
        addScript(Script(type: '网页前进', params: {}, isEnabled: true));
        actionDescription = '网页前进';
        break;
      case '刷新网页':
        addScript(Script(type: '刷新网页', params: {}, isEnabled: true));
        actionDescription = '刷新网页';
        break;
      case '进入网址':
        if (detail != null && detail.isNotEmpty) {
          addScript(
              Script(type: '进入网址', params: {'网址': detail}, isEnabled: true));
          actionDescription = '进入网址: $detail';
        }
        break;
      case '点击图片':
        addScript(Script(type: '点击图片', params: {}, isEnabled: true));
        actionDescription = '点击图片';
        break;
    }

    if (actionDescription.isNotEmpty) {
      _lastRecordedActionController.add(actionDescription);
    }
  }

  void handleScriptMessage(String message) {
    if (!_isRecording) return;

    final separatorIndex = message.indexOf('|');
    if (separatorIndex == -1) return;

    final type = message.substring(0, separatorIndex);
    final content = message.substring(separatorIndex + 1);

    switch (type) {
      case '点击文字':
        // Now only records link clicks (improved detection in JS)
        addScript(Script(
          type: '点击文字',
          params: {'点击文本': content},
          isEnabled: true,
        ));
        _lastRecordedActionController.add('点击文字: $content');
        break;

      case '点击提交按钮':
        try {
          final data = json.decode(content) as Map<String, dynamic>;
          final buttonText = data['按钮文本'] as String? ?? '提交';
          final formData = data['表单数据'];

          addScript(Script(
            type: '输入框提交',
            params: {
              '提交按钮文字': buttonText,
              '表单数据': formData ?? {},
            },
            isEnabled: true,
          ));
          _lastRecordedActionController.add('输入框提交: $buttonText');
        } catch (e) {
          debugPrint('Parse submit button data error: $e');
        }
        break;

      case '点击图片':
        // Image click from JS with optional src
        addScript(Script(
          type: '点击图片',
          params: content.isNotEmpty ? {'图片地址': content} : {},
          isEnabled: true,
        ));
        _lastRecordedActionController.add('点击图片');
        break;
    }
  }

  void updateScript(int index, Script script) {
    if (_currentTab != null &&
        index >= 0 &&
        index < _currentTab!.scripts.length) {
      _currentTab!.scripts[index] = script;
      notifyListeners();
    }
  }

  Future<void> startExecution(InAppWebViewController controller) async {
    if (_currentTab == null || _currentTab!.scripts.isEmpty || _isRecording) {
      return;
    }

    // Lock execution to this specific tab (not _currentTab which can change)
    final executingTab = _currentTab!;
    final executingController = controller;

    // Mark tab as executing (use tab-specific state)
    executingTab.isExecutingScript = true;
    _isPaused = false;
    _currentScriptIndex = 0;
    _remainingLoopCount = _originalLoopCount;
    executingTab.currentScriptIndex = 0;
    executingTab.successCount = 0;
    executingTab.failureCount = 0;
    executingTab.remainingLoopCount = _remainingLoopCount;

    // Reset status and counts
    _successCount = 0;
    _failureCount = 0;
    for (var script in executingTab.scripts) {
      script.status = ScriptStatus.idle;
      script.statusMessage = null;
    }
    notifyListeners();

    // Loop execution: 0 means infinite loop, otherwise loop the specified times
    while (executingTab.isExecutingScript &&
        (_originalLoopCount == 0 || _remainingLoopCount > 0)) {
      for (var i = 0; i < executingTab.scripts.length; i++) {
        if (!executingTab.isExecutingScript) break;

        // Handle pause
        while (_isPaused && executingTab.isExecutingScript) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        _currentScriptIndex = i;
        executingTab.currentScriptIndex = i;
        notifyListeners();

        final script = executingTab.scripts[i];
        if (script.isEnabled) {
          await _executor.execute(
            executingController,
            script,
            executionDelay: _executionDelay,
            onStatusChanged: (status, message, progress) {
              script.status = status;
              script.statusMessage = message;
              script.progress = progress;

              if (status == ScriptStatus.success) {
                _successCount++;
                executingTab.successCount++;
              } else if (status == ScriptStatus.failure) {
                _failureCount++;
                executingTab.failureCount++;
              }

              notifyListeners();
            },
            waitForPageLoad: _waitForPageLoadCallback,
          );
        }

        // Global delay between scripts is now handled inside execute (before execution)
        // so we don't need it here.
      }

      // Only decrement if not in infinite loop mode (0 = infinite)
      if (executingTab.isExecutingScript && _originalLoopCount > 0) {
        _remainingLoopCount--;
        executingTab.remainingLoopCount = _remainingLoopCount;
        notifyListeners();
      }
    }

    // Clear execution state
    _currentScriptIndex = 0;
    executingTab.isExecutingScript = false;
    executingTab.currentScriptIndex = 0;
    notifyListeners();
  }

  void stopExecution() {
    if (_currentTab != null) {
      _currentTab!.isExecutingScript = false;
    }
    _isPaused = false;
    notifyListeners();
  }

  void pauseExecution() {
    _isPaused = true;
    notifyListeners();
  }

  void resumeExecution() {
    _isPaused = false;
    notifyListeners();
  }

  String exportScript() {
    if (_currentTab == null) return '[]';

    final List<Map<String, dynamic>> jsonList = [];

    // Add global settings
    jsonList.add({
      '脚本类型': '全局设置',
      '执行延迟': _executionDelay ~/ _delayTimeUnit.multiplier,
      // Note: User JSON example used '执行延迟' for global delay, assuming unit is implied or standard.
      // But to be safe and consistent with my internal logic, I'll save what I have.
      // The user example: "执行延迟": 1000.
    });

    for (var script in _currentTab!.scripts) {
      if (script.isEnabled) {
        jsonList.add(script.toUserMap());
      }
    }

    return json.encode(jsonList);
  }

  void importScript(String content) {
    if (_currentTab == null) return;

    try {
      final List<dynamic> jsonList = json.decode(content);
      _currentTab!.scripts.clear();

      for (var item in jsonList) {
        if (item is! Map<String, dynamic>) continue;

        final type = item['脚本类型'];
        if (type == '全局设置') {
          final delay = item['执行延迟'] as int? ?? 1000;
          // User JSON doesn't explicitly show unit, assuming milliseconds or matching current logic.
          // If the user JSON implies milliseconds:
          _executionDelay = delay;
          // If we want to respect the unit, we might need to infer or default.
          // Let's assume milliseconds for now as per "执行延迟": 1000 (1 second).
          _delayTimeUnit = TimeUnit.milliseconds;

          // User JSON didn't show loop count in global settings example, but if it exists:
          if (item.containsKey('循环次数')) {
            _originalLoopCount = item['循环次数'] as int;
          }
        } else {
          try {
            _currentTab!.scripts.add(Script.fromUserMap(item));
          } catch (e) {
            debugPrint('Parse script item error: $e');
          }
        }
      }
      _saveScripts();
      notifyListeners();
    } catch (e) {
      debugPrint('Import script error: $e');
      // Fallback to old line-by-line format if JSON decode fails
      _importScriptLegacy(content);
    }
  }

  void _importScriptLegacy(String content) {
    if (_currentTab == null) return;

    try {
      final lines = content.split('\n');
      _currentTab!.scripts.clear();

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final script = Script.fromJson(line);
          if (script.type == '全局变量') {
            // Legacy global settings logic
            final delay = script.params['执行延迟'] as int;
            final unitLabel = script.params['时间单位'] as String;
            final loop = script.params['循环次数'] as int;
            _delayTimeUnit = TimeUnit.values.firstWhere(
              (u) => u.label == unitLabel,
              orElse: () => TimeUnit.milliseconds,
            );
            _executionDelay = delay * _delayTimeUnit.multiplier;
            _originalLoopCount = loop;
          } else {
            _currentTab!.scripts.add(script);
          }
        } catch (e) {
          debugPrint('Legacy parse error: $e');
        }
      }
      _saveScripts();
      notifyListeners();
    } catch (e) {
      debugPrint('Legacy import error: $e');
    }
  }

  static const String recordingJs = '''
    (function() {
      if (window._auokRecorderInjected) return;
      window._auokRecorderInjected = true;

      document.addEventListener('click', function(e) {
        let target = e.target;
        
        // Handle text nodes (nodeType 3)
        if (target.nodeType === 3) {
          target = target.parentElement;
        }
        
        if (!target) return;

        // Priority 1: Check if it's an image
        if (target.tagName === 'IMG') {
          ScriptRunner.postMessage('点击图片|' + (target.src || ''));
          return;
        }

        // Check if target or parent has background image
        let isBgImage = false;
        try {
          let computedStyle = window.getComputedStyle(target);
          isBgImage = computedStyle.backgroundImage !== 'none';
          
          if (!isBgImage && target.parentElement) {
            computedStyle = window.getComputedStyle(target.parentElement);
            isBgImage = computedStyle.backgroundImage !== 'none';
          }
        } catch (e) {}
        
        if (isBgImage) {
          ScriptRunner.postMessage('点击图片|');
          return;
        }

        // Priority 2: Check if it's a link (or element within a link)
        let linkElement = target.closest('a');
        if (linkElement && linkElement.href) {
          let linkText = linkElement.innerText || linkElement.textContent || '';
          linkText = linkText.trim().substring(0, 50);
          if (linkText) {
            ScriptRunner.postMessage('点击文字|' + linkText);
            return;
          }
        }

        // Priority 3: Check if it's a submit button
        let isSubmitButton = false;
        let submitElement = null;
        
        if (target.tagName === 'BUTTON') {
          if (target.type === 'submit' || !target.type) {
            isSubmitButton = true;
            submitElement = target;
          }
        } else if (target.tagName === 'INPUT' && target.type === 'submit') {
          isSubmitButton = true;
          submitElement = target;
        } else {
          // Check if clicked element is inside a submit button
          submitElement = target.closest('button[type="submit"], input[type="submit"]');
          if (!submitElement) {
            submitElement = target.closest('button:not([type])');
          }
          if (submitElement) {
            isSubmitButton = true;
          }
        }

        if (isSubmitButton && submitElement) {
          // Find the form
          let form = submitElement.closest('form');
          if (form) {
            // Collect form data
            let formData = {};
            let inputs = form.querySelectorAll('input, textarea, select');
            
            inputs.forEach(function(input) {
              // Skip hidden, button, submit, reset, image, search types
              if (input.type === 'hidden' || 
                  input.type === 'button' || 
                  input.type === 'submit' ||
                  input.type === 'reset' ||
                  input.type === 'image') {
                return;
              }
              
              // Only save fields with name attribute (not id)
              // Allow empty values to support clearing fields
              if (input.name) {
                formData[input.name] = input.value;
              }
            });

            // Get button text
            let buttonText = '';
            if (submitElement.tagName === 'INPUT') {
              buttonText = submitElement.value || '提交';
            } else {
              buttonText = submitElement.innerText || submitElement.textContent || '提交';
            }
            buttonText = buttonText.trim();

            let data = {
              '按钮文本': buttonText,
              '表单数据': formData
            };
            
            ScriptRunner.postMessage('点击提交按钮|' + JSON.stringify(data));
            return;
          }
        }
      }, true);
    })();
  ''';
}

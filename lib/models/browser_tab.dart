import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'script.dart';

import 'dart:async';

class BrowserTab {
  final String id;

  InAppWebViewController? controller;

  String title; // 网页标题

  String url; // 网页URL

  bool isLoading; // 加载状态

  bool isExecutingScript; // 是否正在执行脚本

  bool isPaused = false; // 是否处于暂停状态

  int currentScriptIndex = 0; // 当前执行的脚本索引

  int successCount = 0; // 成功执行的脚本计数

  int failureCount = 0; // 失败执行的脚本计数

  int remainingLoopCount = 1; // 剩余循环次数

  int originalLoopCount = 1; // 初始总循环次数（0为无限）

  int currentLoopIndex = 1; // 当前循环轮次（从1开始）

  int completedLoopCount = 0; // 已执行的完整循环轮次

  int executionDelay = 0; // 全局执行延迟（毫秒）

  String delayTimeUnit = '毫秒'; // 延迟单位

  List<Script> scripts = []; // 添加每个标签页自己的脚本列表

  double progress; // 网页加载进度

  String? scriptFilePath; // 脚本的物理文件路径，null表示未保存

  bool canGoBack = false;

  bool canGoForward = false;

  String? customName; // 自定义窗口名称

  String? customUserAgent; // 自定义UA（可为预设键名或完整UA字符串，null表示继承全局设置）
  String proxyMode; // 代理模式：关闭 / wap代理 / 自定义
  String proxyHost; // 代理服务器地址
  String proxyPort; // 代理服务器端口
  String proxyUsername; // 代理登录用户名
  String proxyPassword; // 代理登录密码

  /// 是否已启用有效代理配置
  bool get hasProxy => resolvedProxyAddress != null;

  /// 解析当前生效的代理地址 (host:port)
  String? get resolvedProxyAddress {
    if (proxyMode == 'wap代理') {
      return '10.0.0.172:80';
    }
    if (proxyMode == '自定义') {
      final host = proxyHost.trim();
      final port = proxyPort.trim();
      if (host.isNotEmpty && port.isNotEmpty) {
        return '$host:$port';
      }
    }
    return null;
  }

  /// 用于检测代理配置是否变化的签名
  String get proxySignature =>
      '${resolvedProxyAddress ?? ''}|$proxyUsername|$proxyPassword';

  int loadStartEpoch = 0; // 页面开始加载事件序号

  int loadStopEpoch = 0; // 页面加载完成事件序号

  Completer<void>? _loadStartCompleter;

  Completer<void>? _loadStopCompleter;

  /// 标记页面开始加载（由 WebView onLoadStart 调用）

  void markLoadStarted() {
    isLoading = true;

    loadStartEpoch++;

    if (_loadStartCompleter != null && !_loadStartCompleter!.isCompleted) {
      _loadStartCompleter!.complete();
    }

    _loadStartCompleter = null;

    if (_loadStopCompleter == null || _loadStopCompleter!.isCompleted) {
      _loadStopCompleter = Completer<void>();
    }
  }

  /// 标记页面加载完成（由 WebView onLoadStop / 主文档加载失败调用）

  void markLoadStopped() {
    isLoading = false;

    loadStopEpoch++;

    if (_loadStopCompleter != null && !_loadStopCompleter!.isCompleted) {
      _loadStopCompleter!.complete();
    }

    _loadStopCompleter = null;
  }

  /// 等待下一次 onLoadStart 事件触发（用于点击链接后探测页面是否开始跳转）

  Future<bool> waitForLoadStartEvent(
      {Duration timeout = const Duration(milliseconds: 120)}) async {
    if (isLoading) return true;

    _loadStartCompleter ??= Completer<void>();

    try {
      await _loadStartCompleter!.future.timeout(timeout);

      return true;
    } catch (_) {
      return isLoading;
    }
  }

  /// 等待当前正在加载的页面触发 onLoadStop（0ms 事件驱动唤醒）

  Future<void> waitForLoadStopEvent(
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (!isLoading) return;

    _loadStopCompleter ??= Completer<void>();

    try {
      await _loadStopCompleter!.future.timeout(timeout);
    } catch (_) {}
  }

  /// 已执行完整循环轮次展示文本（如 1/100 或 2/∞）

  String get completedLoopProgressText {
    final totalLoopStr = originalLoopCount == 0 ? '∞' : '$originalLoopCount';

    return '$completedLoopCount/$totalLoopStr';
  }

  /// 格式化执行状态简报（如图片样式：延迟:1秒,全局:58/无限,列表:1/2）

  String get executionStatusSummary {
    if (!isExecutingScript) return '';

    final delayText = _formatDelay(executionDelay, delayTimeUnit);

    final delayPart = '延迟:$delayText,';

    final totalLoopStr = originalLoopCount == 0 ? '无限' : '$originalLoopCount';

    final loopPart = '全局:$currentLoopIndex/$totalLoopStr';

    final totalScripts = scripts.length;

    final currentScriptNum =
        totalScripts == 0 ? 0 : (currentScriptIndex + 1).clamp(1, totalScripts);

    final listPart = '列表:$currentScriptNum/$totalScripts';

    final pausePrefix = isPaused ? '[暂停] ' : '';

    return '$pausePrefix$delayPart$loopPart,$listPart';
  }

  static String _formatDelay(int delay, String unit) {
    if (delay == 0) return '0秒';

    if (unit == '秒') {
      if (delay % 1000 == 0) return '${delay ~/ 1000}秒';

      return '${(delay / 1000).toStringAsFixed(1)}秒';
    }

    if (unit == '分' || unit == '分钟') {
      if (delay % 60000 == 0) return '${delay ~/ 60000}分';

      return '${(delay / 60000).toStringAsFixed(1)}分';
    }

    if (delay % 60000 == 0 && delay >= 60000) {
      return '${delay ~/ 60000}分';
    }

    if (delay % 1000 == 0 && delay >= 1000) {
      return '${delay ~/ 1000}秒';
    }

    return '${delay}ms';
  }

  // Call Stack for Subroutines

  List<ExecutionState> executionStack = [];

  // Auto Refresh

  Timer? _autoRefreshTimer;

  bool isAutoRefreshActive = false;

  int autoRefreshInterval = 0; // in seconds

  int autoRefreshCount = 0; // 0 means infinite

  int _currentRefreshCount = 0;

  BrowserTab({
    required this.id,
    this.controller,
    this.title = '新标签页',
    this.url = 'about:blank',
    this.isLoading = false,
    this.isExecutingScript = false,
    this.isPaused = false,
    this.progress = 0.0,
    this.customName,
    this.customUserAgent,
    this.proxyMode = '关闭',
    this.proxyHost = '',
    this.proxyPort = '',
    this.proxyUsername = '',
    this.proxyPassword = '',
  });

  void setController(InAppWebViewController newController) {
    controller = newController;
  }

  void startAutoRefresh(int intervalSeconds, int count) {
    stopAutoRefresh();

    autoRefreshInterval = intervalSeconds;

    autoRefreshCount = count;

    _currentRefreshCount = 0;

    isAutoRefreshActive = true;

    _autoRefreshTimer =
        Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (count > 0 && _currentRefreshCount >= count) {
        stopAutoRefresh();

        return;
      }

      controller?.reload();

      _currentRefreshCount++;
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();

    _autoRefreshTimer = null;

    isAutoRefreshActive = false;
  }
}

class ExecutionState {
  final List<Script> scripts;

  final int currentScriptIndex;

  final int remainingLoopCount;

  final int? currentLoopIndex;

  final int? completedLoopCount;

  final String? scriptFilePath;

  ExecutionState({
    required this.scripts,
    required this.currentScriptIndex,
    required this.remainingLoopCount,
    this.currentLoopIndex,
    this.completedLoopCount,
    this.scriptFilePath,
  });
}

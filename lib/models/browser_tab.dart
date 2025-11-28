import 'package:webview_flutter/webview_flutter.dart';
import 'script.dart';
import 'dart:async';

class BrowserTab {
  final String id;
  final WebViewController controller;
  String title; // 网页标题
  String url; // 网页URL
  bool isLoading; // 加载状态
  bool isExecutingScript; // 是否正在执行脚本
  int currentScriptIndex = 0; // 当前执行的脚本索引
  int successCount = 0; // 成功执行的脚本计数
  int failureCount = 0; // 失败执行的脚本计数
  int remainingLoopCount = 1; // 剩余循环次数
  List<Script> scripts = []; // 添加每个标签页自己的脚本列表
  double progress; // 网页加载进度

  // Auto Refresh
  Timer? _autoRefreshTimer;
  bool isAutoRefreshActive = false;
  int autoRefreshInterval = 0; // in seconds
  int autoRefreshCount = 0; // 0 means infinite
  int _currentRefreshCount = 0;

  // Script Settings
  int executionDelay = 1000;
  int originalLoopCount = 1;
  TimeUnit delayTimeUnit = TimeUnit.milliseconds;

  BrowserTab({
    required this.id,
    required this.controller,
    this.title = 'New Tab',
    this.url = 'about:blank',
    this.isLoading = false,
    this.isExecutingScript = false,
    this.progress = 0.0,
    this.scripts = const [],
  });

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
      controller.reload();
      _currentRefreshCount++;
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    isAutoRefreshActive = false;
  }
}

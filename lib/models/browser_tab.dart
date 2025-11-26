import 'package:webview_flutter/webview_flutter.dart';
import 'script.dart';

class BrowserTab {
  final String id;
  final WebViewController controller;
  String title;    // 网页标题
  String url;      // 网页URL
  bool isLoading;  // 加载状态
  bool isExecutingScript;  // 是否正在执行脚本
  int currentScriptIndex = 0;  // 当前执行的脚本索引
  int successCount = 0;  // 成功执行的脚本计数
  int failureCount = 0;  // 失败执行的脚本计数
  int remainingLoopCount = 1;  // 剩余循环次数
  List<Script> scripts = []; // 添加每个标签页自己的脚本列表

  BrowserTab({
    required this.id,
    required this.controller,
    this.title = 'auok浏览器',
    this.url = 'about:blank',
    this.isLoading = false,
    this.isExecutingScript = false,
  });
}

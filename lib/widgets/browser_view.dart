import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:collection';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/browser_tab.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import '../services/script_executor.dart';
import 'download_confirm_dialog.dart';
import '../utils/welcome_manager.dart';

/// 全局 WebView 调试日志管理器（支持打包 APK 后在设备端直接查看与一键复制）
class DebugLogManager {
  static final List<String> logs = [];
  static final ValueNotifier<int> logCountNotifier = ValueNotifier<int>(0);

  static void log(String msg) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}";
    final entry = '[$timeStr] $msg';
    debugPrint('🔥 $entry');
    logs.add(entry);
    if (logs.length > 500) {
      logs.removeAt(0);
    }
    logCountNotifier.value = logs.length;
  }

  static void clear() {
    logs.clear();
    logCountNotifier.value = 0;
  }

  static String getAllLogs() => logs.join('\n');
}

class BrowserView extends StatefulWidget {
  final BrowserTab tab;
  final bool isActive;

  const BrowserView({
    super.key,
    required this.tab,
    this.isActive = true,
  });

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  String _normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return 'about:blank';
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file://') ||
        lower.startsWith('about:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:')) {
      return url;
    }
    return 'http://$url';
  }

  @override
  void didUpdateWidget(covariant BrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当该标签页从后台切换到前台显示时，检测页面是否处于空白/未加载状态并补救触发加载
    if (widget.isActive && !oldWidget.isActive) {
      _checkAndEnsurePageLoaded();
    }
  }

  void _loadTargetUrl(String rawUrl) {
    final targetUrl = _normalizeUrl(rawUrl);
    widget.tab.url = targetUrl;
    if (widget.tab.controller != null) {
      try {
        widget.tab.controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri(targetUrl)),
        );
      } catch (_) {}
    }
  }

  void _checkAndEnsurePageLoaded() async {
    if (widget.tab.url.isEmpty ||
        widget.tab.url == 'about:blank' ||
        widget.tab.url.endsWith('welcome.html')) {
      return;
    }
    final controller = widget.tab.controller;
    if (controller != null) {
      try {
        final currentUri = await controller.getUrl();
        final currentStr = currentUri?.toString() ?? '';
        if (currentStr.isEmpty || currentStr == 'about:blank') {
          _loadTargetUrl(widget.tab.url);
        }
      } catch (_) {
        _loadTargetUrl(widget.tab.url);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final browserProvider = context.read<BrowserProvider>();
    final scriptProvider = context.read<ScriptProvider>();

    // Build initial user scripts list
    final List<UserScript> initialScripts = [];

    // 禁用点击高亮效果，避免快速点击时的视觉残留
    initialScripts.add(UserScript(
      source: '''
        (function() {
          var style = document.createElement('style');
          style.textContent = '* { -webkit-tap-highlight-color: transparent !important; }';
          document.head.appendChild(style);
        })();
      ''',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ));

    if (browserProvider.isDarkMode &&
        browserProvider.nightModeUserScript != null) {
      initialScripts.add(browserProvider.nightModeUserScript!);
    }
    if (scriptProvider.isRecording) {
      initialScripts.add(scriptProvider.recordingUserScript);
    }

    // 白鹭引擎 (Egret) 与 Canvas 游戏自动化全局探针（常驻挂载 window.clickVirtual 与 window.scanEgretElements）
    initialScripts.add(UserScript(
      source: ScriptExecutor.egretCanvasProbeJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ));

    // 通用/桌面端浮窗广告安全拦截脚本（欢迎页与官方起始页严格加入白名单免拦截）
    if (browserProvider.isAdBlockEnabled) {
      initialScripts.add(UserScript(
        source: '''
          (function() {
            try {
              var href = window.location.href || '';
              if (href.indexOf('welcome.html') !== -1 || href.indexOf('test.txsj.ink') !== -1 || href.indexOf('about:blank') !== -1) {
                return; // 欢迎页免拦截白名单
              }
              var style = document.createElement('style');
              style.id = '_auok_adblock_style';
              style.textContent = '.popup-ad, .app-download-bar, .open-app-btn, .modal-ad, .bottom-ad, #app-banner { display: none !important; }';
              (document.head || document.documentElement).appendChild(style);
            } catch(e) {}
          })();
        ''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ));
    }

    // 跨平台/Windows 端下载点击主动捕获（解决 WebView2 底层缺失 DownloadStarting 事件的问题）
    initialScripts.add(UserScript(
      source: '''
        (function() {
          function handleDownloadClick(e) {
            try {
              var rawTarget = e.target;
              if (rawTarget && rawTarget.nodeType === 3) {
                rawTarget = rawTarget.parentElement;
              }
              if (!rawTarget) return;

              // 优先查找外层 <a> 链接（解决 <a href="xxx.apk"><button>下载</button></a> 嵌套按钮丢失 href 的问题）
              var target = (rawTarget.closest && rawTarget.closest('a[href]')) ||
                           (rawTarget.closest && rawTarget.closest('a, button'));
              if (!target) {
                target = rawTarget;
                while (target && target.tagName !== 'A' && target.tagName !== 'BUTTON') {
                  target = target.parentElement;
                }
              }
              if (!target) return;

              var href = target.getAttribute('href') || '';
              var downloadAttr = target.getAttribute('download');

              if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;

              var isDownloadExt = /\\.(apk|exe|msi|zip|rar|7z|tar|gz|bz2|dmg|iso|pkg|pdf|mp3|mp4|flv|mkv|avi|mov|docx|xlsx|pptx|torrent|deb|rpm|appx|msix)(\\?.*)?\$/i.test(href);

              if (downloadAttr !== null || isDownloadExt) {
                var fullUrl = target.href || '';
                if (!fullUrl && href) {
                  try {
                    fullUrl = new URL(href, window.location.href).href;
                  } catch(_) {
                    fullUrl = href;
                  }
                }
                if (fullUrl && (fullUrl.startsWith('http://') || fullUrl.startsWith('https://'))) {
                  e.preventDefault();
                  e.stopPropagation();
                  var suggestedName = downloadAttr || '';
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onFileDownloadClick', fullUrl, suggestedName);
                  }
                }
              }
            } catch(err) {}
          }
          document.addEventListener('click', handleDownloadClick, true);
        })();
      ''',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ));

    // 全局接管 window.open 与弹窗，将弹窗平滑转为当前标签页导航，杜绝 Chromium 弹窗拒绝导致的死循环刷新
    initialScripts.add(UserScript(
      source: '''
        (function() {
          try {
            var _origOpen = window.open;
            window.open = function(url, target, features) {
              function navigateCurrent(targetUrl) {
                if (!targetUrl || typeof targetUrl !== 'string') return;
                var trimmed = targetUrl.trim();
                if (!trimmed || trimmed === 'about:blank' || trimmed.startsWith('javascript:')) return;
                try {
                  window.location.href = new URL(trimmed, window.location.href).href;
                } catch(_) {
                  window.location.href = trimmed;
                }
              }

              var proxyWin = {
                closed: false,
                name: target || '',
                opener: window,
                parent: window,
                top: window,
                self: null,
                window: null,
                close: function() { this.closed = true; },
                focus: function() {},
                blur: function() {},
                postMessage: function() {},
                document: {
                  write: function() {},
                  writeln: function() {},
                  open: function() { return this; },
                  close: function() {}
                },
                location: {
                  get href() { return window.location.href; },
                  set href(val) { navigateCurrent(val); },
                  replace: function(val) { navigateCurrent(val); },
                  assign: function(val) { navigateCurrent(val); },
                  reload: function() { window.location.reload(); }
                }
              };
              proxyWin.self = proxyWin;
              proxyWin.window = proxyWin;

              if (url && typeof url === 'string') {
                navigateCurrent(url);
              }
              return proxyWin;
            };

            // 自动降级所有 target="_blank" 链接与表单为当前窗口加载，防御多窗口拦截导致的刷新
            document.addEventListener('click', function(e) {
              try {
                var a = e.target && e.target.closest ? e.target.closest('a') : null;
                if (a && a.target === '_blank') {
                  a.target = '_self';
                }
              } catch(_) {}
            }, true);

            document.addEventListener('submit', function(e) {
              try {
                if (e.target && e.target.target === '_blank') {
                  e.target.target = '_self';
                }
              } catch(_) {}
            }, true);
          } catch(e) {}
        })();
      ''',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ));

    // 全局字体大小自适应注入 (跨平台通用 CSS zoom + text-size-adjust)
    final zoomVal = browserProvider.textZoom;
    final zoomRatio = (zoomVal / 100.0).toStringAsFixed(2);
    if (zoomVal != 100) {
      initialScripts.add(UserScript(
        source: '''
          (function() {
            try {
              var s = document.createElement('style');
              s.id = 'auok-font-size-adjust';
              s.appendChild(document.createTextNode('body { zoom: $zoomRatio !important; -webkit-text-size-adjust: $zoomVal% !important; text-size-adjust: $zoomVal% !important; }'));
              (document.head || document.documentElement).appendChild(s);

              if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() {
                  if (document.body) document.body.style.zoom = '$zoomRatio';
                });
              } else if (document.body) {
                document.body.style.zoom = '$zoomRatio';
              }
            } catch(e) {}
          })();
        ''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ));
    }

    return Container(
      color: browserProvider.isDarkMode ? Colors.black : Colors.white,
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: (widget.tab.url != 'about:blank' &&
                    widget.tab.url.isNotEmpty &&
                    !widget.tab.url.endsWith('welcome.html'))
                ? URLRequest(url: WebUri(_normalizeUrl(widget.tab.url)))
                : null,
            contextMenu: ContextMenu(
              menuItems: [
                ContextMenuItem(
                  id: 1,
                  title: "剪切",
                  action: () async {
                    try {
                      await widget.tab.controller?.evaluateJavascript(
                        source: "document.execCommand('cut');",
                      );
                    } catch (_) {}
                  },
                ),
                ContextMenuItem(
                  id: 2,
                  title: "复制",
                  action: () async {
                    try {
                      await widget.tab.controller?.evaluateJavascript(
                        source: "document.execCommand('copy');",
                      );
                    } catch (_) {}
                  },
                ),
                ContextMenuItem(
                  id: 3,
                  title: "粘贴",
                  action: () async {
                    try {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      final clipText = data?.text;
                      if (clipText != null && clipText.isNotEmpty) {
                        final jsonText = jsonEncode(clipText);
                        await widget.tab.controller?.evaluateJavascript(
                          source: """
                            (function() {
                              var el = document.activeElement;
                              if (!el || el === document.body) {
                                var sel = window.getSelection();
                                if (sel && sel.anchorNode) {
                                  var node = sel.anchorNode;
                                  if (node.nodeType === 3) node = node.parentElement;
                                  if (node && (node.tagName === 'INPUT' || node.tagName === 'TEXTAREA' || node.isContentEditable)) {
                                    el = node;
                                  }
                                }
                              }
                              var text = $jsonText;
                              if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
                                try { if (typeof el.focus === 'function') el.focus(); } catch(_) {}
                                var start = 0, end = 0;
                                try {
                                  start = el.selectionStart || 0;
                                  end = el.selectionEnd || 0;
                                } catch(_) {
                                  start = (el.value || '').length;
                                  end = start;
                                }
                                var val = el.value || '';
                                el.value = val.substring(0, start) + text + val.substring(end);
                                try {
                                  el.selectionStart = el.selectionEnd = start + text.length;
                                } catch(_) {}
                                el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                                el.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                              } else if (el && el.isContentEditable) {
                                document.execCommand('insertText', false, text);
                              } else {
                                try {
                                  document.execCommand('insertText', false, text);
                                } catch(e) {
                                  try { document.execCommand('paste'); } catch(e2) {}
                                }
                              }
                            })();
                          """,
                        );
                      }
                    } catch (_) {}
                  },
                ),
                ContextMenuItem(
                  id: 4,
                  title: "全选",
                  action: () async {
                    try {
                      await widget.tab.controller?.evaluateJavascript(
                        source: "document.execCommand('selectAll');",
                      );
                    } catch (_) {}
                  },
                ),
                ContextMenuItem(
                  id: 5,
                  title: "在新标签页打开",
                  action: () async {
                    final browserProvider = context.read<BrowserProvider>();
                    try {
                      final rawResult =
                          await widget.tab.controller?.evaluateJavascript(
                        source: """
                          (function() {
                            try {
                              // 1. 尝试从选区或活动元素提取最近的超链接 A.href
                              var sel = window.getSelection();
                              var selText = sel ? sel.toString().trim() : '';

                              if (sel && sel.rangeCount > 0) {
                                var range = sel.getRangeAt(0);
                                var node = range.commonAncestorContainer;
                                while (node && node !== document.body && node.nodeName !== 'A') {
                                  node = node.parentNode;
                                }
                                if (node && node.nodeName === 'A' && node.href) {
                                  return JSON.stringify({ type: 'url', value: node.href });
                                }
                                // 检查选区碎片内是否包含 <a>
                                if (range.cloneContents) {
                                  var fragment = range.cloneContents();
                                  var aInFrag = fragment.querySelector ? fragment.querySelector('a') : null;
                                  if (aInFrag && aInFrag.href) {
                                    return JSON.stringify({ type: 'url', value: aInFrag.href });
                                  }
                                }
                              }

                              // 2. 尝试从当前焦点元素或点击锚点读取 A.href
                              var active = document.activeElement;
                              var closestA = active ? (active.closest ? active.closest('a') : null) : null;
                              if (closestA && closestA.href) {
                                return JSON.stringify({ type: 'url', value: closestA.href });
                              }

                              // 3. 若无 <a> 标签，检查选中的文字本身是否是 URL 网址或域名
                              if (selText) {
                                var lower = selText.toLowerCase();
                                var isHttpUrl = lower.indexOf('http://') === 0 ||
                                    lower.indexOf('https://') === 0 ||
                                    lower.indexOf('file://') === 0 ||
                                    lower.indexOf('about:') === 0;
                                var isDomainUrl = lower.indexOf('.') !== -1 &&
                                    lower.indexOf(' ') === -1 &&
                                    lower.length >= 4;
                                if (isHttpUrl) {
                                  return JSON.stringify({ type: 'url', value: selText });
                                } else if (isDomainUrl) {
                                  return JSON.stringify({ type: 'url', value: 'https://' + selText });
                                } else {
                                  // 4. 普通关键词，作为搜索词在新标签页打开
                                  return JSON.stringify({ type: 'search', value: selText });
                                }
                              }
                            } catch(e) {}
                            return null;
                          })();
                        """,
                      );

                      if (rawResult != null &&
                          rawResult.toString().isNotEmpty &&
                          rawResult.toString() != 'null') {
                        String targetUrl = '';
                        try {
                          final parsed = jsonDecode(rawResult.toString());
                          if (parsed is Map) {
                            final type = parsed['type']?.toString();
                            final val = parsed['value']?.toString() ?? '';
                            if (type == 'url' && val.isNotEmpty) {
                              targetUrl = val;
                            } else if (type == 'search' && val.isNotEmpty) {
                              final engine = browserProvider.searchEngine;
                              if (engine == 'Bing') {
                                targetUrl =
                                    'https://www.bing.com/search?q=${Uri.encodeComponent(val)}';
                              } else if (engine == 'Google') {
                                targetUrl =
                                    'https://www.google.com/search?q=${Uri.encodeComponent(val)}';
                              } else {
                                targetUrl =
                                    'https://www.baidu.com/s?wd=${Uri.encodeComponent(val)}';
                              }
                            }
                          }
                        } catch (_) {
                          final str = rawResult.toString().trim();
                          if (str.startsWith('http')) targetUrl = str;
                        }

                        if (targetUrl.isNotEmpty) {
                          browserProvider.addTab(initialUrl: targetUrl);
                        }
                      }
                    } catch (_) {}
                  },
                ),
              ],
              settings: ContextMenuSettings(
                hideDefaultSystemContextMenuItems: true,
              ),
            ),
            initialSettings: InAppWebViewSettings(
              isInspectable: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllow: "camera; microphone",
              iframeAllowFullscreen: true,
              transparentBackground: true,
              // ====== 1. 全局核心渲染与主流兼容性支持 ======
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              thirdPartyCookiesEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
              allowFileAccess: true,
              allowContentAccess: true,
              cacheMode: CacheMode.LOAD_DEFAULT,
              saveFormData: true,

              // ====== 2. 移动端视口与排版兼容性 (WAP / 老旧网站 / 响应式) ======
              useWideViewPort: true, // 开启宽视口模式，老旧非响应式网页自动缩放适配屏幕
              loadWithOverviewMode: true, // 概览缩放模式，避免大图或宽表格撑破屏幕
              supportZoom: true,
              builtInZoomControls: true,
              displayZoomControls: false, // 隐藏 Android 屏幕上过时的 +/- 浮动缩放按钮
              textZoom: browserProvider.textZoom, // 响应用户设定的网页字体大小缩放 (75% ~ 130%)

              // ====== 3. 多窗口与新标签页支持 (保持 false 以免 Android Chromium 在 onCreateWindow 拦截丢失 target_blank 链接并陷入刷新死循环) ======
              supportMultipleWindows: false,
              geolocationEnabled: true,
              safeBrowsingEnabled: false,
              userAgent: widget.tab.customUserAgent != null
                  ? browserProvider.getUserAgentString(widget.tab.customUserAgent)
                  : browserProvider.currentUserAgentString,
              preferredContentMode: widget.tab.customUserAgent != null
                  ? (widget.tab.customUserAgent == 'Desktop'
                      ? UserPreferredContentMode.DESKTOP
                      : UserPreferredContentMode.MOBILE)
                  : (browserProvider.userAgent == 'Desktop'
                      ? UserPreferredContentMode.DESKTOP
                      : UserPreferredContentMode.MOBILE),
              useHybridComposition: true,
              useOnDownloadStart: true,
              allowsLinkPreview: false, // 禁用 iOS 链接预览
              allowsBackForwardNavigationGestures: !Platform.isWindows, // 仅在移动端开启滑动前进后退手势，Windows PC 端禁用以避免触控板/鼠标误触后退
              forceDark: browserProvider.isDarkMode
                  ? ForceDark.ON
                  : ForceDark.OFF,
              algorithmicDarkeningAllowed: true,
              contentBlockers:
                  (browserProvider.isAdBlockEnabled && !Platform.isWindows)
                      ? [
                          ContentBlocker(
                            trigger: ContentBlockerTrigger(
                              urlFilter:
                                  ".*(doubleclick\\.net|googlesyndication\\.com|adservice\\.google|pos\\.baidu\\.com|cpro\\.baidustatic\\.com|eclick\\.baidu\\.com|ad\\.toutiao\\.com|adnxs\\.com|popads\\.net|adroll\\.com).*",
                              unlessTopUrl: [
                                ".*welcome.*",
                                ".*test\\.txsj\\.ink.*",
                                "file:///.*",
                                "about:blank",
                              ],
                              unlessDomain: [
                                "test.txsj.ink",
                                "txsj.ink",
                              ],
                            ),
                            action: ContentBlockerAction(
                              type: ContentBlockerActionType.BLOCK,
                            ),
                          ),
                          ContentBlocker(
                            trigger: ContentBlockerTrigger(
                              urlFilter: ".*",
                              unlessTopUrl: [
                                ".*welcome.*",
                                ".*test\\.txsj\\.ink.*",
                                "file:///.*",
                                "about:blank",
                              ],
                              unlessDomain: [
                                "test.txsj.ink",
                                "txsj.ink",
                              ],
                              resourceType: [
                                ContentBlockerTriggerResourceType.IMAGE,
                                ContentBlockerTriggerResourceType.RAW,
                                ContentBlockerTriggerResourceType.SCRIPT,
                              ],
                            ),
                            action: ContentBlockerAction(
                              type: ContentBlockerActionType.CSS_DISPLAY_NONE,
                              selector:
                                  ".ad, .ads, .advert, .advertisement, [id^='ad-'], [class^='ad-'], .popup-ad, .app-download-bar, .open-app-btn, .modal-ad, .bottom-ad, #app-banner",
                            ),
                          ),
                        ]
                      : [],
            ),
            initialUserScripts:
                UnmodifiableListView<UserScript>(initialScripts),
            onWebViewCreated: (controller) async {
              widget.tab.setController(controller);

              // 关键加固：在 WebView 内核创建完成的第一时间显式调用 setSettings
              // 解决 Windows WebView2 等平台冷启动时 initialSettings.userAgent 未能立即生效导致的 UA 错乱问题
              try {
                final targetUa = widget.tab.customUserAgent != null
                    ? browserProvider.getUserAgentString(widget.tab.customUserAgent)
                    : browserProvider.currentUserAgentString;
                final targetMode = widget.tab.customUserAgent != null
                    ? (widget.tab.customUserAgent == 'Desktop'
                        ? UserPreferredContentMode.DESKTOP
                        : UserPreferredContentMode.MOBILE)
                    : (browserProvider.userAgent == 'Desktop'
                        ? UserPreferredContentMode.DESKTOP
                        : UserPreferredContentMode.MOBILE);
                await controller.setSettings(
                  settings: InAppWebViewSettings(
                    userAgent: targetUa,
                    preferredContentMode: targetMode,
                    supportMultipleWindows: false,
                    textZoom: browserProvider.textZoom,
                  ),
                );
                if (browserProvider.textZoom != 100) {
                  browserProvider.applyFontSizeToController(controller);
                }
              } catch (_) {}

              // Check if we need to load welcome page (new tab or empty url)
              if (widget.tab.url == 'about:blank' || widget.tab.url.isEmpty) {
                WelcomeManager.getWelcomeContent().then((content) {
                  controller.loadData(
                    data: content,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                    baseUrl: WebUri('file:///welcome.html'),
                  );
                });
              } else {
                final targetUrl = _normalizeUrl(widget.tab.url);
                widget.tab.url = targetUrl;
                // 跨平台与 Windows WebView2 离屏补强：延迟检查底层 initialUrlRequest 是否已启动，若未启动则调用 loadUrl
                Future.delayed(const Duration(milliseconds: 300), () async {
                  if (!mounted) return;
                  try {
                    final cur = await controller.getUrl();
                    final curStr = cur?.toString() ?? '';
                    if (curStr.isEmpty || curStr == 'about:blank') {
                      controller.loadUrl(
                        urlRequest: URLRequest(url: WebUri(targetUrl)),
                      );
                    }
                  } catch (_) {
                    controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(targetUrl)),
                    );
                  }
                });
              }

              // Add JavaScript Handler for ScriptRunner
              controller.addJavaScriptHandler(
                handlerName: 'ScriptRunner',
                callback: (args) {
                  if (args.isNotEmpty) {
                    scriptProvider.handleScriptMessage(args[0].toString());
                  }
                },
              );

              // 注册文件下载点击主动拦截处理器 (解决 Windows/WebView2 无 DownloadStarting 回调问题)
              controller.addJavaScriptHandler(
                handlerName: 'onFileDownloadClick',
                callback: (args) async {
                  if (args.isNotEmpty) {
                    final rawUrl = args[0]?.toString() ?? '';
                    final suggestedName =
                        args.length > 1 && args[1] != null && args[1].toString().isNotEmpty
                            ? args[1].toString()
                            : null;
                    if (rawUrl.isNotEmpty) {
                      _triggerDownload(controller, rawUrl, suggestedFilename: suggestedName);
                    }
                  }
                },
              );

              // Recording and Night Mode scripts are now in initialUserScripts
              // This ensures they inject at the earliest possible moment
            },
            onLongPressHitTestResult: (controller, hitTestResult) async {
              // 检查是否长按了链接
              if (hitTestResult.type ==
                      InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
                  hitTestResult.type ==
                      InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) {
                final url = hitTestResult.extra;
                if (url != null && url.isNotEmpty) {
                  // 显示自定义菜单
                  _showLinkActionSheet(context, browserProvider, url);
                }
              }
            },
            onLoadStart: (controller, url) {
              DebugLogManager.log('🚀 [onLoadStart] url=$url');
              if (url != null) {
                final urlString = url.toString();
                widget.tab.url = urlString;
                widget.tab.isLoading = true;

                final index = browserProvider.tabs.indexOf(widget.tab);
                if (index != -1) {
                  if (index == browserProvider.currentIndex) {
                    browserProvider.updateTabProgress(0.0);
                  }

                  if (urlString != 'about:blank' &&
                      !urlString.endsWith('welcome.html')) {
                    try {
                      final historyItem = browserProvider.history.firstWhere(
                        (item) => item.url == urlString,
                      );
                      widget.tab.title = historyItem.title;
                    } catch (_) {}
                  }
                }
              }
            },
            onLoadStop: (controller, url) async {
              DebugLogManager.log('🏁 [onLoadStop] url=$url');
              if (url != null) {
                widget.tab.isLoading = false;
                final index = browserProvider.tabs.indexOf(widget.tab);

                if (index != -1) {
                  if (index == browserProvider.currentIndex) {
                    browserProvider.updateTabProgress(1.0);
                  }

                  // Fallback injection for Night Mode (especially for PC/Desktop)
                  if (browserProvider.isDarkMode) {
                    try {
                      browserProvider.injectNightMode(controller);
                    } catch (_) {}

                    // Windows: Poll for Night Mode injection to fight dynamic content/CSP
                    if (Platform.isWindows) {
                      for (int i = 0; i < 4; i++) {
                        await Future.delayed(const Duration(milliseconds: 800));
                        if (!mounted) break;
                        try {
                          if (browserProvider.isDarkMode) {
                            browserProvider.injectNightMode(controller);
                          }
                        } catch (_) {
                          break;
                        }
                      }
                    }
                  }

                  if (!mounted) return;

                  // 页面加载完成时补强注入白鹭引擎全局探针
                  try {
                    await controller.evaluateJavascript(
                        source: ScriptExecutor.egretCanvasProbeJs);
                  } catch (_) {}

                  // 补强注入网页字体缩放
                  if (browserProvider.textZoom != 100) {
                    try {
                      browserProvider.applyFontSizeToController(controller);
                    } catch (_) {}
                  }

                  if (!mounted) return;

                  if (scriptProvider.isRecording &&
                      index == browserProvider.currentIndex) {
                    try {
                      await controller.evaluateJavascript(
                          source: ScriptProvider.recordingJs);
                    } catch (_) {}
                  }

                  if (!mounted) return;

                  String? title;
                  try {
                    if (Platform.isWindows) {
                      // Windows workaround: getTitle() is buggy, use JS
                      final result = await controller.evaluateJavascript(
                          source: "document.title");
                      title = result?.toString();
                    } else {
                      // Mobile: use standard API
                      title = await controller.getTitle();
                    }
                  } catch (_) {}

                  // Retry getting title if empty (common on Desktop/fast loads)
                  if ((title == null || title.isEmpty) && mounted) {
                    await Future.delayed(const Duration(milliseconds: 500));
                    if (mounted) {
                      try {
                        if (Platform.isWindows) {
                          final result = await controller.evaluateJavascript(
                              source: "document.title");
                          title = result?.toString();
                        } else {
                          title = await controller.getTitle();
                        }
                      } catch (_) {}
                    }
                  }

                  if (!mounted) return;

                  // Polling for title updates (SPA support) - Windows only
                  if (Platform.isWindows) {
                    for (int i = 0; i < 6; i++) {
                      await Future.delayed(const Duration(milliseconds: 500));
                      if (!mounted) break;
                      try {
                        final result = await controller.evaluateJavascript(
                            source: "document.title");
                        final newTitle = result?.toString();
                        if (newTitle != null &&
                            newTitle.isNotEmpty &&
                            newTitle != title &&
                            mounted) {
                          title = newTitle;
                          final currentIndex =
                              browserProvider.tabs.indexOf(widget.tab);
                          if (currentIndex != -1) {
                            browserProvider.updateTabInfo(
                                currentIndex, url.toString(), title);
                          }
                        }
                      } catch (_) {
                        break;
                      }
                    }
                  }

                  if (!mounted) return;

                  // Handle default page title
                  if (url.toString().endsWith('welcome.html') ||
                      url.toString() == 'about:blank') {
                    title = '欢迎使用';
                  } else if ((title == null || title.isEmpty) &&
                      url.toString().startsWith('http')) {
                    title = url.toString();
                  }

                  if (title != null && mounted) {
                    DebugLogManager.log('📄 [确定标题] $title, url=$url');
                    try {
                      controller.evaluateJavascript(
                        source: "document.body ? (document.body.innerText || '').substring(0, 120).replace(/\\n/g, ' ') : ''",
                      ).then((snippet) {
                        if (snippet != null && snippet.toString().isNotEmpty) {
                          DebugLogManager.log('📝 [正文前120字] $snippet');
                        }
                      });
                    } catch (_) {}

                    final currentIndex =
                        browserProvider.tabs.indexOf(widget.tab);
                    if (currentIndex != -1) {
                      browserProvider.updateTabInfo(
                          currentIndex, url.toString(), title);
                      // Allow http/https and welcome.html to be added to history
                      // The provider's addToHistory method has further filtering for other file:// URLs
                      if (url.toString().startsWith('http') ||
                          url.toString().endsWith('welcome.html')) {
                        browserProvider.addToHistory(url.toString(), title);
                      }
                    }
                  }

                  if (!mounted) return;

                  // Update navigation state
                  try {
                    final canGoBack = await controller.canGoBack();
                    final canGoForward = await controller.canGoForward();
                    final currentIndex =
                        browserProvider.tabs.indexOf(widget.tab);
                    if (currentIndex != -1 && mounted) {
                      browserProvider.updateTabNavigationState(
                          currentIndex, canGoBack, canGoForward);
                    }
                  } catch (_) {}
                }
              }
            },
            onProgressChanged: (controller, progress) {
              final index = browserProvider.tabs.indexOf(widget.tab);
              if (index != -1) {
                if (index == browserProvider.currentIndex) {
                  browserProvider.updateTabProgress(progress / 100.0);
                } else {
                  browserProvider.tabs[index].progress = progress / 100.0;
                }
              }
            },
            onTitleChanged: (controller, title) {
              DebugLogManager.log('🏷️ [onTitleChanged] title=$title');
              if (title != null) {
                String displayTitle = title;
                if (displayTitle.isEmpty) {
                  displayTitle =
                      widget.tab.url; // Fallback to URL if title is empty
                }
                widget.tab.title = displayTitle;
                final index = browserProvider.tabs.indexOf(widget.tab);
                if (index != -1) {
                  // Update provider to notify listeners (UI update) and persist state
                  browserProvider.updateTabInfo(
                      index, widget.tab.url, displayTitle);
                  // Also update history title if it's the current page
                  browserProvider.updateHistoryTitle(
                      widget.tab.url, displayTitle);
                }
              }
            },
            onUpdateVisitedHistory: (controller, url, androidIsReload) async {
              DebugLogManager.log('📜 [onUpdateHistory] url=$url, androidIsReload=$androidIsReload');
              final index = browserProvider.tabs.indexOf(widget.tab);
              if (index != -1 && mounted) {
                try {
                  final canGoBack = await controller.canGoBack();
                  final canGoForward = await controller.canGoForward();
                  browserProvider.updateTabNavigationState(
                      index, canGoBack, canGoForward);
                } catch (_) {}

                if (url != null) {
                  final urlStr = url.toString();
                  widget.tab.url = urlStr;

                  if (urlStr.endsWith('welcome.html') ||
                      urlStr == 'file:///welcome.html') {
                    WelcomeManager.getWelcomeContent().then((content) {
                      controller.loadData(
                        data: content,
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                        baseUrl: WebUri('file:///welcome.html'),
                      );
                    });
                    browserProvider.updateTabInfo(index, urlStr, '欢迎使用');
                  } else {
                    String? title;
                    try {
                      if (Platform.isWindows) {
                        final res = await controller.evaluateJavascript(
                            source: "document.title");
                        title = res?.toString();
                      } else {
                        title = await controller.getTitle();
                      }
                    } catch (_) {}
                    if (title != null && title.isNotEmpty) {
                      browserProvider.updateTabInfo(index, urlStr, title);
                    } else {
                      browserProvider.updateTabInfo(
                          index, urlStr, widget.tab.title);
                    }
                  }
                }
              }
            },
            onCreateWindow: (controller, createWindowAction) async {
              String? targetUrl = createWindowAction.request.url?.toString();
              DebugLogManager.log('🪟 [onCreateWindow] targetUrl=$targetUrl');
              if (targetUrl == null ||
                  targetUrl.isEmpty ||
                  targetUrl == 'about:blank') {
                try {
                  final hitTest = await controller.getHitTestResult();
                  if (hitTest?.extra != null && hitTest!.extra!.isNotEmpty) {
                    targetUrl = hitTest.extra;
                  }
                } catch (_) {}
              }
              if (targetUrl != null &&
                  targetUrl.isNotEmpty &&
                  targetUrl != 'about:blank') {
                // 平滑在当前窗口中直接加载，保持脚本引擎与会话连贯
                await controller.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
                return true;
              }
              return false;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              final method = navigationAction.request.method;
              DebugLogManager.log(
                  '🔍 [shouldOverrideUrl] uri=$uri, method=$method, isMainFrame=${navigationAction.isForMainFrame}');
              
              // 1. 表单 POST 请求必须直接放行，杜绝 Android 重载导致丢 Body 或被降级为 GET
              if (method == 'POST') {
                return NavigationActionPolicy.ALLOW;
              }

              if (uri != null) {
                final scheme = uri.scheme.toLowerCase();
                // 拦截非 Web 协议 (如 intent://, weixin://, alipays:// 等)，防止 Android WebView 抛出 net::ERR_UNKNOWN_URL_SCHEME 导致页面死循环刷新
                if (scheme.isNotEmpty &&
                    scheme != 'http' &&
                    scheme != 'https' &&
                    scheme != 'file' &&
                    scheme != 'about' &&
                    scheme != 'javascript' &&
                    scheme != 'data' &&
                    scheme != 'blob') {
                  DebugLogManager.log('🚫 [shouldOverrideUrl] 拦截外部应用私有协议: $uri');
                  return NavigationActionPolicy.CANCEL;
                }

                final urlStr = uri.toString();
                // 2. 拦截并触发文件下载
                if (_isDownloadableUrl(urlStr)) {
                  _triggerDownload(controller, urlStr);
                  return NavigationActionPolicy.CANCEL;
                }

                // 3. 拦截特定纯 HTTP 站点被内核自动升级为 HTTPS 导致的 403 错误
                final host = uri.host.toLowerCase();
                if (scheme == 'https' &&
                    (host == 'duobao.txsj.ink' ||
                        host.endsWith('.txsj.ink') ||
                        host == 'zqwan.cn' ||
                        host.endsWith('.zqwan.cn'))) {
                  final httpUrl = uri.replace(scheme: 'http').toString();
                  DebugLogManager.log('🛡️ [拦截HTTPS升级] 强制重定向至 HTTP: $httpUrl');
                  controller.loadUrl(urlRequest: URLRequest(url: WebUri(httpUrl)));
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
            onPermissionRequest: (controller, request) async {
              DebugLogManager.log('🛡️ [onPermissionRequest] resources=${request.resources}');
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onReceivedServerTrustAuthRequest: (controller, challenge) async {
              return ServerTrustAuthResponse(
                action: ServerTrustAuthResponseAction.PROCEED,
              );
            },
            onSafeBrowsingHit: (controller, url, threatType) async {
              return SafeBrowsingResponse(
                report: false,
                action: SafeBrowsingResponseAction.PROCEED,
              );
            },
            onJsBeforeUnload: (controller, jsBeforeUnloadRequest) async {
              return JsBeforeUnloadResponse(
                handledByClient: true,
                action: JsBeforeUnloadResponseAction.CONFIRM,
              );
            },
            onReceivedError: (controller, request, error) {
              DebugLogManager.log('❌ [onReceivedError] url=${request.url}, error=${error.description}');
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              DebugLogManager.log('⚠️ [onReceivedHttpError] url=${request.url}, statusCode=${errorResponse.statusCode}');
            },
            onConsoleMessage: (controller, consoleMessage) {
              DebugLogManager.log('💬 [Console-${consoleMessage.messageLevel}] ${consoleMessage.message}');
            },
            onJsAlert: (controller, jsAlertRequest) async {
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  content: Text(jsAlertRequest.message ?? ''),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
              return JsAlertResponse(handledByClient: true);
            },
            onJsConfirm: (controller, jsConfirmRequest) async {
              final result = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  content: Text(jsConfirmRequest.message ?? ''),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
              return JsConfirmResponse(
                  handledByClient: true,
                  action: result == true
                      ? JsConfirmResponseAction.CONFIRM
                      : JsConfirmResponseAction.CANCEL);
            },
            onJsPrompt: (controller, jsPromptRequest) async {
              final textController =
                  TextEditingController(text: jsPromptRequest.defaultValue);
              final result = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  content: TextField(
                    controller: textController,
                    decoration:
                        InputDecoration(hintText: jsPromptRequest.message),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, textController.text),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
              return JsPromptResponse(
                  handledByClient: true,
                  action: result != null
                      ? JsPromptResponseAction.CONFIRM
                      : JsPromptResponseAction.CANCEL,
                  value: result);
            },
            onDownloadStartRequest: (controller, downloadStartRequest) async {
              final url = downloadStartRequest.url.toString();
              final suggestedFilename = downloadStartRequest.suggestedFilename;
              final mimeType = downloadStartRequest.mimeType;

              _triggerDownload(
                controller,
                url,
                suggestedFilename: suggestedFilename,
                mimeType: mimeType,
              );
            },
          ),
          // 悬浮调试胶囊（仅在设置中开启调试开关时显示）
          if (browserProvider.isDebugModeEnabled)
            Positioned(
              bottom: 80,
              right: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showDebugLogModal(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bug_report, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      ValueListenableBuilder<int>(
                        valueListenable: DebugLogManager.logCountNotifier,
                        builder: (context, count, _) => Text(
                          '调试 ($count)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开在屏调试日志弹窗（可滑动浏览、一键复制全部、清空）
  void _showDebugLogModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'WebView 调试日志',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      DebugLogManager.clear();
                    },
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('复制全部', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: DebugLogManager.getAllLogs()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制所有调试日志到剪贴板！'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: DebugLogManager.logCountNotifier,
                builder: (context, count, _) {
                  if (DebugLogManager.logs.isEmpty) {
                    return const Center(
                      child: Text(
                        '暂无日志\\n请在网页中点击“使用其它物品”触发操作',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: DebugLogManager.logs.length,
                    itemBuilder: (context, index) {
                      final log = DebugLogManager.logs[index];
                      Color textColor = Colors.white70;
                      if (log.contains('shouldOverrideUrl')) {
                        textColor = Colors.amberAccent;
                      } else if (log.contains('onLoadStart')) {
                        textColor = Colors.lightBlueAccent;
                      } else if (log.contains('onLoadStop')) {
                        textColor = Colors.lightGreenAccent;
                      } else if (log.contains('Error') || log.contains('❌') || log.contains('⚠️')) {
                        textColor = Colors.redAccent;
                      } else if (log.contains('标题') || log.contains('正文')) {
                        textColor = Colors.purpleAccent;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: SelectableText(
                          log,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.3,
                          ),
                        ),
                      );
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

  /// 显示长按链接的操作菜单
  void _showLinkActionSheet(
      BuildContext context, BrowserProvider browserProvider, String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // URL 预览
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Text(
                url,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1, color: Colors.grey),
            // 后台打开
            _buildLinkActionItem(
              context,
              '后台打开',
              Colors.white,
              () {
                Navigator.pop(context);
                browserProvider.addTab(initialUrl: url, switchToNewTab: false);
              },
            ),
            const Divider(height: 1, color: Colors.grey),
            // 新标签打开
            _buildLinkActionItem(
              context,
              '新标签打开',
              Colors.white,
              () {
                Navigator.pop(context);
                browserProvider.addTab(initialUrl: url, switchToNewTab: true);
              },
            ),
            const Divider(height: 1, color: Colors.grey),
            // 复制链接
            _buildLinkActionItem(
              context,
              '复制链接',
              Colors.white,
              () {
                Navigator.pop(context);
                // 复制链接到剪贴板
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('链接已复制')),
                );
              },
            ),
            const Divider(height: 1, color: Colors.grey),
            // 下载链接目标
            _buildLinkActionItem(
              context,
              '下载目标文件',
              Colors.lightBlueAccent,
              () {
                Navigator.pop(context);
                if (widget.tab.controller != null) {
                  _triggerDownload(widget.tab.controller!, url);
                }
              },
            ),
            const Divider(height: 1, color: Colors.grey),
            // 取消
            _buildLinkActionItem(
              context,
              '取消',
              Colors.red,
              () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkActionItem(
      BuildContext context, String title, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        width: double.infinity,
        child: Text(
          title,
          style: TextStyle(color: color, fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 校验 URL 是否指向常见下载文件或资源
  bool _isDownloadableUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      const downloadExts = [
        '.apk', '.exe', '.msi', '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
        '.dmg', '.pkg', '.iso', '.pdf', '.mp3', '.mp4', '.flv', '.mkv', '.avi',
        '.mov', '.docx', '.xlsx', '.pptx', '.torrent', '.deb', '.rpm', '.appx', '.msix'
      ];
      for (final ext in downloadExts) {
        if (path.endsWith(ext)) return true;
      }
      if (uri.queryParameters.containsKey('download') ||
          uri.queryParameters.containsKey('attachment')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 统一触发下载弹窗流程（自动提取并携带当前会话 Cookie 与 User-Agent）
  Future<void> _triggerDownload(
    InAppWebViewController controller,
    String url, {
    String? suggestedFilename,
    String? mimeType,
  }) async {
    String? userAgent;
    String? cookieString;
    try {
      final uaResult = await controller.evaluateJavascript(source: 'navigator.userAgent');
      if (uaResult != null) userAgent = uaResult.toString();
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) {
        cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (_) {}

    if (mounted) {
      DownloadConfirmDialog.show(
        context,
        url: url,
        suggestedFilename: suggestedFilename,
        mimeType: mimeType,
        userAgent: userAgent,
        cookies: cookieString,
      );
    }
  }
}

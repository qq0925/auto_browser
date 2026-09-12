import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:collection';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/browser_tab.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import 'download_confirm_dialog.dart';
import '../utils/welcome_manager.dart';

class BrowserView extends StatefulWidget {
  final BrowserTab tab;

  const BrowserView({super.key, required this.tab});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
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
              var target = e.target;
              while (target && target.tagName !== 'A' && target.tagName !== 'BUTTON') {
                target = target.parentElement;
              }
              if (!target) return;

              var href = target.getAttribute('href') || '';
              var downloadAttr = target.getAttribute('download');

              if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;

              var isDownloadExt = /\\.(apk|exe|msi|zip|rar|7z|tar|gz|bz2|dmg|iso|pkg|pdf|mp3|mp4|flv|mkv|avi|mov|docx|xlsx|pptx|torrent|deb|rpm|appx|msix)(\\?.*)?\$/i.test(href);

              if (downloadAttr !== null || isDownloadExt) {
                var fullUrl = target.href || href;
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

    return Container(
      color: browserProvider.isDarkMode ? Colors.black : Colors.white,
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
            contextMenu: ContextMenu(
              menuItems: [
                ContextMenuItem(
                  id: 1,
                  title: "复制",
                  action: () async {
                    await widget.tab.controller?.evaluateJavascript(
                      source: "document.execCommand('copy');",
                    );
                  },
                ),
                ContextMenuItem(
                  id: 2,
                  title: "全选",
                  action: () async {
                    await widget.tab.controller?.evaluateJavascript(
                      source: "document.execCommand('selectAll');",
                    );
                  },
                ),
                ContextMenuItem(
                  id: 3,
                  title: "在新标签页打开",
                  action: () async {
                    // 在异步操作前获取 provider
                    final browserProvider = context.read<BrowserProvider>();
                    // 获取选中的链接
                    final linkUrl =
                        await widget.tab.controller?.evaluateJavascript(
                      source: """
                        (function() {
                          var selection = window.getSelection();
                          if (selection.rangeCount > 0) {
                            var range = selection.getRangeAt(0);
                            var container = range.commonAncestorContainer;
                            while (container && container.nodeName !== 'A') {
                              container = container.parentNode;
                            }
                            if (container && container.nodeName === 'A') {
                              return container.href;
                            }
                          }
                          return null;
                        })();
                      """,
                    );
                    if (linkUrl != null &&
                        linkUrl.toString().isNotEmpty &&
                        linkUrl.toString() != 'null') {
                      browserProvider.addTab(initialUrl: linkUrl.toString());
                    }
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
              userAgent: widget.tab.customUserAgent != null
                  ? (widget.tab.customUserAgent == 'Mobile'
                      ? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
                      : (widget.tab.customUserAgent == 'Desktop'
                          ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
                          : "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1")) // Tablet
                  : (browserProvider.userAgent == 'Mobile'
                      ? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
                      : browserProvider.currentUserAgentString),
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
              supportZoom: true,
              builtInZoomControls: true,
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
            onWebViewCreated: (controller) {
              widget.tab.setController(controller);

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
              if (url != null) {
                widget.tab.isLoading = false;
                final index = browserProvider.tabs.indexOf(widget.tab);

                if (index != -1) {
                  if (index == browserProvider.currentIndex) {
                    browserProvider.updateTabProgress(1.0);
                  }

                  // Fallback injection for Night Mode (especially for PC/Desktop)
                  if (browserProvider.isDarkMode) {
                    browserProvider.injectNightMode(controller);

                    // Windows: Poll for Night Mode injection to fight dynamic content/CSP
                    if (Platform.isWindows) {
                      for (int i = 0; i < 4; i++) {
                        await Future.delayed(const Duration(milliseconds: 800));
                        if (browserProvider.isDarkMode) {
                          browserProvider.injectNightMode(controller);
                        }
                      }
                    }
                  }

                  if (scriptProvider.isRecording &&
                      index == browserProvider.currentIndex) {
                    controller.evaluateJavascript(
                        source: ScriptProvider.recordingJs);
                  }

                  String? title;
                  if (Platform.isWindows) {
                    // Windows workaround: getTitle() is buggy, use JS
                    final result = await controller.evaluateJavascript(
                        source: "document.title");
                    title = result?.toString();
                  } else {
                    // Mobile: use standard API
                    title = await controller.getTitle();
                  }

                  // Retry getting title if empty (common on Desktop/fast loads)
                  if (title == null || title.isEmpty) {
                    await Future.delayed(const Duration(milliseconds: 500));
                    if (Platform.isWindows) {
                      final result = await controller.evaluateJavascript(
                          source: "document.title");
                      title = result?.toString();
                    } else {
                      title = await controller.getTitle();
                    }
                  }

                  // Polling for title updates (SPA support) - Windows only
                  if (Platform.isWindows) {
                    for (int i = 0; i < 6; i++) {
                      await Future.delayed(const Duration(milliseconds: 500));
                      final result = await controller.evaluateJavascript(
                          source: "document.title");
                      final newTitle = result?.toString();
                      if (newTitle != null &&
                          newTitle.isNotEmpty &&
                          newTitle != title) {
                        title = newTitle;
                        final index = browserProvider.tabs.indexOf(widget.tab);
                        if (index != -1) {
                          browserProvider.updateTabInfo(
                              index, url.toString(), title);
                        }
                      }
                    }
                  }

                  // Handle default page title
                  if (url.toString().endsWith('welcome.html') ||
                      url.toString() == 'about:blank') {
                    title = '欢迎使用';
                  } else if ((title == null || title.isEmpty) &&
                      url.toString().startsWith('http')) {
                    title = url.toString();
                  }

                  if (title != null) {
                    browserProvider.updateTabInfo(index, url.toString(), title);
                    // Allow http/https and welcome.html to be added to history
                    // The provider's addToHistory method has further filtering for other file:// URLs
                    if (url.toString().startsWith('http') ||
                        url.toString().endsWith('welcome.html')) {
                      browserProvider.addToHistory(url.toString(), title);
                    }
                  }

                  // Update navigation state
                  final canGoBack = await controller.canGoBack();
                  final canGoForward = await controller.canGoForward();
                  browserProvider.updateTabNavigationState(
                      index, canGoBack, canGoForward);
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
              final index = browserProvider.tabs.indexOf(widget.tab);
              if (index != -1) {
                final canGoBack = await controller.canGoBack();
                final canGoForward = await controller.canGoForward();
                browserProvider.updateTabNavigationState(
                    index, canGoBack, canGoForward);
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null) {
                final urlStr = uri.toString();
                if (_isDownloadableUrl(urlStr)) {
                  _triggerDownload(controller, urlStr);
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
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
        ],
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

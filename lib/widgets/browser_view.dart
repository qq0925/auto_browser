import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:collection';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/browser_tab.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';
import '../services/download_service.dart';

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
    if (browserProvider.isDarkMode &&
        browserProvider.nightModeUserScript != null) {
      initialScripts.add(browserProvider.nightModeUserScript!);
    }
    if (scriptProvider.isRecording) {
      initialScripts.add(scriptProvider.recordingUserScript);
    }

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

              // Recording and Night Mode scripts are now in initialUserScripts
              // This ensures they inject at the earliest possible moment
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

              // 显示开始下载提示
              if (context.mounted) {
                DownloadService.showDownloadStarted(
                  context,
                  suggestedFilename ?? url.split('/').last,
                );
              }

              // 开始下载
              await DownloadService.downloadFile(
                url: url,
                suggestedFilename: suggestedFilename,
                onProgress: (progress) {
                  // 进度更新（可扩展显示进度条）
                },
                onComplete: (filePath) {
                  if (context.mounted) {
                    DownloadService.showDownloadComplete(context, filePath);
                  }
                },
                onError: (error) {
                  if (context.mounted) {
                    DownloadService.showDownloadError(context, error);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

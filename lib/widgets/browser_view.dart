import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:collection';
import 'package:provider/provider.dart';
import '../models/browser_tab.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';

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

    final index = browserProvider.tabs.indexOf(widget.tab);
    final displayIndex = index + 1;
    final displayName = widget.tab.customName;

    return Container(
      color: browserProvider.isDarkMode ? Colors.black : Colors.white,
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
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
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              // Dark mode script is now handled via addUserScript in onWebViewCreated
              // to ensure consistency with toggle logic
            ]),
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

              // If recording, add UserScript immediately
              if (scriptProvider.isRecording) {
                controller.addUserScript(
                    userScript: scriptProvider.recordingUserScript);
              }

              // If dark mode, add UserScript immediately
              if (browserProvider.isDarkMode &&
                  browserProvider.nightModeUserScript != null) {
                controller.addUserScript(
                    userScript: browserProvider.nightModeUserScript!);
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

                  // browserProvider.injectNightModeIfEnabled(controller); // Handled by UserScript now

                  if (scriptProvider.isRecording &&
                      index == browserProvider.currentIndex) {
                    controller.evaluateJavascript(
                        source: ScriptProvider.recordingJs);
                  }

                  String? title = await controller.getTitle();

                  // Handle default page title
                  if (url.toString().endsWith('welcome.html') ||
                      url.toString() == 'about:blank') {
                    title = '欢迎使用';
                    // If we are back at about:blank, reload the welcome content
                    if (url.toString() == 'about:blank') {
                      WelcomeManager.getWelcomeContent().then((content) {
                        controller.loadData(
                          data: content,
                          mimeType: 'text/html',
                          encoding: 'utf-8',
                          baseUrl: WebUri('file:///welcome.html'),
                        );
                      });
                    }
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
          ),
          // Window Info Overlay
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                displayName != null && displayName.isNotEmpty
                    ? '#$displayIndex $displayName'
                    : '#$displayIndex 窗口$displayIndex',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

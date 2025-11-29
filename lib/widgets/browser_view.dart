import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:collection';
import 'package:provider/provider.dart';
import '../models/browser_tab.dart';
import '../providers/browser_provider.dart';
import '../providers/script_provider.dart';

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

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
      initialSettings: InAppWebViewSettings(
        isInspectable: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        iframeAllow: "camera; microphone",
        iframeAllowFullscreen: true,
        userAgent: browserProvider.userAgent == 'Mobile'
            ? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
            : browserProvider.currentUserAgentString,
        preferredContentMode: browserProvider.userAgent == 'Desktop'
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.MOBILE,
        useHybridComposition: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        if (browserProvider.isDarkMode &&
            browserProvider.nightCssContent != null)
          UserScript(
            source: """
              (function() {
                if (document.getElementById('auok-night-mode')) return;
                var style = document.createElement('style');
                style.id = 'auok-night-mode';
                style.innerHTML = `${browserProvider.nightCssContent!.replaceAll('\n', ' ')}`;
                if (document.head) {
                  document.head.appendChild(style);
                } else {
                  document.documentElement.appendChild(style);
                }
              })();
            """,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
      ]),
      onWebViewCreated: (controller) {
        widget.tab.setController(controller);

        // Add JavaScript Handler for ScriptRunner
        controller.addJavaScriptHandler(
          handlerName: 'ScriptRunner',
          callback: (args) {
            if (args.isNotEmpty) {
              scriptProvider.handleScriptMessage(args[0].toString());
            }
          },
        );
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

            browserProvider.injectNightModeIfEnabled(controller);

            if (scriptProvider.isRecording &&
                index == browserProvider.currentIndex) {
              controller.evaluateJavascript(source: ScriptProvider.recordingJs);
            }

            String? title = await controller.getTitle();
            if ((title == null || title.isEmpty) &&
                url.toString().startsWith('http')) {
              title = url.toString();
            }

            if (title != null) {
              browserProvider.updateTabInfo(index, url.toString(), title);
              if (url.toString().startsWith('http')) {
                browserProvider.addToHistory(url.toString(), title);
              }
            }
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
          widget.tab.title = title;
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
              decoration: InputDecoration(hintText: jsPromptRequest.message),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, textController.text),
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
    );
  }
}

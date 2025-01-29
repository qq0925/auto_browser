import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  runApp(const AutoBrowserApp());
}

class AutoBrowserApp extends StatelessWidget {
  const AutoBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Browser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BrowserScreen(),
    );
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  _BrowserScreenState createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  TextEditingController urlController = TextEditingController();
  double progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;

  @override
  void initState() {
    super.initState();
    urlController.text = 'https://www.baidu.com';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: urlController,
          decoration: InputDecoration(
            hintText: '输入网址',
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            suffixIcon: IconButton(
              icon: Icon(progress < 1.0 ? Icons.close : Icons.refresh),
              onPressed: () {
                if (progress < 1.0) {
                  webViewController?.stopLoading();
                } else {
                  webViewController?.reload();
                }
              },
            ),
          ),
          onSubmitted: (value) => _loadUrl(value),
          textInputAction: TextInputAction.go,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: canGoBack
                ? () {
                    webViewController?.goBack();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: canGoForward
                ? () {
                    webViewController?.goForward();
                  }
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.transparent,
          ),
          Expanded(
            child: InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(urlController.text)),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onLoadStart: (controller, url) {
                setState(() {
                  urlController.text = url?.toString() ?? '';
                });
              },
              onLoadStop: (controller, url) {
                setState(() {
                  urlController.text = url?.toString() ?? '';
                });
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  this.progress = progress / 100;
                });
              },
              onUpdateVisitedHistory: (controller, url, androidIsReload) {
                _updateNavigationState();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _loadUrl(String url) {
    final uri = WebUri(url);
    if (uri.scheme.isEmpty) {
      webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri('https://$url')));
    } else {
      webViewController?.loadUrl(urlRequest: URLRequest(url: uri));
    }
  }

  void _updateNavigationState() async {
    final canBack = await webViewController?.canGoBack() ?? false;
    final canForward = await webViewController?.canGoForward() ?? false;
    setState(() {
      canGoBack = canBack;
      canGoForward = canForward;
    });
  }
}
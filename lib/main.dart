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
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  bool isPanelExpanded = false;

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
            onPressed: canGoBack ? () => webViewController?.goBack() : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: canGoForward ? () => webViewController?.goForward() : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                minHeight: 2,
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
                    _updateNavigationState();
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
          Positioned(
            right: 0,
            top: MediaQuery.of(context).size.height / 2 - 100,
            child: _buildControlPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: isPanelExpanded ? 150 : 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: isPanelExpanded ? _buildExpandedPanel() : _buildCollapsedButton(),
    );
  }

  Widget _buildCollapsedButton() {
    return InkWell(
      onTap: () => setState(() => isPanelExpanded = true),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: const Icon(Icons.more_vert, color: Colors.blue),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPanelButton(
          icon: Icons.close,
          label: '关闭面板',
          onTap: () => setState(() => isPanelExpanded = false),
        ),
        _buildPanelButton(
          icon: Icons.home,
          label: '返回主页',
          onTap: () => _loadUrl('https://www.baidu.com'),
        ),
        _buildPanelButton(
          icon: Icons.refresh,
          label: '刷新页面',
          onTap: () => webViewController?.reload(),
        ),
        _buildPanelButton(
          icon: Icons.arrow_back,
          label: '后退',
          onTap: () => webViewController?.goBack(),
        ),
        _buildPanelButton(
          icon: Icons.arrow_forward,
          label: '前进',
          onTap: () => webViewController?.goForward(),
        ),
      ],
    );
  }

  Widget _buildPanelButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onTap();
          setState(() => isPanelExpanded = false);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
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
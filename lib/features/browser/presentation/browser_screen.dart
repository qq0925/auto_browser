import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'widgets/sidebar.dart';
import 'widgets/url_bar.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  final _urlFocusNode = FocusNode();
  bool _isLoading = false;
  bool _showSidebar = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _urlFocusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: UrlBar(
            controller: _controller,
            focusNode: _urlFocusNode,
            isLoading: _isLoading,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              right: _showSidebar ? 0 : -280,
              top: 0,
              bottom: 0,
              child: const Sidebar(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => _showSidebar = !_showSidebar),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _showSidebar ? Icons.close : Icons.bookmark,
              key: ValueKey(_showSidebar),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    super.dispose();
  }
}
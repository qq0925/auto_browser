import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/browser_tab.dart';

class BrowserView extends StatelessWidget {
  final BrowserTab tab;

  const BrowserView({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: tab.controller);
  }
}

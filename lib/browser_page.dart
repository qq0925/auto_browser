import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrowserPage extends StatefulWidget {
  @override
  _BrowserPageState createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Simple Browser'),
      ),
      body: WebView(
        initialUrl: 'https://www.example.com',
        javascriptMode: JavascriptMode.unrestricted,
      ),
    );
  }
}
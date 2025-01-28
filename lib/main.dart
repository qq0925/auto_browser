import 'package:flutter/material.dart';
import 'browser_page.dart'; // 确保导入正确

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BrowserPage(), // 使用BrowserPage作为首页
    );
  }
}
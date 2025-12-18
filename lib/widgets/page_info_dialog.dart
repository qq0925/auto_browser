import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PageInfoDialog extends StatefulWidget {
  final String title;
  final String url;
  final InAppWebViewController? controller;

  const PageInfoDialog({
    super.key,
    required this.title,
    required this.url,
    required this.controller,
  });

  @override
  State<PageInfoDialog> createState() => _PageInfoDialogState();
}

class _PageInfoDialogState extends State<PageInfoDialog> {
  String _pageSource = '加载中...';
  final TextEditingController _sourceController = TextEditingController();
  bool _isLoadingSource = true;

  @override
  void initState() {
    super.initState();
    _loadPageSource();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _loadPageSource() async {
    try {
      // Get the full HTML content
      final Object? result = await widget.controller
          ?.evaluateJavascript(source: "document.documentElement.outerHTML");

      String source = result.toString();
      // Clean up the result if it's a quoted string (common in some webview implementations)
      if (source.startsWith('"') && source.endsWith('"')) {
        source = source.substring(1, source.length - 1);
        // Unescape common characters if needed, though usually runJavaScriptReturningResult handles this
        source = source
            .replaceAll('\\"', '"')
            .replaceAll('\\n', '\n')
            .replaceAll('\\t', '\t');
      }

      if (mounted) {
        setState(() {
          _pageSource = source;
          _sourceController.text = source;
          _isLoadingSource = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageSource = '无法获取页面源码: $e';
          _sourceController.text = _pageSource;
          _isLoadingSource = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _applySource() async {
    try {
      final newSource = _sourceController.text;
      // Escape the source code for JavaScript string
      final escapedSource = newSource
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '\\r');

      // Use JavaScript to replace the document content while maintaining the URL context
      // This prevents breaking the page's origin and allows relative resources to load
      await widget.controller?.evaluateJavascript(source: '''
        (function() {
          document.open();
          document.write('$escapedSource');
          document.close();
        })();
      ''');

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('页面源码已更新'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('应用源码失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF333333), // Dark background as per screenshot
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('页面信息', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Container(
        color: const Color(0xFFF0F0F0), // Light grey background
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Name Row
            _buildInfoRow('名称', widget.title, true),
            const SizedBox(height: 16),

            // Address Row
            _buildInfoRow(
              '地址',
              (widget.url.endsWith('welcome.html') ||
                      widget.url.startsWith('file://'))
                  ? 'welcome.html'
                  : widget.url,
              true,
            ),
            const SizedBox(height: 16),

            // Source Header Row
            Row(
              children: [
                const Text(
                  '页面源码',
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                    '复制', () => _copyToClipboard(_sourceController.text)),
                const SizedBox(width: 8),
                _buildActionButton('应用', _applySource),
              ],
            ),
            const SizedBox(height: 8),

            // Source Code Editor
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.amber,
                      width: 2), // Yellow/Amber border as per screenshot
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _isLoadingSource
                    ? const Center(child: CircularProgressIndicator())
                    : TextField(
                        controller: _sourceController,
                        maxLines: null,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.black87, // Darker text color
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(8),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String content, bool showCopy) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
        Expanded(
          child: Text(
            content,
            style: const TextStyle(fontSize: 16, color: Colors.black54),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showCopy) _buildActionButton('复制', () => _copyToClipboard(content)),
      ],
    );
  }

  Widget _buildActionButton(String text, VoidCallback onPressed) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF555555), // Dark grey button
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          elevation: 0,
        ),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

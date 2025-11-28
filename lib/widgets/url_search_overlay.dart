import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browser_provider.dart';

class UrlSearchOverlay extends StatefulWidget {
  final String initialUrl;
  final Function(String) onSubmitted;

  const UrlSearchOverlay({
    super.key,
    required this.initialUrl,
    required this.onSubmitted,
  });

  @override
  State<UrlSearchOverlay> createState() => _UrlSearchOverlayState();
}

class _UrlSearchOverlayState extends State<UrlSearchOverlay> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);

    // Auto focus and select all text
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        context.select<BrowserProvider, bool>((p) => p.isDarkMode);
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.grey[800],
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Container(
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: '输入网址或搜索...',
              hintStyle: TextStyle(color: Colors.white54),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onSubmitted: (value) {
              // Logic is handled in home_screen, just pass back
              widget.onSubmitted(value);
              Navigator.pop(context);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              '取消',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16, // Slightly larger than default
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: backgroundColor,
        // Future: Add search history or suggestions here
      ),
    );
  }
}

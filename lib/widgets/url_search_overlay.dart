import 'package:flutter/material.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.black),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            hintText: '输入网址或搜索...',
            border: InputBorder.none,
          ),
          onSubmitted: (value) {
            widget.onSubmitted(value);
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_controller.text.isNotEmpty) {
                widget.onSubmitted(_controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text(
              '前往',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        // Future: Add search history or suggestions here
      ),
    );
  }
}

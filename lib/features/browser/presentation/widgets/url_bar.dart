import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class UrlBar extends StatelessWidget {
  final WebViewController controller;
  final FocusNode focusNode;
  final bool isLoading;

  const UrlBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: 'Search or enter URL',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: isLoading
            ? const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => controller.reload(),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onSubmitted: (value) => _handleUrlSubmission(value),
    );
  }

  void _handleUrlSubmission(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null) return;

    if (uri.scheme.isEmpty) {
      controller.loadRequest(Uri.parse('https://$input'));
    } else {
      controller.loadRequest(uri);
    }
  }
}
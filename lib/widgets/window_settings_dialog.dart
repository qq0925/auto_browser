import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/browser_provider.dart';

/// 单个标签窗口设置弹窗（长按标签页触发）
/// 支持配置窗口名称、独立代理服务器（关闭/wap代理/自定义+账密校验）与浏览器标识 UA（默认继承总设置）
class WindowSettingsDialog extends StatefulWidget {
  final int tabIndex;

  const WindowSettingsDialog({
    super.key,
    required this.tabIndex,
  });

  @override
  State<WindowSettingsDialog> createState() => _WindowSettingsDialogState();
}

class _WindowSettingsDialogState extends State<WindowSettingsDialog> {
  static const String _inheritUaKey = '跟随总设置';
  static const String _customUaKey = '自定义';

  late final TextEditingController _nameController;
  late final TextEditingController _proxyHostController;
  late final TextEditingController _proxyPortController;
  late final TextEditingController _proxyUserController;
  late final TextEditingController _proxyPassController;
  late final TextEditingController _uaTextController;

  late String _proxyMode;
  late String _selectedUaMode;
  bool _isUpdatingUaProgrammatically = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final browser = context.read<BrowserProvider>();
    final tab = browser.tabs[widget.tabIndex];

    _nameController = TextEditingController(text: tab.customName ?? '');
    _proxyMode = (tab.proxyMode == 'wap代理' || tab.proxyMode == '自定义')
        ? tab.proxyMode
        : '关闭';
    _proxyHostController = TextEditingController(text: tab.proxyHost);
    _proxyPortController = TextEditingController(text: tab.proxyPort);
    _proxyUserController = TextEditingController(text: tab.proxyUsername);
    _proxyPassController = TextEditingController(text: tab.proxyPassword);

    final rawUa = tab.customUserAgent?.trim();
    String initialUaText;
    if (rawUa == null || rawUa.isEmpty || rawUa == _inheritUaKey || rawUa == '默认') {
      _selectedUaMode = _inheritUaKey;
      initialUaText = browser.currentUserAgentString;
    } else if (rawUa == 'Mobile' || rawUa == 'Tablet' || rawUa == 'Desktop') {
      _selectedUaMode = rawUa;
      initialUaText = browser.getUserAgentString(rawUa);
    } else {
      _selectedUaMode = _customUaKey;
      initialUaText = rawUa;
    }
    _uaTextController = TextEditingController(text: initialUaText);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _proxyUserController.dispose();
    _proxyPassController.dispose();
    _uaTextController.dispose();
    super.dispose();
  }

  void _setUaTextProgrammatically(String text) {
    _isUpdatingUaProgrammatically = true;
    _uaTextController.text = text;
    _uaTextController.selection = TextSelection.collapsed(offset: text.length);
    _isUpdatingUaProgrammatically = false;
  }

  void _resetToDefaults(BrowserProvider browser) {
    setState(() {
      _nameController.clear();
      _proxyMode = '关闭';
      _proxyHostController.clear();
      _proxyPortController.clear();
      _proxyUserController.clear();
      _proxyPassController.clear();
      _selectedUaMode = _inheritUaKey;
      _errorText = null;
      _setUaTextProgrammatically(browser.currentUserAgentString);
    });
  }

  Future<void> _applySettings(BrowserProvider browser) async {
    if (_proxyMode == '自定义') {
      final host = _proxyHostController.text.trim();
      final portStr = _proxyPortController.text.trim();
      final port = int.tryParse(portStr);
      if (host.isEmpty || port == null || port < 1 || port > 65535) {
        setState(() {
          _errorText = '请填写有效的自定义代理 IP/域名与端口 (1-65535)';
        });
        return;
      }
    }

    final uaInput = _uaTextController.text.trim();
    String? finalUa;
    if (_selectedUaMode == _inheritUaKey) {
      finalUa = (uaInput.isEmpty || uaInput == browser.currentUserAgentString)
          ? null
          : uaInput;
    } else if (_selectedUaMode == 'Mobile' ||
        _selectedUaMode == 'Tablet' ||
        _selectedUaMode == 'Desktop') {
      final presetStr = browser.getUserAgentString(_selectedUaMode);
      finalUa = (uaInput.isEmpty || uaInput == presetStr)
          ? _selectedUaMode
          : uaInput;
    } else {
      finalUa = (uaInput.isEmpty || uaInput == browser.currentUserAgentString)
          ? null
          : uaInput;
    }

    await browser.updateTabCustomSettings(
      widget.tabIndex,
      _nameController.text,
      finalUa,
      proxyMode: _proxyMode,
      proxyHost: _proxyMode == '自定义' ? _proxyHostController.text.trim() : '',
      proxyPort: _proxyMode == '自定义' ? _proxyPortController.text.trim() : '',
      proxyUsername:
          _proxyMode == '自定义' ? _proxyUserController.text.trim() : '',
      proxyPassword: _proxyMode == '自定义' ? _proxyPassController.text : '',
      reloadIfNeeded: true,
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildHelpButton(
      String message, Color fillColor, Color borderColor, Color labelColor) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: true,
      child: Container(
        width: 32,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          '?',
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final browser = context.watch<BrowserProvider>();
    final isDark = browser.isDarkMode;
    final bgColor = isDark ? const Color(0xFF1F242D) : Colors.white;
    final headerBg = isDark ? const Color(0xFF161A22) : const Color(0xFFF5F6F8);
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final inputFill =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100;
    final dropdownBg = isDark ? const Color(0xFF2C313A) : Colors.white;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final buttonBg =
        isDark ? const Color(0xFF3E444E) : const Color(0xFFEAECEF);

    final globalPresetText = switch (browser.userAgent) {
      'Mobile' => '手机',
      'Tablet' => '平板',
      _ => '电脑',
    };

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Container(
        width: 440,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '窗口设置',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: labelColor, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 表单内容区
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 窗口名称
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            '窗口名称',
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            style: TextStyle(color: textColor, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '选填，默认显示网页标题',
                              hintStyle:
                                  TextStyle(color: hintColor, fontSize: 13),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: inputFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    const BorderSide(color: Colors.blue),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. 代理服务器
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            '代理服务器',
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _proxyMode,
                            isExpanded: true,
                            dropdownColor: dropdownBg,
                            style: TextStyle(color: textColor, fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: inputFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderColor),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: '关闭', child: Text('关闭')),
                              DropdownMenuItem(
                                  value: 'wap代理', child: Text('wap代理')),
                              DropdownMenuItem(value: '自定义', child: Text('自定义')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _proxyMode = val;
                                  _errorText = null;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    if (_proxyMode == 'wap代理') ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 96),
                        child: Text(
                          '将使用默认 WAP 网关代理: 10.0.0.172:80',
                          style: TextStyle(color: labelColor, fontSize: 12),
                        ),
                      ),
                    ],

                    if (_proxyMode == '自定义') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _proxyHostController,
                              style: TextStyle(color: textColor, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: '0.0.0.0',
                                hintStyle:
                                    TextStyle(color: hintColor, fontSize: 13),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                filled: true,
                                fillColor: inputFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              ':',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _proxyPortController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: TextStyle(color: textColor, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: '端口',
                                hintStyle:
                                    TextStyle(color: hintColor, fontSize: 13),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                filled: true,
                                fillColor: inputFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildHelpButton(
                            '输入代理服务器 IP/域名和端口，如 127.0.0.1 : 8080',
                            buttonBg,
                            borderColor,
                            textColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _proxyUserController,
                              style: TextStyle(color: textColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '选填,代理的登录',
                                hintStyle:
                                    TextStyle(color: hintColor, fontSize: 12),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                filled: true,
                                fillColor: inputFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _proxyPassController,
                              style: TextStyle(color: textColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '选填,代理的密码',
                                hintStyle:
                                    TextStyle(color: hintColor, fontSize: 12),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                filled: true,
                                fillColor: inputFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildHelpButton(
                            '如果这个代理需要用户名密码校验，在这里输入',
                            buttonBg,
                            borderColor,
                            textColor,
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 3. 浏览器标识(UA)（默认继承总设置，可切换预设或直接自定义修改）
                    Row(
                      children: [
                        Text(
                          '浏览器标识(UA)',
                          style: TextStyle(color: textColor, fontSize: 14),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedUaMode,
                            isExpanded: true,
                            dropdownColor: dropdownBg,
                            style: TextStyle(color: textColor, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: inputFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderColor),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: _inheritUaKey,
                                child: Text('继承总设置 ($globalPresetText)',
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const DropdownMenuItem(
                                value: 'Mobile',
                                child: Text('手机 (Mobile)'),
                              ),
                              const DropdownMenuItem(
                                value: 'Tablet',
                                child: Text('平板 (Tablet)'),
                              ),
                              const DropdownMenuItem(
                                value: 'Desktop',
                                child: Text('电脑 (Desktop)'),
                              ),
                              const DropdownMenuItem(
                                value: _customUaKey,
                                child: Text('自定义'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _selectedUaMode = val;
                                if (val == _inheritUaKey) {
                                  _setUaTextProgrammatically(
                                      browser.currentUserAgentString);
                                } else if (val != _customUaKey) {
                                  _setUaTextProgrammatically(
                                      browser.getUserAgentString(val));
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildHelpButton(
                          '默认继承浏览器总设置中的 UA；可切换设备预设或直接在下方修改自定义 User-Agent',
                          buttonBg,
                          borderColor,
                          textColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _uaTextController,
                      style: TextStyle(color: textColor, fontSize: 12.5),
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (value) {
                        if (_isUpdatingUaProgrammatically) return;
                        final trimmed = value.trim();
                        if (_selectedUaMode != _customUaKey) {
                          final expected = _selectedUaMode == _inheritUaKey
                              ? browser.currentUserAgentString
                              : browser.getUserAgentString(_selectedUaMode);
                          if (trimmed != expected) {
                            setState(() {
                              _selectedUaMode = _customUaKey;
                            });
                          }
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '输入自定义浏览器标识 (UA)',
                        hintStyle: TextStyle(color: hintColor, fontSize: 12.5),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        filled: true,
                        fillColor: inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),

                    if (_errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 底部双按钮栏：恢复默认 | ✓ 应用(窗口N)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonBg,
                          foregroundColor: textColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () => _resetToDefaults(browser),
                        child: const Text(
                          '恢复默认',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonBg,
                          foregroundColor: textColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () => _applySettings(browser),
                        icon: Icon(
                          Icons.check,
                          size: 18,
                          color: isDark
                              ? Colors.greenAccent
                              : Colors.green.shade700,
                        ),
                        label: Text(
                          '应用(窗口${widget.tabIndex + 1})',
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

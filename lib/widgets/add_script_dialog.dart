import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';

class AddScriptDialog extends StatefulWidget {
  const AddScriptDialog({super.key});

  @override
  State<AddScriptDialog> createState() => _AddScriptDialogState();
}

class _AddScriptDialogState extends State<AddScriptDialog> {
  // Script types list
  static const List<String> scriptTypes = [
    '点击图片',
    '点击文字',
    '回陆时间',
    '脚本替换',
    '脚本停止',
    '脚本查询',
    '进入网址',
    '控制脚本开关',
    '逻辑脚本-出现文字',
    '逻辑脚本-时间对比',
    '逻辑脚本-数值对比',
    '输入框提交',
    '数字运算',
    '数值对比-点击文字',
    '刷新网页',
    '跳转脚本',
    '网页后退',
    '网页前进',
    '新建标签页并执行脚本',
    '延时脚本',
    '执行本地脚本集',
    '重查限制次数',
  ];

  String _selectedScriptType = '点击文字';
  final TextEditingController _repeatCountController =
      TextEditingController(text: '1');
  final TextEditingController _loopCountController =
      TextEditingController(text: '0');

  // Common fields
  final TextEditingController _delayController = TextEditingController();
  final TextEditingController _delayBeforeController = TextEditingController();
  final TextEditingController _appearTextController = TextEditingController();
  final TextEditingController _clickTextController = TextEditingController();
  final TextEditingController _afterTextController = TextEditingController();
  final TextEditingController _beforeTextController = TextEditingController();
  final TextEditingController _multipleFilterController =
      TextEditingController();
  bool _exactMatch = false;

  @override
  void dispose() {
    _repeatCountController.dispose();
    _loopCountController.dispose();
    _delayController.dispose();
    _delayBeforeController.dispose();
    _appearTextController.dispose();
    _clickTextController.dispose();
    _afterTextController.dispose();
    _beforeTextController.dispose();
    _multipleFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF4A5C6A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A4A5A),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '添加脚本',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Top row: Script Type and Counters
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Script Type
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('脚本类型'),
                              const SizedBox(height: 4),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButtonFormField<String>(
                                  value: _selectedScriptType,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    border: InputBorder.none,
                                  ),
                                  isExpanded: true,
                                  items: scriptTypes.map((String type) {
                                    return DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(type,
                                          style: const TextStyle(fontSize: 14)),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedScriptType = newValue;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Repeat Count
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('重复次数'),
                              const SizedBox(height: 4),
                              _buildTextField(_repeatCountController, '1'),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Loop Count row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('循环次数'),
                              const SizedBox(height: 4),
                              _buildTextField(_loopCountController, '0'),
                            ],
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Dynamic fields based on script type
                    ..._buildDynamicFields(),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Bottom button
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5A6C7A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    '确认',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDynamicFields() {
    // Return different fields based on selected script type
    switch (_selectedScriptType) {
      case '点击文字':
        return [
          _buildFieldRow('执行延迟', _delayController, ''),
          _buildFieldRow('执行前执行', _delayBeforeController, ''),
          _buildFieldRow('出现文字', _appearTextController, ''),
          _buildFieldRow('点击文字', _clickTextController, '', required: true),
          _buildFieldRow('在...之后', _afterTextController, ''),
          _buildFieldRow('在...之前', _beforeTextController, ''),
          _buildFieldRow('多个筛选', _multipleFilterController, ''),
          _buildCheckboxRow('完全匹配', _exactMatch, (value) {
            setState(() => _exactMatch = value ?? false);
          }),
        ];
      case '点击图片':
        return [
          _buildFieldRow('执行延迟', _delayController, ''),
          _buildFieldRow('图片识别', _clickTextController, '', required: true),
        ];
      case '输入框提交':
        return [
          _buildFieldRow('执行延迟', _delayController, ''),
          _buildFieldRow('输入内容', _clickTextController, '', required: true),
        ];
      case '进入网址':
        return [
          _buildFieldRow('网址', _clickTextController, '', required: true),
        ];
      case '延时脚本':
        return [
          _buildFieldRow('延时时长(毫秒)', _delayController, '', required: true),
        ];
      default:
        return [
          _buildFieldRow('参数', _clickTextController, ''),
        ];
    }
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildFieldRow(
      String label, TextEditingController controller, String hint,
      {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                if (required)
                  const Text(
                    '*',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _buildTextField(controller, hint),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxRow(
      String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  void _handleSubmit() {
    // Validate required fields based on script type
    if (_selectedScriptType == '点击文字' && _clickTextController.text.isEmpty) {
      // Show error
      return;
    }

    final scriptProvider = context.read<ScriptProvider>();

    // Build params based on script type
    final params = <String, dynamic>{
      'type': _selectedScriptType,
      'repeatCount': int.tryParse(_repeatCountController.text) ?? 1,
      'loopCount': int.tryParse(_loopCountController.text) ?? 0,
    };

    // Add type-specific params
    if (_delayController.text.isNotEmpty) {
      params['执行延迟'] = _delayController.text;
    }
    if (_clickTextController.text.isNotEmpty) {
      params['content'] = _clickTextController.text;
    }
    if (_appearTextController.text.isNotEmpty) {
      params['出现文字'] = _appearTextController.text;
    }
    if (_afterTextController.text.isNotEmpty) {
      params['在...之后'] = _afterTextController.text;
    }
    if (_beforeTextController.text.isNotEmpty) {
      params['在...之前'] = _beforeTextController.text;
    }
    if (_multipleFilterController.text.isNotEmpty) {
      params['多个筛选'] = _multipleFilterController.text;
    }
    params['完全匹配'] = _exactMatch;

    scriptProvider.addScript(Script(
      type: _selectedScriptType,
      params: params,
      isEnabled: true,
    ));

    Navigator.pop(context);
  }
}

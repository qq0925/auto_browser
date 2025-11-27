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
  // Script types list (focused on implemented types)
  static const List<String> scriptTypes = [
    '全局设置',
    '点击文字',
    '点击图片',
    '间隔时间',
    '进入网址',
    '输入框提交',
  ];

  String _selectedScriptType = '点击文字';
  final TextEditingController _repeatCountController =
      TextEditingController(text: '1');
  final TextEditingController _loopCountController =
      TextEditingController(text: '0');

  // Common fields
  final TextEditingController _delayController = TextEditingController();
  final TextEditingController _appearTextController = TextEditingController();
  final TextEditingController _clickTextController = TextEditingController();
  final TextEditingController _afterSearchController = TextEditingController();
  final TextEditingController _beforeSearchController = TextEditingController();

  // 间隔时间 fields
  final TextEditingController _intervalHoursController =
      TextEditingController();
  final TextEditingController _intervalMinutesController =
      TextEditingController();
  final TextEditingController _intervalSecondsController =
      TextEditingController();

  // 输入框提交 fields
  final TextEditingController _submitButtonTextController =
      TextEditingController();
  final TextEditingController _inputValueController = TextEditingController();

  // 进入网址 field
  final TextEditingController _urlController = TextEditingController();

  bool _exactMatch = false;

  @override
  void dispose() {
    _repeatCountController.dispose();
    _loopCountController.dispose();
    _delayController.dispose();
    _appearTextController.dispose();
    _clickTextController.dispose();
    _afterSearchController.dispose();
    _beforeSearchController.dispose();
    _intervalHoursController.dispose();
    _intervalMinutesController.dispose();
    _intervalSecondsController.dispose();
    _submitButtonTextController.dispose();
    _inputValueController.dispose();
    _urlController.dispose();
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
                    // Top row: Script Type and Repeat Count
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
                        // Repeat Count (not visible for 全局设置)
                        if (_selectedScriptType != '全局设置')
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

                    // Loop Count row (not visible for 全局设置)
                    if (_selectedScriptType != '全局设置')
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

                    if (_selectedScriptType != '全局设置')
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
    switch (_selectedScriptType) {
      case '全局设置':
        return [
          _buildFieldRow('执行延迟', _delayController, '',
              hint: '毫秒', required: true),
        ];
      case '点击文字':
        return [
          _buildFieldRow('执行延迟', _delayController, '', hint: '毫秒'),
          _buildFieldRow('出现文字', _appearTextController, ''),
          _buildFieldRow('点击文本', _clickTextController, '', required: true),
          _buildFieldRow('在...之后搜索', _afterSearchController, ''),
          _buildFieldRow('在...之前搜索', _beforeSearchController, ''),
          _buildCheckboxRow('完全匹配', _exactMatch, (value) {
            setState(() => _exactMatch = value ?? false);
          }),
        ];
      case '点击图片':
        return [
          _buildFieldRow('执行延迟', _delayController, '', hint: '毫秒'),
          _buildFieldRow('在...之后搜索', _afterSearchController, ''),
          _buildFieldRow('在...之前搜索', _beforeSearchController, ''),
        ];
      case '间隔时间':
        return [
          _buildFieldRow('执行延迟', _delayController, '', hint: '毫秒'),
          _buildFieldRow('时间间隔-小时', _intervalHoursController, ''),
          _buildFieldRow('时间间隔-分钟', _intervalMinutesController, ''),
          _buildFieldRow('时间间隔-秒', _intervalSecondsController, ''),
        ];
      case '进入网址':
        return [
          _buildFieldRow('执行延迟', _delayController, '', hint: '毫秒'),
          _buildFieldRow('网址', _urlController, '', required: true),
        ];
      case '输入框提交':
        return [
          _buildFieldRow('执行延迟', _delayController, '', hint: '毫秒'),
          _buildFieldRow('提交按钮文字', _submitButtonTextController, ''),
          _buildFieldRow('输入框值', _inputValueController, ''),
        ];
      default:
        return [];
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

  Widget _buildTextField(TextEditingController controller, String placeholder) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: placeholder,
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
      String label, TextEditingController controller, String placeholder,
      {bool required = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
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
            child: _buildTextField(controller, hint ?? placeholder),
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
            width: 120,
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
    final scriptProvider = context.read<ScriptProvider>();

    // Build params based on script type
    final params = <String, dynamic>{};

    // Add type-specific params based on JSON structure
    switch (_selectedScriptType) {
      case '全局设置':
        if (_delayController.text.isEmpty) return;
        params['执行延迟'] = int.tryParse(_delayController.text) ?? 0;
        break;

      case '点击文字':
        if (_clickTextController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = int.tryParse(_delayController.text) ?? 0;
        }
        if (_appearTextController.text.isNotEmpty) {
          params['出现文字'] = _appearTextController.text;
        }
        params['点击文本'] = _clickTextController.text;
        if (_afterSearchController.text.isNotEmpty) {
          params['在...之后搜索'] = _afterSearchController.text;
        }
        if (_beforeSearchController.text.isNotEmpty) {
          params['在...之前搜索'] = _beforeSearchController.text;
        }
        params['完全匹配'] = _exactMatch;
        break;

      case '点击图片':
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = int.tryParse(_delayController.text) ?? 0;
        }
        if (_afterSearchController.text.isNotEmpty) {
          params['在...之后搜索'] = _afterSearchController.text;
        }
        if (_beforeSearchController.text.isNotEmpty) {
          params['在...之前搜索'] = _beforeSearchController.text;
        }
        break;

      case '间隔时间':
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = int.tryParse(_delayController.text) ?? 0;
        }
        if (_intervalHoursController.text.isNotEmpty) {
          params['时间间隔-小时'] = int.tryParse(_intervalHoursController.text) ?? 0;
        }
        if (_intervalMinutesController.text.isNotEmpty) {
          params['时间间隔-分钟'] =
              int.tryParse(_intervalMinutesController.text) ?? 0;
        }
        if (_intervalSecondsController.text.isNotEmpty) {
          params['时间间隔-秒'] = int.tryParse(_intervalSecondsController.text) ?? 0;
        }
        break;

      case '进入网址':
        if (_urlController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = int.tryParse(_delayController.text) ?? 0;
        }
        params['网址'] = _urlController.text;
        break;

      case '输入框提交':
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = int.tryParse(_delayController.text) ?? 0;
        }
        if (_submitButtonTextController.text.isNotEmpty) {
          params['提交按钮文字'] = _submitButtonTextController.text;
        }
        if (_inputValueController.text.isNotEmpty) {
          params['输入框值'] = _inputValueController.text;
        }
        break;
    }

    scriptProvider.addScript(Script(
      type: _selectedScriptType,
      params: params,
      isEnabled: true,
    ));

    Navigator.pop(context);
  }
}

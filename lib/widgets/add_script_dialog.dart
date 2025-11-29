import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../models/script.dart';

class _FormDataItem {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _FormDataItem(String key, String value)
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class AddScriptDialog extends StatefulWidget {
  final Script? script;
  final int? index;
  final bool isNested;

  const AddScriptDialog(
      {super.key, this.script, this.index, this.isNested = false});

  @override
  State<AddScriptDialog> createState() => _AddScriptDialogState();
}

class _AddScriptDialogState extends State<AddScriptDialog> {
  // Script types list (focused on implemented types)
  static const List<String> scriptTypes = [
    '点击文字',
    '输入框提交',
    '进入网址',
    '间隔时间',
    '脚本替换',
    '脚本停止',
    '脚本暂停',
    '点击图片',
    '控制脚本开关',
    '逻辑脚本-出现文字',
    '逻辑脚本-时间对比',
    '逻辑脚本-数值对比',
    '数学运算',
    '数值对比-点击文字',
    '刷新网页',
    '跳转脚本',
    '网页后退',
    '网页前进',
  ];

  String _selectedScriptType = scriptTypes[0];

  // Common fields
  final TextEditingController _repeatCountController = TextEditingController();
  final TextEditingController _loopCountController = TextEditingController();
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

  // Dynamic form fields managed by persistent controllers
  final List<_FormDataItem> _formItems = [];

  // 进入网址 field
  final TextEditingController _urlController = TextEditingController();

  // Generic/Other fields
  final TextEditingController _scriptNameController = TextEditingController();
  final TextEditingController _targetValueController = TextEditingController();
  final TextEditingController _compareValueController = TextEditingController();
  final TextEditingController _jumpLabelController = TextEditingController();

  bool _exactMatch = false;

  // Additional controllers
  final TextEditingController _variableNameController = TextEditingController();
  final TextEditingController _operationController = TextEditingController();
  final TextEditingController _scriptSetController = TextEditingController();

  String _compareMethod = '>';
  bool _switchState = true;
  String _delayTimeUnit = '毫秒'; // Time unit for delay field

  // Nested scripts state
  Script? _beforeScript;
  Script? _afterScript;

  @override
  void initState() {
    super.initState();
    if (widget.script != null) {
      _selectedScriptType = widget.script!.type;
      final params = widget.script!.params;

      _delayController.text = (params['执行延迟'] ?? '').toString();
      _appearTextController.text = params['出现文字'] ?? '';
      _clickTextController.text = params['点击文本'] ?? '';
      _afterSearchController.text = params['在...之后搜索'] ?? '';
      _beforeSearchController.text = params['在...之前搜索'] ?? '';
      _exactMatch = params['完全匹配'] ?? false;

      _intervalHoursController.text = (params['时间间隔-小时'] ?? '').toString();
      _intervalMinutesController.text = (params['时间间隔-分钟'] ?? '').toString();
      _intervalSecondsController.text = (params['时间间隔-秒'] ?? '').toString();

      _urlController.text = params['网址'] ?? '';
      _submitButtonTextController.text = params['提交按钮文字'] ?? '';

      // Load formData map
      final loadedFormData = params['表单数据'];
      if (loadedFormData is Map) {
        loadedFormData.forEach((key, value) {
          _formItems.add(_FormDataItem(key.toString(), value.toString()));
        });
      }

      _scriptNameController.text = params['脚本名称'] ?? '';
      _targetValueController.text = params['目标值'] ?? '';
      _compareValueController.text = params['对比值'] ?? '';
      _jumpLabelController.text = params['跳转标签'] ?? '';

      _variableNameController.text = params['变量名'] ?? '';
      _operationController.text = params['运算方式'] ?? '';
      _scriptSetController.text = params['脚本集名称'] ?? '';
      _compareMethod = params['对比方式'] ?? '>';
      _switchState = params['开关状态'] ?? true;

      if (params['执行每个脚本前执行'] != null) {
        _beforeScript =
            Script.fromUserMap(Map<String, dynamic>.from(params['执行每个脚本前执行']));
      }
      if (params['执行每个脚本后执行'] != null) {
        _afterScript =
            Script.fromUserMap(Map<String, dynamic>.from(params['执行每个脚本后执行']));
      }
    } else {
      _selectedScriptType = scriptTypes[0];
    }
  }

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
    for (var item in _formItems) {
      item.dispose();
    }
    _urlController.dispose();
    _scriptNameController.dispose();
    _targetValueController.dispose();
    _compareValueController.dispose();
    _jumpLabelController.dispose();
    _variableNameController.dispose();
    _operationController.dispose();
    _scriptSetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A2332),
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
                color: const Color(0xFF0D1B2A),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.script != null ? '编辑脚本' : '添加脚本',
                    style: const TextStyle(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Script Type Row
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
                                  onChanged: widget.script == null
                                      ? (String? newValue) {
                                          if (newValue != null) {
                                            setState(() {
                                              _selectedScriptType = newValue;
                                            });
                                          }
                                        }
                                      : null, // Disable type change when editing
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

                    // Nested Scripts Section (Available for all types except Global Settings)
                    if (_selectedScriptType != '全局设置') ...[
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      const Text(
                        '嵌套脚本',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildNestedScriptTile('执行每个脚本前执行', 'beforeScript'),
                      const SizedBox(height: 8),
                      _buildNestedScriptTile('执行每个脚本后执行', 'afterScript'),
                      const SizedBox(height: 16),
                    ],
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
                    backgroundColor: const Color(0xFF5E81AC),
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
    // Common delay field with time unit selector for most types
    final delayField = _buildDelayFieldWithUnit('执行延迟');

    switch (_selectedScriptType) {
      case '全局设置':
        return [
          _buildDelayFieldWithUnit('执行延迟', required: true),
        ];
      case '点击文字':
        return [
          delayField,
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
          delayField,
          _buildFieldRow('在...之后搜索', _afterSearchController, ''),
          _buildFieldRow('在...之前搜索', _beforeSearchController, ''),
        ];
      case '间隔时间':
        return [
          delayField,
          _buildFieldRow('时间间隔-小时', _intervalHoursController, ''),
          _buildFieldRow('时间间隔-分钟', _intervalMinutesController, ''),
          _buildFieldRow('时间间隔-秒', _intervalSecondsController, ''),
        ];
      case '进入网址':
      case '新建标签页并执行脚本':
        return [
          delayField,
          _buildFieldRow('网址', _urlController, '', required: true),
        ];
      case '输入框提交':
        return [
          delayField,
          _buildFieldRow('提交按钮文字', _submitButtonTextController, ''),
          _buildFormDataFields(),
        ];
      case '脚本替换':
      case '脚本停止':
      case '脚本暂停':
      case '刷新网页':
      case '网页后退':
      case '网页前进':
      case '重置限制次数':
        return [delayField];
      case '跳转脚本':
        return [
          delayField,
          _buildFieldRow('跳转标签', _jumpLabelController, '', required: true),
        ];
      case '延时脚本':
        return [
          _buildFieldRow('延时时间', _delayController, '',
              hint: '毫秒', required: true),
        ];
      case '控制脚本开关':
        return [
          delayField,
          _buildCheckboxRow('开关状态', _switchState, (value) {
            setState(() => _switchState = value ?? true);
          }),
        ];
      case '逻辑脚本-出现文字':
        return [
          delayField,
          _buildFieldRow('出现文字', _appearTextController, '', required: true),
          _buildFieldRow('跳转标签', _jumpLabelController, ''),
        ];
      case '逻辑脚本-时间对比':
        return [
          delayField,
          _buildFieldRow('时间(HH:mm:ss)', _targetValueController, '',
              required: true),
          _buildFieldRow('跳转标签', _jumpLabelController, ''),
        ];
      case '逻辑脚本-数值对比':
        return [
          delayField,
          _buildFieldRow('目标值', _targetValueController, '', required: true),
          _buildDropdownRow('对比方式', _compareMethod, ['>', '<', '=', '>=', '<='],
              (val) {
            if (val != null) setState(() => _compareMethod = val);
          }),
          _buildFieldRow('跳转标签', _jumpLabelController, ''),
        ];
      case '数学运算':
        return [
          delayField,
          _buildFieldRow('变量名', _variableNameController, '', required: true),
          _buildFieldRow('运算方式', _operationController, '+, -, *, /',
              required: true),
          _buildFieldRow('值', _targetValueController, '', required: true),
        ];
      case '数值对比-点击文字':
        return [
          delayField,
          _buildFieldRow('点击文本', _clickTextController, '', required: true),
          _buildFieldRow('目标值', _targetValueController, '', required: true),
          _buildDropdownRow('对比方式', _compareMethod, ['>', '<', '=', '>=', '<='],
              (val) {
            if (val != null) setState(() => _compareMethod = val);
          }),
        ];
      case '执行本地脚本集':
        return [
          delayField,
          _buildFieldRow('脚本集名称', _scriptSetController, '', required: true),
        ];
      default:
        return [delayField];
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

  Widget _buildDropdownRow(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
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
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonFormField<String>(
                value: value,
                decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: InputBorder.none,
                ),
                isExpanded: true,
                items: items.map((String item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDelayFieldWithUnit(String label, {bool required = false}) {
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
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                controller: _delayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<String>(
              value: _delayTimeUnit,
              dropdownColor: const Color(0xFF1A2332),
              style: const TextStyle(color: Colors.black, fontSize: 14),
              underline: Container(),
              isDense: true,
              items: const [
                DropdownMenuItem(value: '毫秒', child: Text('毫秒')),
                DropdownMenuItem(value: '秒', child: Text('秒')),
                DropdownMenuItem(value: '分', child: Text('分')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _delayTimeUnit = value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormDataFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '表单字段',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        ..._formItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: TextField(
                      controller: item.keyController,
                      decoration: const InputDecoration(
                        hintText: '字段名 (name/id)',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: TextField(
                      controller: item.valueController,
                      decoration: const InputDecoration(
                        hintText: '字段值',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _formItems[index].dispose();
                      _formItems.removeAt(index);
                    });
                  },
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _formItems
                  .add(_FormDataItem('field${_formItems.length + 1}', ''));
            });
          },
          icon: const Icon(Icons.add, color: Colors.white, size: 18),
          label: const Text('添加字段',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ],
    );
  }

  Widget _buildNestedScriptTile(String label, String type) {
    final script = type == 'beforeScript' ? _beforeScript : _afterScript;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: ListTile(
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        subtitle: Text(
          script != null ? '${script.type} (已配置)' : '未配置',
          style: TextStyle(
            color: script != null ? Colors.blueAccent : Colors.grey,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (script != null)
              IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.redAccent, size: 18),
                onPressed: () {
                  setState(() {
                    if (type == 'beforeScript') {
                      _beforeScript = null;
                    } else {
                      _afterScript = null;
                    }
                  });
                },
              ),
            IconButton(
              icon: Icon(script != null ? Icons.edit : Icons.add,
                  color: Colors.white, size: 18),
              onPressed: () async {
                final result = await showDialog<Script>(
                  context: context,
                  builder: (context) => AddScriptDialog(
                    script: script,
                    isNested: true, // Pass a flag to indicate nested mode
                  ),
                );

                if (result != null) {
                  setState(() {
                    if (type == 'beforeScript') {
                      _beforeScript = result;
                    } else {
                      _afterScript = result;
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to convert delay to milliseconds based on selected unit
  int _convertDelayToMilliseconds() {
    final value = int.tryParse(_delayController.text) ?? 0;
    switch (_delayTimeUnit) {
      case '秒':
        return value * 1000;
      case '分':
        return value * 60000;
      default: // '毫秒'
        return value;
    }
  }

  void _handleSubmit() {
    final scriptProvider = context.read<ScriptProvider>();

    // Build params based on script type
    final params = <String, dynamic>{};

    // Add type-specific params based on JSON structure
    switch (_selectedScriptType) {
      case '全局设置':
        if (_delayController.text.isEmpty) return;
        params['执行延迟'] = _convertDelayToMilliseconds();
        break;

      case '点击文字':
        if (_clickTextController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
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
          params['执行延迟'] = _convertDelayToMilliseconds();
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
          params['执行延迟'] = _convertDelayToMilliseconds();
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
      case '新建标签页并执行脚本':
        if (_urlController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['网址'] = _urlController.text;
        break;

      case '输入框提交':
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        if (_submitButtonTextController.text.isNotEmpty) {
          params['提交按钮文字'] = _submitButtonTextController.text;
        }
        // Reconstruct formData from _formItems
        if (_formItems.isNotEmpty) {
          final formDataMap = <String, String>{};
          for (var item in _formItems) {
            if (item.keyController.text.isNotEmpty) {
              formDataMap[item.keyController.text] = item.valueController.text;
            }
          }
          if (formDataMap.isNotEmpty) {
            params['表单数据'] = Map<String, dynamic>.from(formDataMap);
          }
        }
        break;

      case '跳转脚本':
        if (_jumpLabelController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['跳转标签'] = _jumpLabelController.text;
        break;

      case '延时脚本':
        if (_delayController.text.isEmpty) return;
        params['延时时间'] = int.tryParse(_delayController.text) ?? 0;
        break;

      case '控制脚本开关':
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['开关状态'] = _switchState;
        break;

      case '逻辑脚本-出现文字':
        if (_appearTextController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['出现文字'] = _appearTextController.text;
        if (_jumpLabelController.text.isNotEmpty) {
          params['跳转标签'] = _jumpLabelController.text;
        }
        break;

      case '逻辑脚本-时间对比':
        if (_targetValueController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['目标值'] = _targetValueController.text;
        if (_jumpLabelController.text.isNotEmpty) {
          params['跳转标签'] = _jumpLabelController.text;
        }
        break;

      case '逻辑脚本-数值对比':
        if (_targetValueController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['目标值'] = _targetValueController.text;
        params['对比方式'] = _compareMethod;
        if (_jumpLabelController.text.isNotEmpty) {
          params['跳转标签'] = _jumpLabelController.text;
        }
        break;

      case '数学运算':
        if (_variableNameController.text.isEmpty) return;
        if (_targetValueController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['变量名'] = _variableNameController.text;
        params['运算方式'] = _operationController.text;
        params['目标值'] = _targetValueController.text;
        break;

      case '数值对比-点击文字':
        if (_clickTextController.text.isEmpty) return;
        if (_targetValueController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['点击文本'] = _clickTextController.text;
        params['目标值'] = _targetValueController.text;
        params['对比方式'] = _compareMethod;
        break;

      case '执行本地脚本集':
        if (_scriptSetController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['脚本集名称'] = _scriptSetController.text;
        break;

      default:
        // For other types, just save delay if present
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        break;
    }

    // Save nested scripts
    if (_beforeScript != null) {
      params['执行每个脚本前执行'] = _beforeScript!.toUserMap();
    }
    if (_afterScript != null) {
      params['执行每个脚本后执行'] = _afterScript!.toUserMap();
    }

    final newScript = Script(
      type: _selectedScriptType,
      params: params,
      isEnabled: true,
    );

    if (widget.isNested) {
      Navigator.pop(context, newScript);
      return;
    }

    if (widget.script != null && widget.index != null) {
      // Update existing script
      scriptProvider.updateScript(widget.index!, newScript);
      Navigator.pop(context);
    } else {
      // Return new script for external handling (insertScript or addScript)
      Navigator.pop(context, newScript);
    }
  }
}

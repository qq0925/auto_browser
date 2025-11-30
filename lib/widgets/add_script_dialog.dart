import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../providers/browser_provider.dart';
import '../models/script.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

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
    '自定义JS',
    '点击图片',
    '刷新网页',
    '网页后退',
    '网页前进',
    '脚本替换',
    '脚本停止',
    '脚本暂停',
    '执行本地脚本集',
    '控制脚本开关',
    '通知栏提醒',
    '逻辑脚本-出现文字',
    '逻辑脚本-时间对比',
    '逻辑脚本-数值对比',
    '数学运算',
    '延时脚本',
    '数值对比-点击文字',
    '新建窗口并执行脚本',
    '跳转脚本',
  ];

  String _selectedScriptType = scriptTypes[0];

  // Common fields
  final TextEditingController _repeatCountController = TextEditingController();
  final TextEditingController _customJsController = TextEditingController();

  final TextEditingController _delayController = TextEditingController();
  final TextEditingController _appearTextController = TextEditingController();
  final TextEditingController _clickTextController = TextEditingController();
  final TextEditingController _afterSearchController = TextEditingController();
  final TextEditingController _beforeSearchController = TextEditingController();
  final TextEditingController _multipleSelectionController =
      TextEditingController();

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
  final TextEditingController _notificationContentController =
      TextEditingController();

  bool _exactMatch = false;
  bool _enableRegex = false;

  // Additional controllers
  final TextEditingController _variableNameController = TextEditingController();
  final TextEditingController _operationController = TextEditingController();
  final TextEditingController _scriptSetController = TextEditingController();

  String _compareMethod = '>';
  bool _switchState = true;
  String _delayTimeUnit = '毫秒'; // Time unit for delay field
  String? _jsFilePath; // Path to selected JS file
  String? _targetScriptPath; // Path to target script set for replacement

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
      _afterSearchController.text = params['在此之后'] ?? '';
      _beforeSearchController.text = params['在此之前'] ?? '';
      _multipleSelectionController.text = (params['多个筛选'] ?? 1).toString();
      _exactMatch = params['完全匹配'] ?? false;
      _enableRegex = params['启用正则'] ?? false;

      _intervalHoursController.text = (params['时间间隔-小时'] ?? '').toString();
      _intervalMinutesController.text = (params['时间间隔-分钟'] ?? '').toString();
      _intervalSecondsController.text = (params['时间间隔-秒'] ?? '').toString();

      _urlController.text = params['网址'] ?? '';
      _customJsController.text = params['代码'] ?? '';
      _jsFilePath = params['jsFilePath'];
      _targetScriptPath =
          params['脚本集']; // Load target script path for replacement
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
      _notificationContentController.text = params['提醒内容'] ?? '';

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
    _customJsController.dispose();

    _delayController.dispose();
    _appearTextController.dispose();
    _clickTextController.dispose();
    _afterSearchController.dispose();
    _beforeSearchController.dispose();
    _multipleSelectionController.dispose();
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
    _notificationContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        context.select<BrowserProvider, bool>((p) => p.isDarkMode);

    // Theme Colors
    final backgroundColor = isDarkMode ? const Color(0xFF1A2332) : Colors.white;
    final headerColor =
        isDarkMode ? const Color(0xFF0D1B2A) : const Color(0xFFF5F5F5);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white70 : Colors.black54;
    final inputFillColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final iconColor = isDarkMode ? Colors.white : Colors.black54;

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: headerColor,
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
                    widget.script != null ? '编辑脚本' : '添加脚本',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: iconColor, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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
                              _buildLabel('脚本类型', color: labelColor),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                value: _selectedScriptType,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  filled: true,
                                  fillColor: inputFillColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        const BorderSide(color: Colors.blue),
                                  ),
                                ),
                                dropdownColor: isDarkMode
                                    ? const Color(0xFF2C2C2C)
                                    : Colors.white,
                                style:
                                    TextStyle(fontSize: 14, color: textColor),
                                icon: Icon(Icons.arrow_drop_down,
                                    color: iconColor),
                                menuMaxHeight: 300, // Limit height
                                items: scriptTypes.map((String type) {
                                  return DropdownMenuItem<String>(
                                    value: type,
                                    child: Text(type),
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
                                    : null,
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
                                _buildLabel('循环次数'),
                                const SizedBox(height: 4),
                                _buildTextField(_repeatCountController, '1'),
                              ],
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    if (_selectedScriptType != '全局设置')
                      // Execution Delay (Common for all types)
                      _buildDelayFieldWithUnit('执行延迟'),

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
    switch (_selectedScriptType) {
      case '全局设置':
        return [
          // Global settings might need its own delay field if it was special,
          // but user said "All types have these fields".
          // However, '全局设置' is usually a meta-script.
          // Let's keep it empty here as delay is now common.
          // Wait, if '全局设置' is selected, the common block above excludes it.
          // So we need to add delay here for '全局设置' OR enable common block for it.
          // The user said "These types of scripts..." referring to the list.
          // '全局设置' is NOT in the list the user provided.
          // The user provided list: '点击文字', '输入框提交', ..., '网页前进'.
          // So '全局设置' is likely a special internal type or legacy.
          // I will assume '全局设置' stays as is or I should check if it's in the list.
          // It is NOT in the user's list.
          // So I will leave '全局设置' handling alone?
          // Actually, the common block has `if (_selectedScriptType != '全局设置')`.
          // So for '全局设置', delay is NOT added by common block.
          // I should keep it here for '全局设置'.
          _buildDelayFieldWithUnit('执行延迟', required: true),
        ];
      case '点击文字':
        return [
          _buildFieldRow('出现文字', _appearTextController, ''),
          _buildFieldRow('点击文本', _clickTextController, '', required: true),
          _buildFieldRow('在...之后搜索', _afterSearchController, ''),
          _buildFieldRow('在...之前搜索', _beforeSearchController, ''),
          _buildFieldRow('多个筛选', _multipleSelectionController, '1',
              hint: '1:第一个, -1:最后一个, 0:随机'),
          _buildCheckboxRow('完全匹配', _exactMatch, (value) {
            setState(() => _exactMatch = value ?? false);
          }),
        ];
      case '点击图片':
        return [
          _buildFieldRow('在...之后搜索', _afterSearchController, ''),
          _buildFieldRow('在...之前搜索', _beforeSearchController, ''),
        ];
      case '间隔时间':
        return [
          _buildFieldRow('时间间隔-小时', _intervalHoursController, ''),
          _buildFieldRow('时间间隔-分钟', _intervalMinutesController, ''),
          _buildFieldRow('时间间隔-秒', _intervalSecondsController, ''),
        ];
      case '自定义JS':
        return [
          // File Picker Row
          Row(
            children: [
              Expanded(
                child: Text(
                  _jsFilePath != null
                      ? '已选择: ${_jsFilePath!.split(Platform.pathSeparator).last}'
                      : '未选择文件',
                  style: TextStyle(
                    color: _jsFilePath != null ? Colors.green : Colors.grey,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  FilePickerResult? result =
                      await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['js'],
                  );

                  if (result != null) {
                    File file = File(result.files.single.path!);
                    String content = await file.readAsString();
                    setState(() {
                      _jsFilePath = result.files.single.path;
                      _customJsController.text = content;
                    });
                  }
                },
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('选择JS文件'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ];
      case '进入网址':
      case '新建标签页并执行脚本':
        return [
          _buildFieldRow('网址', _urlController, '', required: true),
        ];
      case '输入框提交':
        return [
          _buildFieldRow('提交按钮文字', _submitButtonTextController, ''),
          _buildFieldRow('多个筛选', _multipleSelectionController, '1',
              hint: '0:随机, >0:第几个, <0:倒数第几个'),
          _buildCheckboxRow('启用正则', _enableRegex, (value) {
            setState(() => _enableRegex = value ?? false);
          }),
          if (_enableRegex)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                '*勾起代表输入内容为正则表达式，提交时会生成匹配的一个随机字符串\n例如：输入 [0-9]{6} 代表6位随机数字\n输入 [a-z]{3} 代表3位随机小写字母\n输入 ab[a-zA-Z]{2}[0-9]{3} 代表ab跟上2个字母和3个数字',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ),
          _buildFormDataFields(),
        ];
      case '脚本替换':
      case '执行本地脚本集':
        return [
          _buildScriptPathField(),
        ];
      case '脚本停止':
      case '脚本暂停':
      case '刷新网页':
      case '网页后退':
      case '网页前进':
      case '重置限制次数':
      case '延时脚本':
        return [];
      case '逻辑脚本-出现文字':
        return [
          _buildFieldRow('出现文字', _appearTextController, '', required: true),
          _buildFieldRow('跳转标签', _jumpLabelController, ''),
        ];
      case '逻辑脚本-时间对比':
        return [
          _buildFieldRow('时间(HH:mm:ss)', _targetValueController, '',
              required: true),
          _buildFieldRow('跳转标签', _jumpLabelController, ''),
        ];
      case '逻辑脚本-数值对比':
        return [
          _buildFieldRow('目标值', _targetValueController, '', required: true),
          _buildDropdownRow('对比方式', _compareMethod, ['>', '<', '=', '>=', '<='],
              (val) {
            if (val != null) setState(() => _compareMethod = val);
          }),
          _buildFieldRow('跳转标签', _jumpLabelController, ''),
        ];
      case '数学运算':
        return [
          _buildFieldRow('变量名', _variableNameController, '', required: true),
          _buildFieldRow('运算方式', _operationController, '+, -, *, /',
              required: true),
          _buildFieldRow('值', _targetValueController, '', required: true),
        ];
      case '数值对比-点击文字':
        return [
          _buildFieldRow('点击文本', _clickTextController, '', required: true),
          _buildFieldRow('目标值', _targetValueController, '', required: true),
          _buildDropdownRow('对比方式', _compareMethod, ['>', '<', '=', '>=', '<='],
              (val) {
            if (val != null) setState(() => _compareMethod = val);
          }),
        ];

      case '通知栏提醒':
        return [
          _buildFieldRow('提醒内容', _notificationContentController, '',
              required: true),
        ];
      default:
        return [];
    }
  }

  Widget _buildLabel(String text, {Color? color}) {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final textColor = color ?? (isDarkMode ? Colors.white70 : Colors.black54);
    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: 13,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String placeholder) {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final inputFillColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final hintColor = isDarkMode ? Colors.white38 : Colors.black38;

    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 14, color: textColor),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(color: hintColor, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: inputFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blue),
        ),
      ),
    );
  }

  Widget _buildFieldRow(
      String label, TextEditingController controller, String placeholder,
      {bool required = false, String? hint}) {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final labelColor = isDarkMode ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(color: labelColor, fontSize: 13),
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
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final labelColor = isDarkMode ? Colors.white : Colors.black87;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade400;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: labelColor, fontSize: 13),
            ),
          ),
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.blue,
              side: BorderSide(color: borderColor, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final labelColor = isDarkMode ? Colors.white : Colors.black87;
    final inputFillColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final iconColor = isDarkMode ? Colors.white : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: labelColor, fontSize: 13),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: value,
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                filled: true,
                fillColor: inputFillColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
              ),
              dropdownColor:
                  isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
              style: TextStyle(fontSize: 14, color: textColor),
              icon: Icon(Icons.arrow_drop_down, color: iconColor),
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDelayFieldWithUnit(String label, {bool required = false}) {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final labelColor = isDarkMode ? Colors.white : Colors.black87;
    final inputFillColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final iconColor = isDarkMode ? Colors.white : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(color: labelColor, fontSize: 13),
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
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTextField(_delayController, '0'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _delayTimeUnit,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                      filled: true,
                      fillColor: inputFillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                    ),
                    dropdownColor:
                        isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                    style: TextStyle(fontSize: 14, color: textColor),
                    icon: Icon(Icons.arrow_drop_down, color: iconColor),
                    items: ['毫秒', '秒', '分钟'].map((String unit) {
                      return DropdownMenuItem<String>(
                        value: unit,
                        child: Text(unit),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _delayTimeUnit = newValue;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptPathField() {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final labelColor = isDarkMode ? Colors.white : Colors.black87;
    final inputFillColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final hintColor = isDarkMode ? Colors.white38 : Colors.black38;
    final iconColor = isDarkMode ? Colors.white : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '目标脚本集',
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: inputFillColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  _targetScriptPath != null
                      ? _targetScriptPath!.split(Platform.pathSeparator).last
                      : '未选择文件',
                  style: TextStyle(
                    color: _targetScriptPath != null ? textColor : hintColor,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () async {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );

                if (result != null) {
                  setState(() {
                    _targetScriptPath = result.files.single.path;
                  });
                }
              },
              icon: Icon(Icons.folder_open, color: iconColor),
              tooltip: '选择脚本集文件',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormDataFields() {
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final labelColor = isDarkMode ? Colors.white : Colors.black87;
    final inputFillColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final hintColor = isDarkMode ? Colors.white38 : Colors.black38;
    final iconColor = isDarkMode ? Colors.white : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '表单字段',
            style: TextStyle(color: labelColor, fontSize: 13),
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
                  child: TextField(
                    controller: item.keyController,
                    decoration: InputDecoration(
                      hintText: '字段名 (name/id)',
                      hintStyle: TextStyle(color: hintColor, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: inputFillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 13, color: textColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: item.valueController,
                    decoration: InputDecoration(
                      hintText: '字段值',
                      hintStyle: TextStyle(color: hintColor, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: inputFillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 13, color: textColor),
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
          icon: Icon(Icons.add, color: iconColor, size: 18),
          label: Text('添加字段', style: TextStyle(color: iconColor, fontSize: 13)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ],
    );
  }

  Widget _buildNestedScriptTile(String label, String type) {
    final script = type == 'beforeScript' ? _beforeScript : _afterScript;
    final isDarkMode = context.read<BrowserProvider>().isDarkMode;
    final tileColor = isDarkMode ? Colors.white10 : Colors.grey.shade100;
    final borderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final iconColor = isDarkMode ? Colors.white : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(color: textColor, fontSize: 13),
        ),
        subtitle: Text(
          script != null ? '${script.type} (已配置)' : '未配置',
          style: TextStyle(
            color: script != null
                ? Colors.blueAccent
                : (isDarkMode ? Colors.grey : Colors.grey.shade600),
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
                  color: iconColor, size: 18),
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
        params['点击文本'] = _clickTextController.text;
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

      case '间隔时间':
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

      case '自定义JS':
        if (_customJsController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['代码'] = _customJsController.text;
        if (_jsFilePath != null) {
          params['jsFilePath'] = _jsFilePath;
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
        params['多个筛选'] = int.tryParse(_multipleSelectionController.text) ?? 1;
        params['启用正则'] = _enableRegex;
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

      case '脚本替换':
      case '执行本地脚本集':
        if (_targetScriptPath == null) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['脚本集'] = _targetScriptPath;
        break;

      case '脚本停止':
      case '脚本暂停':
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
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
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
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

      case '通知栏提醒':
        if (_notificationContentController.text.isEmpty) return;
        if (_delayController.text.isNotEmpty) {
          params['执行延迟'] = _convertDelayToMilliseconds();
        }
        params['提醒内容'] = _notificationContentController.text;
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

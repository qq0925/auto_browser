import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' show WebUri;
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../providers/browser_provider.dart';
import '../models/script.dart';
import 'add_script_dialog.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import '../utils/file_manager.dart';

class RightScriptPanel extends StatelessWidget {
  final VoidCallback onAddScript;
  final VoidCallback onGlobalSettings;
  final VoidCallback onExecute;
  final VoidCallback onLoad;
  final VoidCallback? onRecordScript; // Optional callback for recording

  const RightScriptPanel({
    super.key,
    required this.onAddScript,
    required this.onGlobalSettings,
    required this.onExecute,
    required this.onLoad,
    this.onRecordScript,
  });

  @override
  Widget build(BuildContext context) {
    final scriptProvider = context.watch<ScriptProvider>();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62), // 半透明暗黑背景，清晰透视底层网页内容，方便查看与复制
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(11.5)),
        child: Column(
          children: [
          // --- Top Section: Global Settings ---
          InkWell(
            onTap: onGlobalSettings,
            child: Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
              child: Stack(
                children: [
                  // 嵌在最左上角: 全局（纯文本无框，紧贴左上角）
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, top: 4),
                      child: const Text(
                        '全局',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // 中间居中: 执行延迟 / 循环次数 (内部左对齐，上下成列完美对齐)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '执行延迟: ',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10.5,
                              ),
                            ),
                            Text(
                              '${scriptProvider.executionDelay ~/ scriptProvider.delayTimeUnit.multiplier}${scriptProvider.delayTimeUnit.label}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '循环次数: ',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10.5,
                              ),
                            ),
                            Text(
                              '${scriptProvider.originalLoopCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 分割线：全局与中间内容分隔
          const Divider(height: 1, color: Colors.white24),

          // --- 脚本文件名展示条 (当脚本已载入或已保存为文件时展示) ---
          if (scriptProvider.currentScriptFilePath != null &&
              scriptProvider.currentScriptFilePath!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              color: Colors.white.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: Colors.amberAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      path.basename(scriptProvider.currentScriptFilePath!),
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${scriptProvider.scripts.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
          ],

          // --- Middle Section: Script List & Management ---
          Expanded(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
                  color: Colors.white.withValues(alpha: 0.04),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '脚本列表 (${scriptProvider.scripts.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Divider (Subtle)
                const Divider(height: 1, color: Colors.white12),

                // Scrollable List
                Expanded(
                  child: scriptProvider.scripts.isEmpty
                      ? _buildEmptyState(scriptProvider)
                      : ListView.builder(
                          itemCount: scriptProvider.scripts.length,
                          itemBuilder: (context, index) =>
                              _buildScriptItem(context, scriptProvider, index),
                        ),
                ),

                // Divider (Subtle)
                const Divider(height: 1, color: Colors.white12),

                // Add Script Button
                InkWell(
                  onTap: onAddScript,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '添加脚本',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider 2 (White) - Separates Middle and Bottom
          Container(height: 1, color: Colors.white),

          // --- Bottom Section: Action Buttons ---
          IntrinsicHeight(
            child: scriptProvider.isExecuting
                ? _buildExecutingActions(scriptProvider)
                : _buildIdleActions(context, scriptProvider),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildEmptyState(ScriptProvider scriptProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '暂无脚本',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              if (!scriptProvider.isExecuting) {
                onRecordScript?.call();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                  SizedBox(width: 4),
                  Text(
                    '录制脚本',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 提取脚本的结构化属性键值对（参考原版设计，丰富展现复杂脚本详细信息）
  List<MapEntry<String, String>> _extractScriptDetails(Script script) {
    final List<MapEntry<String, String>> list = [];
    final params = script.params;
    final handledKeys = <String>{'脚本类型'};

    // 1. 脚本类型永远排在第一行
    list.add(MapEntry('脚本类型', script.type));

    // 2. 根据脚本类型或具体参数填充详细字段
    switch (script.type) {
      case '新建窗口并执行脚本':
        final boundScript = params['绑定脚本'] ?? params['脚本集'] ?? script.targetScriptPath;
        if (boundScript != null && boundScript.toString().isNotEmpty) {
          list.add(MapEntry('绑定脚本', path.basename(boundScript.toString())));
          handledKeys.addAll(['绑定脚本', '脚本集']);
        }
        if (params['窗口名称'] != null && params['窗口名称'].toString().isNotEmpty) {
          list.add(MapEntry('窗口名称', params['窗口名称'].toString()));
          handledKeys.add('窗口名称');
        }
        if (params['窗口UA'] != null && params['窗口UA'].toString().isNotEmpty) {
          list.add(MapEntry('窗口UA', params['窗口UA'].toString()));
          handledKeys.add('窗口UA');
        }
        final url = params['进入网址'] ?? params['网址'];
        if (url != null && url.toString().isNotEmpty) {
          list.add(MapEntry('进入网址', url.toString()));
          handledKeys.addAll(['进入网址', '网址']);
        }
        if (params.containsKey('立即执行')) {
          final execNow = params['立即执行'];
          list.add(MapEntry('立即执行', (execNow == true || execNow == '是') ? '是' : '否'));
          handledKeys.add('立即执行');
        }
        break;

      case '新建标签页并执行脚本':
        final url = params['进入网址'] ?? params['网址'];
        if (url != null && url.toString().isNotEmpty) {
          list.add(MapEntry('进入网址', url.toString()));
          handledKeys.addAll(['进入网址', '网址']);
        }
        break;

      case '点击文字':
        final clickText = params['点击文本'] ?? params['文本'];
        if (clickText != null && clickText.toString().isNotEmpty) {
          list.add(MapEntry('点击文本', clickText.toString()));
          handledKeys.addAll(['点击文本', '文本']);
        }
        if (params['多个筛选'] != null) {
          final filter = params['多个筛选'];
          String filterStr = '第1个';
          if (filter == 0) {
            filterStr = '随机';
          } else if (filter is num && filter < 0) {
            filterStr = '倒数第${-filter}个';
          } else if (filter != null) {
            filterStr = '第$filter个';
          }
          list.add(MapEntry('多个筛选', filterStr));
          handledKeys.add('多个筛选');
        }
        final after = params['在...之后搜索'] ?? params['在此之后'];
        if (after != null && after.toString().isNotEmpty) {
          list.add(MapEntry('在后搜索', after.toString()));
          handledKeys.addAll(['在...之后搜索', '在此之后']);
        }
        final before = params['在...之前搜索'] ?? params['在此之前'];
        if (before != null && before.toString().isNotEmpty) {
          list.add(MapEntry('在前搜索', before.toString()));
          handledKeys.addAll(['在...之前搜索', '在此之前']);
        }
        if (params['完全匹配'] == true) {
          list.add(const MapEntry('完全匹配', '是'));
          handledKeys.add('完全匹配');
        }
        break;

      case '点击图片':
        final img = params['图片特征'] ?? params['图片关键词/地址'] ?? params['点击文本'];
        if (img != null && img.toString().isNotEmpty) {
          list.add(MapEntry('图片特征', img.toString()));
          handledKeys.addAll(['图片特征', '图片关键词/地址', '点击文本']);
        }
        if (params['多个筛选'] != null) {
          final filter = params['多个筛选'];
          String filterStr = '第1个';
          if (filter == 0) {
            filterStr = '随机';
          } else if (filter is num && filter < 0) {
            filterStr = '倒数第${-filter}个';
          } else if (filter != null) {
            filterStr = '第$filter个';
          }
          list.add(MapEntry('多个筛选', filterStr));
          handledKeys.add('多个筛选');
        }
        break;

      case '输入框提交':
        final btnText = params['提交按钮文字'] ?? params['提交按钮'];
        if (btnText != null && btnText.toString().isNotEmpty) {
          list.add(MapEntry('提交按钮', btnText.toString()));
          handledKeys.addAll(['提交按钮文字', '提交按钮']);
        }
        final formData = params['表单数据'];
        if (formData is Map && formData.isNotEmpty) {
          final summary = formData.entries.map((e) => '${e.key}: ${e.value}').join(', ');
          list.add(MapEntry('表单数据', summary));
          handledKeys.add('表单数据');
        }
        if (params['启用正则'] == true) {
          list.add(const MapEntry('正则匹配', '是'));
          handledKeys.add('启用正则');
        }
        break;

      case '进入网址':
        final url = params['进入网址'] ?? params['网址'];
        if (url != null && url.toString().isNotEmpty) {
          list.add(MapEntry('进入网址', url.toString()));
          handledKeys.addAll(['进入网址', '网址']);
        }
        break;

      case '自定义JS':
        final jsPath = params['jsFilePath']?.toString();
        if (jsPath != null && jsPath.isNotEmpty) {
          list.add(MapEntry('关联文件', path.basename(jsPath)));
          handledKeys.add('jsFilePath');
        } else {
          final code = (params['代码'] ?? params['js内容'] ?? '').toString().trim();
          if (code.isNotEmpty) {
            final firstLine = code.split('\n').first.trim();
            list.add(MapEntry('代码内容', firstLine.length > 30 ? '${firstLine.substring(0, 30)}...' : firstLine));
          }
        }
        handledKeys.addAll(['代码', 'js内容']);
        break;

      case '间隔时间':
        final h = params['时间间隔-小时'] ?? 0;
        final m = params['时间间隔-分钟'] ?? 0;
        final s = params['时间间隔-秒'] ?? 0;
        list.add(MapEntry('等待时间', '$h时$m分$s秒'));
        handledKeys.addAll(['时间间隔-小时', '时间间隔-分钟', '时间间隔-秒']);
        final target = params['间隔时间后执行脚本'] ?? script.targetScriptPath;
        if (target != null && target.toString().isNotEmpty) {
          list.add(MapEntry('后续执行', path.basename(target.toString())));
          handledKeys.add('间隔时间后执行脚本');
        }
        break;

      case '跳转脚本':
        final targetIdx = params['跳转的脚本序号'] ?? params['跳转至序号'] ?? params['跳转标签'];
        if (targetIdx != null && targetIdx.toString().isNotEmpty) {
          list.add(MapEntry('跳转序号', targetIdx.toString()));
          handledKeys.addAll(['跳转的脚本序号', '跳转至序号', '跳转标签']);
        }
        break;

      case '延时脚本':
        final delay = params['延时时间'] ?? params['执行延迟'];
        if (delay != null) {
          list.add(MapEntry('延时时长', '${delay}ms'));
          handledKeys.addAll(['延时时间', '执行延迟']);
        }
        break;

      case '逻辑脚本-出现文字':
        final txt = params['出现文字'] ?? params['检测文字'];
        if (txt != null && txt.toString().isNotEmpty) {
          list.add(MapEntry('出现文字', txt.toString()));
          handledKeys.addAll(['出现文字', '检测文字']);
        }
        final truePath = params['出现时执行'] ?? params['满足执行'];
        if (truePath != null && truePath.toString().isNotEmpty) {
          list.add(MapEntry('满足执行', path.basename(truePath.toString())));
          handledKeys.addAll(['出现时执行', '满足执行']);
        }
        final falsePath = params['未出现时执行'] ?? params['不满足执行'];
        if (falsePath != null && falsePath.toString().isNotEmpty) {
          list.add(MapEntry('未出现执行', path.basename(falsePath.toString())));
          handledKeys.addAll(['未出现时执行', '不满足执行']);
        }
        break;

      case '逻辑脚本-时间对比':
        final targetVal = params['目标值'] ?? params['目标时间'];
        if (targetVal != null && targetVal.toString().isNotEmpty) {
          list.add(MapEntry('目标时间', targetVal.toString()));
          handledKeys.addAll(['目标值', '目标时间']);
        }
        final afterTime = params['出现时执行'] ?? params['时间后执行'];
        if (afterTime != null && afterTime.toString().isNotEmpty) {
          list.add(MapEntry('时间后执行', path.basename(afterTime.toString())));
          handledKeys.addAll(['出现时执行', '时间后执行']);
        }
        break;

      case '逻辑脚本-数值对比':
      case '数值对比-点击文字':
        if (params['点击文本'] != null && params['点击文本'].toString().isNotEmpty) {
          list.add(MapEntry('点击文本', params['点击文本'].toString()));
          handledKeys.add('点击文本');
        }
        final cmp = '${params['对比方式'] ?? ''} ${params['目标值'] ?? ''}'.trim();
        if (cmp.isNotEmpty) {
          list.add(MapEntry('对比规则', cmp));
          handledKeys.addAll(['对比方式', '目标值']);
        }
        final satisfied = params['出现时执行'] ?? params['满足执行'];
        if (satisfied != null && satisfied.toString().isNotEmpty) {
          list.add(MapEntry('满足执行', path.basename(satisfied.toString())));
          handledKeys.addAll(['出现时执行', '满足执行']);
        }
        break;

      case '脚本替换':
      case '执行本地脚本集':
        final setPath = params['脚本集'] ?? script.targetScriptPath;
        if (setPath != null && setPath.toString().isNotEmpty) {
          list.add(MapEntry('绑定脚本', path.basename(setPath.toString())));
          handledKeys.add('脚本集');
        }
        break;

      case '控制脚本开关':
        if (params['脚本序号'] != null && params['脚本序号'].toString().isNotEmpty) {
          list.add(MapEntry('目标序号', params['脚本序号'].toString()));
          handledKeys.add('脚本序号');
        }
        if (params['开关动作'] != null && params['开关动作'].toString().isNotEmpty) {
          list.add(MapEntry('更改为', params['开关动作'].toString()));
          handledKeys.add('开关动作');
        }
        break;

      case '设置Cookie':
        if (params['账号存档名称'] != null && params['账号存档名称'].toString().isNotEmpty) {
          list.add(MapEntry('账号存档', params['账号存档名称'].toString()));
          handledKeys.add('账号存档名称');
        } else if (params['Cookie名称'] != null && params['Cookie名称'].toString().isNotEmpty) {
          list.add(MapEntry('Cookie', '${params['Cookie名称']}=${params['Cookie值'] ?? ''}'));
          handledKeys.addAll(['Cookie名称', 'Cookie值']);
        }
        break;

      case '提取文字':
        if (params['CSS选择器'] != null && params['CSS选择器'].toString().isNotEmpty) {
          list.add(MapEntry('CSS选择器', params['CSS选择器'].toString()));
          handledKeys.add('CSS选择器');
        }
        if (params['保存至变量'] != null && params['保存至变量'].toString().isNotEmpty) {
          list.add(MapEntry('保存变量', params['保存至变量'].toString()));
          handledKeys.add('保存至变量');
        }
        break;

      default:
        // 通用降级文本
        final content = _getScriptContent(script);
        if (content.isNotEmpty) {
          list.add(MapEntry('内容', content));
        }
        break;
    }

    // 通用支持：若用户 params 中还包含其他未展示的非空键，优雅补充展示
    params.forEach((key, val) {
      if (!handledKeys.contains(key) &&
          key != '执行延迟' &&
          key != 'isEnabled' &&
          val != null &&
          val.toString().trim().isNotEmpty &&
          !key.startsWith('_')) {
        list.add(MapEntry(key, val.toString()));
      }
    });

    // 通用字段：执行延迟 (若设置且大于0)
    if (params['执行延迟'] != null && params['执行延迟'] is num && params['执行延迟'] > 0) {
      list.add(MapEntry('执行延迟', '${params['执行延迟']}ms'));
    }

    return list;
  }

  Widget _buildScriptItem(
      BuildContext context, ScriptProvider scriptProvider, int index) {
    final script = scriptProvider.scripts[index];
    final isCurrent = scriptProvider.isExecuting &&
        scriptProvider.currentScriptIndex == index;
    final details = _extractScriptDetails(script);

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AddScriptDialog(
            script: script,
            index: index,
          ),
        );
      },
      onLongPress: () {
        _showScriptContextMenu(context, scriptProvider, index);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        color: isCurrent ? Colors.blue.withValues(alpha: 0.3) : null,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 结构化多行键值对列表（与原版图片排版风格完全一致）
            ...details.asMap().entries.map((entry) {
              final detailIdx = entry.key;
              final item = entry.value;
              final isFirstRow = detailIdx == 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 2.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧标签列 (固定宽度 52px，左对齐，柔和灰白色)
                    SizedBox(
                      width: 52,
                      child: Text(
                        item.key,
                        style: TextStyle(
                          color: script.isEnabled ? Colors.white70 : Colors.white38,
                          fontSize: 10.5,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 右侧内容列 (第一行适当提亮，支持折行与溢出保护)
                    Expanded(
                      child: Text(
                        item.value,
                        style: TextStyle(
                          color: script.isEnabled
                              ? (isFirstRow ? Colors.white : Colors.white.withValues(alpha: 0.9))
                              : Colors.white38,
                          fontSize: 10.5,
                          fontWeight: isFirstRow ? FontWeight.w600 : FontWeight.normal,
                          decoration: script.isEnabled ? null : TextDecoration.lineThrough,
                          height: 1.25,
                        ),
                        maxLines: item.key.contains('网址') ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 第一行右上角展示清晰纯文本数字序号 (完全契合用户参考图)
                    if (isFirstRow)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: script.isEnabled ? Colors.white : Colors.white38,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),

            // Status Line (正在执行状态，进度条)
            if (scriptProvider.isExecuting &&
                script.status != ScriptStatus.idle) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  _getStatusIcon(script.status),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStatusText(script),
                          style: TextStyle(
                            color: _getStatusColor(script.status),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (script.progress != null &&
                            script.progress! >= 0 &&
                            script.progress! <= 1.0) ...[
                          const SizedBox(height: 2),
                          LinearProgressIndicator(
                            value: script.progress,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                _getStatusColor(script.status)),
                            minHeight: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],

            // 分割线：脚本与脚本之间
            if (index < scriptProvider.scripts.length - 1)
              const Divider(color: Colors.white12, height: 8, thickness: 0.7),
          ],
        ),
      ),
    );
  }

  void _showScriptContextMenu(
      BuildContext context, ScriptProvider scriptProvider, int index) {
    final script = scriptProvider.scripts[index];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 禁用/启用
              ListTile(
                leading: Icon(
                  script.isEnabled ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white,
                ),
                title: Text(
                  script.isEnabled ? '禁用' : '启用',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  scriptProvider.toggleScriptEnabled(index, !script.isEnabled);
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 复制
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white),
                title: const Text('复制', style: TextStyle(color: Colors.white)),
                onTap: () {
                  final copied = scriptProvider.duplicateScript(index);
                  if (copied != null) {
                    scriptProvider.addScript(copied);
                  }
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 在前粘贴脚本
              ListTile(
                leading: const Icon(Icons.content_paste, color: Colors.white),
                title:
                    const Text('在前粘贴脚本', style: TextStyle(color: Colors.white)),
                onTap: () {
                  final copied = scriptProvider.duplicateScript(index);
                  if (copied != null) {
                    scriptProvider.insertScript(index, copied);
                  }
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 删除
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  scriptProvider.removeScript(index);
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24, height: 1),

              // 在前插入新脚本
              ListTile(
                leading:
                    const Icon(Icons.add_circle_outline, color: Colors.white),
                title: const Text('在前插入新脚本',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);

                  // Show index info on screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('准备在位置 $index 插入 (序号${index + 1}之前)'),
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  final result = await showDialog<Script>(
                    context: context,
                    builder: (context) => const AddScriptDialog(),
                  );
                  if (result != null) {
                    scriptProvider.insertScript(index, result);

                    // Show result
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '已插入到位置 $index，现在共${scriptProvider.scripts.length}个脚本'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExecutingActions(ScriptProvider scriptProvider) {
    return Row(
      children: [
        // Pause/Resume button
        Expanded(
          child: InkWell(
            onTap: () {
              if (scriptProvider.isPaused) {
                scriptProvider.resumeExecution();
              } else {
                scriptProvider.pauseExecution();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(
                scriptProvider.isPaused ? Icons.play_arrow : Icons.pause,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Stop button
        Expanded(
          child: InkWell(
            onTap: () => scriptProvider.stopExecution(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: const Text(
                '停止',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Counts display
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '失败${scriptProvider.failureCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '成功${scriptProvider.successCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdleActions(
      BuildContext context, ScriptProvider scriptProvider) {
    return Row(
      children: [
        // Execute button
        Expanded(
          child: InkWell(
            onTap: scriptProvider.isRecording ? null : onExecute,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '执行',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      scriptProvider.isRecording ? Colors.grey : Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Load button
        Expanded(
          child: InkWell(
            onTap: () {
              _handleLoadScript(context, scriptProvider);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: const Text(
                '读取',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(width: 1, color: Colors.white),
        // Menu button (3 dots)
        Expanded(
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
            color: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onSelected: (value) async {
              if (value == 'share') {
                _showShareDialog(context, scriptProvider);
              } else if (value == 'clear') {
                scriptProvider.clearScripts();
              } else if (value == 'save') {
                _showSaveDialog(context, scriptProvider);
              } else if (value == 'guide') {
                try {
                  final content = await rootBundle.loadString('assets/guide.html');
                  if (context.mounted) {
                    final tab = Provider.of<BrowserProvider>(context, listen: false).currentTab;
                    await tab?.controller?.loadData(
                        data: content,
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                        baseUrl: WebUri('file:///guide.html'));
                  }
                } catch (e) {
                  debugPrint('Load guide.html failed: $e');
                }
              } else if (value == 'test_page') {
                try {
                  final content = await rootBundle.loadString('assets/test_page.html');
                  if (context.mounted) {
                    final tab = Provider.of<BrowserProvider>(context, listen: false).currentTab;
                    await tab?.controller?.loadData(
                        data: content,
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                        baseUrl: WebUri('file:///test_page.html'));
                  }
                } catch (e) {
                  debugPrint('Load test_page.html failed: $e');
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'guide',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: Colors.lightBlueAccent, size: 18),
                    SizedBox(width: 8),
                    Text('使用教程', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test_page',
                child: Row(
                  children: [
                    Icon(Icons.science_outlined, color: Colors.amberAccent, size: 18),
                    SizedBox(width: 8),
                    Text('测试网页', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(
                value: 'share',
                child: Text('分享', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('清空', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'save',
                child: Text('保存', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getScriptContent(Script script) {
    final params = script.params;
    switch (script.type) {
      case '点击文字':
        final filter = params['多个筛选'];
        String filterStr = '';
        if (filter != null) {
          if (filter == 0) {
            filterStr = ' [随机]';
          } else if (filter < 0) {
            filterStr = ' [倒数第${-filter}个]';
          } else {
            filterStr = ' [第$filter个]';
          }
        }
        return '点击: ${params['点击文本'] ?? ''}$filterStr';
      case '点击图片':
        final imgFilter = params['多个筛选'];
        String imgFilterStr = '';
        if (imgFilter != null) {
          if (imgFilter == 0) {
            imgFilterStr = ' [随机]';
          } else if (imgFilter < 0) {
            imgFilterStr = ' [倒数第${-imgFilter}个]';
          } else {
            imgFilterStr = ' [第$imgFilter个]';
          }
        }
        return '点击图片$imgFilterStr';
      case '输入框提交':
        final List<String> parts = [];
        if (params['提交按钮文字'] != null &&
            params['提交按钮文字'].toString().isNotEmpty) {
          parts.add('提交: ${params['提交按钮文字']}');
        }
        final formData = params['表单数据'];
        if (formData is Map && formData.isNotEmpty) {
          parts.addAll(formData.entries.map((e) => '${e.key}: ${e.value}'));
        }
        return parts.join('\n');
      case '进入网址':
        return '网址: ${params['网址'] ?? ''}';
      case '间隔时间':
        final h = params['时间间隔-小时'] ?? 0;
        final m = params['时间间隔-分钟'] ?? 0;
        final s = params['时间间隔-秒'] ?? 0;
        return '等待: $h时$m分$s秒';
      case '跳转脚本':
        return '跳转到: ${params['跳转标签'] ?? ''}';
      case '延时脚本':
        return '延时: ${params['延时时间'] ?? 0}ms';
      case '逻辑脚本-出现文字':
        return '检测: ${params['出现文字'] ?? ''}';
      case '刷新网页':
        return '刷新当前页面';
      case '网页后退':
        return '后退';
      case '网页前进':
        return '前进';
      case '脚本停止':
        return '停止运行';
      case '脚本暂停':
        return '暂停运行';
      case '自定义JS':
        final path = params['jsFilePath']?.toString();
        if (path != null && path.isNotEmpty) {
          final filename = path.split(RegExp(r'[\\/]')).last;
          return '文件: $filename';
        }
        final code = (params['代码'] ?? params['js内容'] ?? '').toString().trim();
        if (code.isNotEmpty) {
          final firstLine = code.split('\n').first.trim();
          return firstLine.length > 25 ? '${firstLine.substring(0, 25)}...' : firstLine;
        }
        return 'JS代码块';
      default:
        if (params.containsKey('执行延迟')) {
          return '延迟: ${params['执行延迟']}ms';
        }
        return '';
    }
  }

  Widget _getStatusIcon(ScriptStatus status) {
    switch (status) {
      case ScriptStatus.success:
        return const Icon(Icons.check, color: Colors.green, size: 12);
      case ScriptStatus.failure:
        return const Icon(Icons.close, color: Colors.red, size: 12);
      case ScriptStatus.waiting:
        return const Icon(Icons.access_time, color: Colors.orange, size: 12);
      case ScriptStatus.running:
        return const Icon(Icons.arrow_forward, color: Colors.blue, size: 12);
      default:
        return const SizedBox.shrink();
    }
  }

  Color _getStatusColor(ScriptStatus status) {
    switch (status) {
      case ScriptStatus.success:
        return Colors.green;
      case ScriptStatus.failure:
        return Colors.red;
      case ScriptStatus.waiting:
        return Colors.orange;
      case ScriptStatus.running:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(Script script) {
    if (script.statusMessage != null) {
      return script.statusMessage!;
    }
    switch (script.status) {
      case ScriptStatus.success:
        return '成功';
      case ScriptStatus.failure:
        return '失败';
      case ScriptStatus.waiting:
        return '等待中';
      case ScriptStatus.running:
        return '执行中';
      default:
        return '';
    }
  }

  Future<void> _handleSaveScript(
      BuildContext context, ScriptProvider scriptProvider) async {
    try {
      final String? existingFilePath = scriptProvider.currentScriptFilePath;
      String filePath;

      if (existingFilePath == null || existingFilePath.isEmpty) {
        // First-time save: ask for filename and use default directory
        final String defaultDir = await FileManager.getScriptDirectory();

        if (!context.mounted) return;

        // Show filename input dialog
        final TextEditingController filenameController = TextEditingController(
          text: 'script_${DateTime.now().millisecondsSinceEpoch}',
        );

        final filename = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            title: const Text('输入文件名', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: filenameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '脚本名称',
                hintStyle: TextStyle(color: Colors.white54),
                suffixText: '.json',
                suffixStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消', style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, filenameController.text);
                },
                child: const Text('保存', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );

        if (filename == null || filename.isEmpty) return;

        // Create full file path in default directory
        filePath = path.join(defaultDir, '$filename.json');
      } else {
        // Overwrite existing file
        filePath = existingFilePath;
      }

      // Get script content and save
      final scriptContent = scriptProvider.exportScript();
      final file = File(filePath);
      await file.writeAsString(scriptContent);

      // Update file path in provider
      scriptProvider.updateScriptFilePath(filePath);

      // Show success message
      if (context.mounted) {
        final String message = existingFilePath == null
            ? '脚本已保存到: Auok/脚本/${path.basename(filePath)}'
            : '脚本已更新';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleShareScript(
      BuildContext context, ScriptProvider scriptProvider) async {
    try {
      final String? filePath = scriptProvider.currentScriptFilePath;

      // Check if script is saved
      if (filePath == null ||
          filePath.isEmpty ||
          !await FileManager.fileExists(filePath)) {
        // Show warning: file not saved
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('你还没有保存文件，请先保存'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Share the saved file
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: '脚本分享',
        text: '这是我的浏览器自动化脚本',
      );

      if (context.mounted && result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('分享成功'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分享失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleLoadScript(
      BuildContext context, ScriptProvider scriptProvider) async {
    try {
      final savedScripts = await FileManager.getSavedScripts();

      if (!context.mounted) return;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              title: const Text('选择脚本', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: savedScripts.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无保存的脚本',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: savedScripts.length,
                        itemBuilder: (context, index) {
                          final file = savedScripts[index];
                          final fileName = path.basename(file.path);
                          return ListTile(
                            title: Text(
                              fileName,
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                await FileManager.deleteFile(file.path);
                                setState(() {
                                  savedScripts.removeAt(index);
                                });
                              },
                            ),
                            onTap: () {
                              Navigator.pop(context, file.path);
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, 'import_external');
                  },
                  child: const Text('从外部文件导入...', style: TextStyle(color: Colors.blue)),
                ),
              ],
            );
          },
        ),
      ).then((result) async {
        if (result == null) return;
        
        String? filePath;

        if (result == 'import_external') {
          // Get default script directory
          final String defaultDir = await FileManager.getScriptDirectory();

          // Let user pick a JSON file
          // Note: initialDirectory is not supported on Android, so we only use it on iOS
          FilePickerResult? pickResult = await FilePicker.platform.pickFiles(
            dialogTitle: '选择脚本文件',
            type: FileType.any,
            initialDirectory: Platform.isIOS ? defaultDir : null,
          );

          if (pickResult == null || pickResult.files.single.path == null) return;
          filePath = pickResult.files.single.path!;
        } else {
          filePath = result as String;
        }

        if (!filePath.toLowerCase().endsWith('.json')) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请选择 .json 格式的脚本文件'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        final file = File(filePath);
        final content = await file.readAsString();

        // Import script
        scriptProvider.importScript(content);

        // Update file path for this tab
        scriptProvider.updateScriptFilePath(filePath);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已加载: ${path.basename(filePath)}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('读取失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context, ScriptProvider scriptProvider) {
    _handleShareScript(context, scriptProvider);
  }

  void _showSaveDialog(BuildContext context, ScriptProvider scriptProvider) {
    _handleSaveScript(context, scriptProvider);
  }
}

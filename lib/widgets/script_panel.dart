import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../providers/browser_provider.dart';

class ScriptPanel extends StatelessWidget {
  final VoidCallback onClose;

  const ScriptPanel({super.key, required this.onClose});

  void _showImportDialog(
      BuildContext context, ScriptProvider scriptProvider, bool isDark) {
    final TextEditingController controller = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导入脚本'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            const Text('粘贴脚本内容：'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: controller,
              placeholder: '粘贴脚本...',
              maxLines: 10,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('导入'),
            onPressed: () {
              scriptProvider.importScript(controller.text);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showExportDialog(
      BuildContext context, ScriptProvider scriptProvider, bool isDark) {
    final exported = scriptProvider.exportScript();

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导出脚本'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            const Text('复制以下内容：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? CupertinoColors.darkBackgroundGray
                    : CupertinoColors.lightBackgroundGray,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                exported,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('复制'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: exported));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scriptProvider = context.watch<ScriptProvider>();
    final browserProvider = context.read<BrowserProvider>();
    final isDark = context.watch<BrowserProvider>().isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? CupertinoColors.black : CupertinoColors.white,
        border: const Border(
          top: BorderSide(color: CupertinoColors.separator),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: CupertinoColors.separator)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Scripts',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black)),
                Row(
                  children: [
                    // Recording control
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        scriptProvider.isRecording
                            ? CupertinoIcons.stop_circle_fill
                            : CupertinoIcons.circle,
                        color: scriptProvider.isRecording
                            ? CupertinoColors.systemRed
                            : (isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black),
                      ),
                      onPressed: () {
                        if (scriptProvider.isRecording) {
                          scriptProvider.stopRecording();
                        } else {
                          scriptProvider.startRecording();
                        }
                      },
                    ),
                    if (scriptProvider.isExecuting)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Icon(
                          CupertinoIcons.pause,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                        onPressed: () => scriptProvider.pauseExecution(),
                      )
                    else
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Icon(
                          CupertinoIcons.play,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                        ),
                        onPressed: () {
                          if (browserProvider.currentTab != null &&
                              browserProvider.currentTab!.controller != null) {
                            scriptProvider.startExecution(
                                browserProvider.currentTab!.controller!);
                          }
                        },
                      ),
                    // Import/Export buttons
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        CupertinoIcons.arrow_down_doc,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                      onPressed: () =>
                          _showImportDialog(context, scriptProvider, isDark),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        CupertinoIcons.arrow_up_doc,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                      onPressed: () =>
                          _showExportDialog(context, scriptProvider, isDark),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        CupertinoIcons.trash,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                      onPressed: () => scriptProvider.clearScripts(),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onClose,
                      child: Icon(
                        CupertinoIcons.down_arrow,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Script List
          Expanded(
            child: ListView.builder(
              itemCount: scriptProvider.scripts.length,
              itemBuilder: (context, index) {
                final script = scriptProvider.scripts[index];
                final isCurrent = scriptProvider.isExecuting &&
                    scriptProvider.currentScriptIndex == index;

                return Container(
                  color: isCurrent
                      ? CupertinoColors.activeBlue.withOpacity(0.1)
                      : null,
                  child: ListTile(
                    leading: Icon(
                      script.type == '点击文字'
                          ? CupertinoIcons.hand_point_right
                          : CupertinoIcons.text_cursor,
                      color: isCurrent
                          ? CupertinoColors.activeBlue
                          : (isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemGrey2),
                    ),
                    title: Text(
                      script.type,
                      style: TextStyle(
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      ),
                    ),
                    subtitle: Text(
                      script.params.toString(),
                      style: TextStyle(
                        color: isDark
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.systemGrey2,
                      ),
                    ),
                    trailing: CupertinoSwitch(
                      value: script.isEnabled,
                      onChanged: (value) =>
                          scriptProvider.toggleScriptEnabled(index, value),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

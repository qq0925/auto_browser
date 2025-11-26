import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/script_provider.dart';
import '../providers/browser_provider.dart';

class ScriptPanel extends StatelessWidget {
  final VoidCallback onClose;

  const ScriptPanel({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scriptProvider = context.watch<ScriptProvider>();
    final browserProvider = context.read<BrowserProvider>();

    return Container(
      color: CupertinoColors.systemBackground,
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
                const Text('Scripts',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    if (scriptProvider.isExecuting)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(CupertinoIcons.pause),
                        onPressed: () => scriptProvider.pauseExecution(),
                      )
                    else
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(CupertinoIcons.play),
                        onPressed: () {
                          if (browserProvider.currentTab != null) {
                            scriptProvider.startExecution(
                                browserProvider.currentTab!.controller);
                          }
                        },
                      ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Icon(CupertinoIcons.trash),
                      onPressed: () => scriptProvider.clearScripts(),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onClose,
                      child: const Icon(CupertinoIcons.down_arrow),
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
                          : CupertinoColors.systemGrey,
                    ),
                    title: Text(script.type),
                    subtitle: Text(script.params.toString()),
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

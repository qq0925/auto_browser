# 重构实施计划

## 目标
将单体 `lib/main.dart` 拆分为模块化结构，提高代码的可读性、可维护性和可扩展性。

## 用户审查要求
> [!IMPORTANT]
> 这是一个纯重构任务，旨在重新组织代码结构，不应改变现有的功能逻辑。

## 拟议变更

### 1. 创建目录结构
- `lib/models/`
- `lib/screens/`
- `lib/utils/`

### 2. 提取模型 (Models)
将数据类从 `main.dart` 移动到独立文件。

#### [NEW] [script.dart](file:///e:/auto_browser/auto_browser/lib/models/script.dart)
- 包含 `Script` 类
- 包含 `ScriptMode` 枚举
- 包含 `TimeUnit` 枚举

#### [NEW] [browser_tab.dart](file:///e:/auto_browser/auto_browser/lib/models/browser_tab.dart)
- 包含 `BrowserTab` 类

#### [NEW] [browser_data.dart](file:///e:/auto_browser/auto_browser/lib/models/browser_data.dart)
- 包含 `Bookmark` 类
- 包含 `HistoryItem` 类

### 3. 提取页面 (Screens)
将主页面逻辑移动到独立文件。

#### [NEW] [home_screen.dart](file:///e:/auto_browser/auto_browser/lib/screens/home_screen.dart)
- 包含 `BrowserHomePage` 和 `_BrowserHomePageState` 类
- 需要导入上述模型文件

### 4. 清理入口文件
简化 `main.dart`。

#### [MODIFY] [main.dart](file:///e:/auto_browser/auto_browser/lib/main.dart)
- 保留 `main()` 函数和 `MyApp` 类
- 导入 `lib/screens/home_screen.dart`
- 保留 `main()` 函数和 `MyApp` 类
- 导入 `lib/screens/home_screen.dart`
- 移除所有已提取的类定义
- **[FIX]** 移除 `main()` 中的阻塞性权限请求，移动到 `BrowserHomePage` 的 `initState` 中处理。

### 5. 修复配置 (Configuration)

#### [MODIFY] [pubspec.yaml](file:///e:/auto_browser/auto_browser/pubspec.yaml)
- 移除 `dependency_overrides`，允许 `webview_flutter` 使用兼容的依赖版本。

## 验证计划

### 自动化测试
- 运行 `flutter test` (如果现有测试存在) - *目前似乎没有针对这些UI组件的单元测试*
- 运行 `flutter analyze` 确保没有导入错误或语法错误。

### 手动验证
1.  **启动应用**：确保应用能正常启动，无崩溃。
2.  **基本浏览**：打开网页，新建标签页，切换标签页。
3.  **脚本功能**：
    -   录制一个简单的点击脚本。
    -   保存并执行脚本，验证是否正常工作。
4.  **持久化**：重启应用，检查历史记录和书签是否保留。

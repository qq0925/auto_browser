# Auok 浏览器 App Store 提审与过审完整指引手册

本文档为 **Auok 浏览器** 提交 Apple App Store 官方审核提供全套合规配置、元数据模板、审核员测试指引以及防拒审应对方案。

---

## 一、App Store Connect 基础信息配置

### 1. App 分类（Category）
- **主要类别：** 效率（Productivity）
- **次要类别：** 工具（Utilities）
> **注意：** 切勿选择“游戏”或“娱乐”，坚决定位于生产力/测试辅助工具。

### 2. 年龄分级（Age Rating）——【核心红线】
在分级问卷中，必须按照以下选择：
- **未受限制的 Web 访问（Unrestricted Web Access）：** **【必须选：是】**
- 赌博与竞赛：否
- 令人反感的内容/暴力/成人内容：否
- **最终评级结果：** **17+**
> **原因：** 苹果规定所有包含自由输入 URL 浏览互联网的通用浏览器必须标为 17+。若选“否”，审核员在地址栏输入任意网站即可直接驳回。

### 3. 隐私政策网址（Privacy Policy URL）
- 必须提供一个公网可访问的 HTTPS 网页链接。
- **推荐做法：** 将本项目中的 `assets/privacy_policy.html` 部署至您的官网，或通过 GitHub Pages、Cloudflare Pages、Vercel 免费托管，链接格式如：
  `https://your-domain.com/privacy_policy.html`

---

## 二、商店元数据推荐（文案脱敏合规）

### 1. App 推广名称与副标题
- **名称：** Auok浏览器 - 自动化与效率工具
- **副标题：** 支持脚本自动化与多标签高效浏览

### 2. 关键词（Keywords）
```text
浏览器,自动化测试,网页脚本,效率工具,开发者浏览器,多标签,Cookie管理,JS脚本,无障碍辅助,自动点击
```

### 3. App 描述（Description）
```text
Auok 浏览器是一款专为开发者、自动化测试工程师及追求极致效率的用户打造的现代 Web 浏览器。

【核心功能亮点】
• 智能网页自动化引擎：内置轻量级流程自动化工具，支持点击、文本填充、数值比对与条件等待，让重复的网页流程一触即达。
• 原生 WebKit 内核保障：基于 iOS 官方 WebKit 引擎深度优化，带来毫秒级响应、极致流畅与电池低消耗。
• 隐私与本地数据沙盒：坚持本地沙盒存储原则，Cookie 隔离存档、书签历史及脚本配置完全存储在您的本地设备中，不设云端收集，保障隐私安全。
• 开发者辅助与富交互测试：提供可视化脚本编辑器与精准的 DOM / HTML5 Canvas 节点探测能力，满足前端开发与自动化巡检需求。
• 多标签与沉浸浏览：独立窗口标签页切换、夜间模式、自定义 UA 标识与广告过滤拦截，打造高自由度的浏览环境。
```

---

## 三、App 审核信息（App Review Information）——【写给审核员】

在 App Store Connect 的 **“审核备注 (Notes)”** 栏中，请直接复制以下中英文对照说明：

```text
Dear Apple App Review Team,

Auok Browser is a productivity and developer-oriented web browser built entirely on Apple's official WebKit (WKWebView) framework. It provides general web browsing alongside local automation testing capabilities (similar to Safari Web Extensions and Shortcuts).

[Demo & Testing Instructions]
1. Launch the app. The browser opens with a clean navigation interface.
2. Tap the address bar and navigate to the built-in testing page by typing: about:test (or test_page.html).
3. Tap the script manager button on the right edge of the screen to open the Script Automation Panel.
4. You will see preset testing steps (e.g., Click, Form Submit, Value Check).
5. Tap "Run / 执行" button. The engine will automatically demonstrate form inputs and element interactions step-by-step.
6. Open Settings dialog from the top-right menu to view our full Privacy Policy and Terms of Service (also accessible at about:privacy).

All user data, cookies, and local scripts are securely stored inside the app's local sandbox and are never uploaded to any remote server.

Thank you for your time and assistance!

---
尊敬的苹果审核团队：

Auok 浏览器是一款面向生产力与开发者的效率工具浏览器，基于 iOS 原生 WebKit (WKWebView) 引擎构建。应用提供通用网页浏览与本地流程自动化辅助功能（类似于 Safari 网页扩展与快捷指令应用）。

【审核测试步骤指引】
1. 启动应用，进入标准浏览器主界面；
2. 在地址栏输入 about:test（或 test_page.html）打开内置的自动化测试演示页面；
3. 点击屏幕右侧的悬浮展开按钮，调出“脚本管理器”面板；
4. 面板中已预置标准的测试流程步骤（包括文字点击、表单提交与数值比对）；
5. 点击“执行”按钮，即可观察自动化引擎逐步完成表单输入与元素互动的测试流程；
6. 点击右上角菜单进入“设置”，可查看完整的《隐私政策》与《用户服务协议》（亦可在地址栏输入 about:privacy 浏览）。

本应用遵循本地沙盒原则，所有 Cookie 存档与脚本均只存储在本机设备中，不设外部收集服务器。感谢审核团队的辛劳审核！
```

---

## 四、苹果常见审核条款应对（Appeal Strategy）

### 1. 若审核员质疑 Guideline 2.5.2（动态可执行代码）：
- **答辩依据：**
  > 根据 Guideline 2.5.2 的官方豁免条款：“*Exceptions are made for scripts and code that are interpreted by WebKit and run in a web view...*”。Auok 浏览器的自动化脚本仅在官方 WebKit 容器（WKWebView）的沙盒内部解释执行，不下载任何原生二进制机器码，不调用任何私有 API，完全符合 2.5.2 的豁免准则。

### 2. 若审核员质疑 Guideline 4.2（最低功能性/怀疑是套壳）：
- **答辩依据：**
  > Auok 并非简单的 Web 打包应用（Web wrapper），而是具备完整的本地原生功能：多标签并发管理系统、本地 Cookie 会话沙盒存档、自定义用户代理（UA）切换、夜间模式、书签历史管理、本地可视化的动作录制与脚本调度引擎。

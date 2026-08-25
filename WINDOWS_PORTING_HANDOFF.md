# Battuta Windows 移植交接文档

> 这份文档用于交给 Windows 电脑上的开发者或 Codex。目标是在不破坏现有 macOS 版本的前提下，制作一个视觉与功能高度一致的 Battuta Windows 版。

## 1. 开始前先确认

### 正确的源码基线

- 当前 Git 远端为：`https://github.com/7b7b7b/battuta.git`
- 必须从远端最新 `main` 开始，不要从旧的 `v0.3.2` Release 标签开始移植。
- 本文编写时，核心源码基线是 commit `cce3b87`；Windows clone 后应确认位于该 commit 或其更新版本。
- 当前源码工程的产品版本为 Battuta `1.1.1`，build `26`。
- Windows 代码应放在独立目录中，默认不要改写或删除 `SimuBoardMac/`。

注意：本文编写时，本机的 `Promo/`、`website/`、`wormforce-integration/` 仍是未跟踪的本地目录，不会自动出现在普通 Git clone 中。若 Windows 端需要其中的宣传截图、视频或网页，必须先单独提交并 push，或手工传到 Windows。不要把本地未提交资源误认为远端仓库内容。

建议在 Windows PowerShell 中执行：

```powershell
git clone https://github.com/7b7b7b/battuta.git
cd battuta
git switch -c codex/windows-port origin/main
git log -1 --oneline
git status
```

如果只是查看公开仓库，不需要 GitHub 登录；如果要 push，需要提前在 Windows 上配置 GitHub 凭据或 SSH Key。

### 仓库之外还需要什么

必须准备：

1. 一台 Windows 10/11 测试环境。可以先用虚拟机，但发布前至少要在一台真实 Windows x64 电脑上验证键盘 Hook、音频延迟、休眠唤醒和声卡切换。
2. Visual Studio，并安装“.NET 桌面开发”工作负载。
3. .NET 10 SDK（LTS）。
4. 一套当前 macOS 版的视觉与交互参考。仓库已有截图和视频，路径见本文后面的“视觉参考”；如果某个交互仍不清楚，再补录短视频。
5. 至少两种键盘、一只普通鼠标，以及有线扬声器或耳机。蓝牙音频只能作为兼容性测试，不能作为低延迟基准。

可选准备：

- Windows 11 ARM 设备，用于后续 ARM64 测试；第一版可以只发布 x64。
- 一台高 DPI/4K 显示器，以及一台 1366×768 或 1920×1080 普通显示器。
- FFmpeg，仅作为用户导入某些音频格式失败时的兜底；按键播放热路径不得依赖 FFmpeg。

## 2. 产品目标

Battuta 是一个常驻系统托盘的键鼠音效应用。用户在任意桌面应用中输入时，它根据物理按键与按下/抬起阶段，播放预载到内存中的短音频；应用不读取或保存用户输入的字符内容。

Windows 版目标：

- 保留 Battuta 的品牌、深色与荧光绿色视觉、卡片结构、键盘图和数据展示方式。
- 在 Windows 的任意普通桌面应用中监听键盘与鼠标按下/抬起。
- 保持与 macOS 版相近的主观音频延迟，不出现第一次按键明显更慢的问题。
- 兼容现有内置音频、音色映射、自然变化规则、DIY 规则和统计定义。
- Windows 与 macOS 分别使用原生系统集成，不强求共用 UI 源码。
- 不因移植而降低隐私标准，不记录字符、密码、剪贴板或鼠标位置。

“视觉几乎一样”指品牌、信息层级、尺寸比例和交互流程高度一致；Windows 字体渲染、窗口阴影、托盘位置和系统对话框允许遵循 Windows 行为。不要在 Windows 分发 Apple SF Symbols 或未经许可的 SF Pro 字体。

## 3. 当前产品范围

现有 macOS 端约有：

- 15,818 行 Swift 产品代码。
- 3,117 行核心测试 Harness。
- 21 种键盘/轴体音色；其中 BCP (Suit80) 以只读 `.simuboardpack` 形式内置。
- 5 种鼠标与触控板点击风格。
- 265 段按下/抬起录音（`Audio/` 237 段，加内置 BCP 包 28 段）。
- 系统级键鼠监听、音量调节、自然音色轮换、登录启动。
- 本地输入统计、逐键热力图、七日趋势和年度热力图。
- DIY 音色编辑器、逐键映射、导入转换、完整击键自动拆音、音色包导入导出。
- GitHub Release 检查、签名验证与 Sparkle 自动更新。

第一版 Windows 不应试图一次性搬完所有功能。先完成可靠的核心音效 MVP，再依次迁移统计、DIY 和正式发布链路。

## 4. 必读文件

Windows 开发者或 Codex 在写代码前，应完整阅读以下文件：

| 文件 | 用途 |
|---|---|
| `README.md` | 产品总览、隐私边界、两种现有版本的关系 |
| `SimuBoardMac/README.md` | macOS 版完整功能、音频策略、更新与发布行为 |
| `SimuBoardMac/SOUND_PACK_FORMAT.md` | DIY 音色包结构、映射优先级和安全限制 |
| `SimuBoardMac/AUDIO_SOURCES.md` | 音频来源、处理方式和许可 |
| `LICENSE` | 本项目许可证 |
| `THIRD_PARTY_NOTICES.md` | 第三方素材与许可证 |
| `design-qa.md` | 统计窗口的尺寸、窄屏规则和视觉验证记录 |
| `SimuBoardMac/SimuBoardMac/Views/BattutaVisualStyle.swift` | 颜色、圆角、阴影、字体尺度和通用视觉组件 |
| `SimuBoardMac/SimuBoardMac/Views/MenuBarView.swift` | 托盘弹出面板的信息结构和交互 |
| `SimuBoardMac/SimuBoardMac/Views/SoundPackEditorView.swift` | DIY 编辑器主要布局与交互 |
| `SimuBoardMac/SimuBoardMac/Views/TypingStatsView.swift` | 统计主窗口结构 |
| `SimuBoardMac/SimuBoardMac/Models/KeyboardLayout.swift` | 现有键盘区域、行与按键定义 |
| `SimuBoardMac/SimuBoardMac/Models/KeySound.swift` | R0–R4、特殊键和通用音频映射 |
| `SimuBoardMac/SimuBoardMac/Models/SwitchProfile.swift` | 20 种键盘音色元数据与资源规则 |
| `SimuBoardMac/SimuBoardMac/Models/PointerSound.swift` | 5 种鼠标点击音与 down/up 规则 |
| `SimuBoardMac/SimuBoardMac/Models/AppSettings.swift` | 设置默认值、持久化键和迁移行为 |
| `SimuBoardMac/SimuBoardMac/Models/SoundPack.swift` | 音色包数据模型、校验限制与编码 |
| `SimuBoardMac/SimuBoardMac/Models/TypingStats.swift` | 统计模型与“字符键”允许列表 |
| `SimuBoardMac/SimuBoardMac/Services/KeyboardMonitor.swift` | macOS 当前键鼠事件语义，仅作为行为参考 |
| `SimuBoardMac/SimuBoardMac/Services/KeyboardAudioEngine.swift` | 音频预热、PCM 转换、voice pool 和播放规则 |
| `SimuBoardMac/SimuBoardMac/Services/AppModel.swift` | 输入事件到音效、统计和设置的总路由 |
| `SimuBoardMac/SimuBoardMac/Services/TypingStatsStore.swift` | SQLite schema、迁移和统计查询 |
| `SimuBoardMac/SimuBoardMac/Services/AudioSplitService.swift` | 自动拆分完整击键录音的算法 |
| `SimuBoardMac/Tests/` | 行为边界和回归测试的事实来源 |

不要只看 SwiftUI 截图然后猜业务规则。遇到不确定行为时，先查模型、服务和测试。

## 5. 视觉参考

Git 已跟踪、普通 clone 可获得：

- `SimuBoardMac/Design/AppIconSource.png`
- `SimuBoardMac/Design/AppIconSquare.png`
- `SimuBoardMac/Design/AppIconPrompt.md`
- 所有 SwiftUI 界面源码与 `design-qa.md`

本机当前存在、但在本文编写时尚未进入 Git 的补充参考：

- `website/public/media/battuta-diy-editor.png`
- `website/public/media/battuta-sound-demo-polished.mp4`
- `website/public/media/battuta-stats-demo-polished-v2.mp4`
- `website/public/media/battuta-sound-poster.jpg`
- `website/public/media/battuta-stats-poster.jpg`
- `website/public/battuta-icon.png`
- `Promo/battuta-info-card-16x9.png`

Windows 端只有在这些本地目录已经提交/push 或被单独传输后，才能看到它们。其中宣传卡只用于理解品牌，不是应用窗口的像素级设计稿。真正实现时，以 macOS SwiftUI 视图、DIY 编辑器截图和演示视频为准。

如果 Windows 开发者无法运行 macOS 版，建议额外提供以下短录屏：

1. 点击菜单栏图标并完整操作托盘面板。
2. 切换键盘音色、鼠标音色、音量、回弹音和自然变化。
3. 打开统计窗口并切换所有页面。
4. 打开 DIY 编辑器，导入音频、试听、保存并启用。
5. 自动拆分完整击键录音的全过程。

## 6. 推荐 Windows 技术栈

首选方案：`.NET 10 + WPF`。

| 能力 | 推荐实现 |
|---|---|
| UI | WPF/XAML，自定义 `ControlTemplate` 和无边框窗口 |
| 状态管理 | C# ViewModel；保持单向状态更新，不把业务逻辑写进 XAML code-behind |
| 全局键盘/鼠标 | CsWin32 或手写 P/Invoke 调用 `SetWindowsHookEx`，使用 `WH_KEYBOARD_LL` 与 `WH_MOUSE_LL` |
| 音频 | NAudio + WASAPI；单个持续输出流、内存 PCM 混音、固定 voice pool |
| 托盘 | `System.Windows.Forms.NotifyIcon`，点击后显示 WPF popup window |
| 数据库 | `Microsoft.Data.Sqlite` |
| 图表与热力图 | 优先自绘 WPF Canvas/Shapes，以保证视觉一致；通用曲线图可评估成熟库 |
| 开机启动 | MSIX `StartupTask`；未打包开发版可使用当前用户启动项适配层 |
| 安装与更新 | 正式版优先签名 MSIX + `.appinstaller`；若采用传统 Setup，再评估 Velopack |
| 日志 | 本地滚动日志，默认不上传；日志中不得出现字符内容 |
| 测试 | xUnit/NUnit + 纯 C# Core 测试；Windows 集成能力另建 smoke tests |

不建议第一版使用 Electron。虽然 HTML/CSS 容易复刻 UI，但全部键鼠监听和可靠低延迟音频仍需原生层，应用体积和运行开销没有必要。

如果未来决定把 macOS 也重写为共享 C# UI，可以重新评估 Avalonia；当前阶段不要同时重写两个平台。

## 7. 建议目录结构

不要移动现有 `SimuBoardMac` 资源，以免破坏 Xcode 工程。建议新增：

```text
BattutaWindows/
├── BattutaWindows.sln
├── src/
│   ├── Battuta.Core/             # 不依赖 WPF/Win32 的纯业务逻辑
│   ├── Battuta.Windows/          # WPF UI 与 Windows 服务实现
│   └── Battuta.Packaging/        # 打包、版本与更新配置
├── tests/
│   ├── Battuta.Core.Tests/
│   └── Battuta.Windows.SmokeTests/
├── assets/
│   ├── sounds/                   # 从现有资源复制或在构建时同步
│   ├── icons/                    # Windows 合法可分发的 SVG/ICO
│   └── licenses/
└── docs/
```

建议让 `Battuta.Core` 包含：

- 中立的按键 ID 与键盘区域定义。
- 音色、音频阶段、轮换配方和解析优先级。
- DIY manifest、SHA-256、安全限制与校验。
- SemVer 与更新摘要解析。
- 统计事件、聚合逻辑和可测试的查询参数。

建议让 `Battuta.Windows` 包含：

- Win32 输入监听。
- WASAPI 音频输出与设备恢复。
- 托盘、窗口、文件选择器、通知和开机启动。
- 前台应用识别。
- Windows 文件路径与安装更新。

## 8. 最关键的跨平台设计：中立按键 ID

macOS 的 `CGKeyCode` 与 Windows 的 `vkCode`/scan code 不是同一套编号，不能把数字直接复制过去。

在写 UI 和数据库前，先定义稳定的跨平台 `PhysicalKeyId`，例如：

```text
KeyA, KeyB, Digit1, Space, Enter, Backspace,
LeftShift, RightShift, LeftControl, RightControl,
LeftAlt, RightAlt, LeftMeta, RightMeta, ArrowUp ...
```

Windows Hook 层应使用 scan code 与 extended flag 映射到 `PhysicalKeyId`。不要调用 `ToUnicode` 把事件转成字符，也不要保存键帽字符作为用户输入记录。

Windows 键盘 UI 可以保留当前的视觉结构，但标签应使用 `Win`、`Alt`、`Backspace`、`Enter` 等 Windows 名称。第一版建议支持常见 ANSI 布局；ISO、JIS、数字小键盘和特殊媒体键作为后续兼容项。

需要明确测试：

- 左右 Shift/Ctrl/Alt/Win 是否能区分。
- 主键区 Enter 与数字小键盘 Enter 是否能区分。
- 扩展方向键、Delete/Home/End/Page 键。
- 自动重复事件。
- 中文输入法、英文布局以及切换输入法时，物理映射是否稳定。
- 外接键盘、笔记本内置键盘和多键同时按下。

## 9. 输入监听要求

- Hook 回调必须非常短，只负责生成 `{physicalKeyId, phase, isRepeat, timestamp}` 或鼠标按钮事件，然后立即放入有界队列并返回。
- 不要在 Hook 回调中读取文件、解码音频、访问数据库、更新复杂 UI 或执行网络请求。
- 业务处理、统计写入和音频调度在独立线程/队列完成。
- 应有 Hook 健康检查和自动重新安装机制。
- 普通使用不应要求管理员权限。
- 不尝试监听 UAC 安全桌面；对以管理员权限运行的目标应用单独记录测试结果。
- 明确是否忽略合成/注入输入事件，并把决定写进测试；不要无意中改变现有用户体验。
- 鼠标只需要按钮 down/up，不记录坐标、移动、拖动或滚轮。

## 10. 音频实现要求

完整版音频的唯一事实来源是：

```text
SimuBoardMac/SimuBoardMac/Resources/Audio/
```

该目录包含 237 个资源、20 个键盘 profile 和 `pointer/` 下的 5 个点击 profile。根目录 `audio/` 只有旧浏览器原型的 151 个文件和 13 种音色，不能拿它作为 Windows 完整版资源源。

必须保留当前 macOS 版的核心性能策略：

1. 应用启动时预热音频输出。
2. 选择音色时把全部相关样本解码为 48 kHz PCM 并预载到内存。
3. 按键热路径只做内存查表、选择轮换配方、设置 gain/rate 和调度播放。
4. 使用一个持续存在的 WASAPI 输出流和软件混音器，不要每按一次键就创建或打开一个播放器。
5. 保留至少 16 个可重叠 voice 的能力，快速输入时不能互相截断。
6. 切换默认输出设备、插拔耳机、休眠唤醒后应自动恢复。
7. 内置 MP3/WAV 可在构建或加载阶段转换；任何转换都不能发生在按键回调中。
8. 保留键盘音量与鼠标音量两个独立设置。
9. 保留按下/回弹分别播放、可关闭回弹音、忽略按下自动重复的现有规则。
10. 保留四种轻微 gain/rate 配方均衡轮换，连续两次不使用同一配方；关闭自然变化时播放原音。

验收时至少测量或记录：

- 首次按键与后续按键是否同样及时。
- 连续快速输入 30 秒是否丢音、爆音或持续增加内存。
- 16 个快速重叠事件是否正常混音。
- 扬声器、3.5 mm/USB 耳机和蓝牙音频的行为差异。
- 默认声卡切换与设备断开后的恢复。
- CPU 空闲占用和常驻内存。

不要在没有测量前宣传具体毫秒数。优先保证“没有首次延迟、没有卡顿、主观不晚于 macOS 版”。

## 11. 音色与 DIY 包兼容

当前 `.simuboardpack` 在 macOS 上是一个 Finder package，本质是目录：

```text
Example.simuboardpack/
├── manifest.json
├── assets/
│   └── <sha256>.wav
└── licenses/
```

Windows 会把它显示为普通文件夹，直接作为跨平台分享格式体验不好。建议：

1. `schemaVersion: 1` 的 manifest 字段、映射优先级、哈希和安全上限保持兼容。
2. Windows 首版可以读取解压后的旧 `.simuboardpack` 目录，方便开发验证。
3. 正式跨平台分享格式改为 ZIP 容器，扩展名可继续讨论使用 `.simuboardpack` 还是新增 `.battutapack`。
4. 如果新增 ZIP 格式，后续应让 macOS 版同时支持目录包与 ZIP 包，不能让现有用户音色失效。
5. ZIP 导入必须防目录穿越、符号链接、超大文件、哈希不一致、重复条目和压缩炸弹。

不要先改 schema 再迁移 UI；先写跨平台格式测试和兼容样例。

## 12. 输入统计与隐私

统计只保存聚合所需的信息：

- 稳定的物理按键 ID。
- 按下时间。
- 是否自动重复、是否快捷键修饰。
- 当时的前台应用标识，用于应用维度统计。

当前统计口径需要原样理解后再迁移：

- 逐键热力图只累计非自动重复的物理 keyDown。
- “字符数”不是读取到的真实文本，而是允许列表内物理字符键的 keyDown 次数。
- 字符数包含自动重复产生的次数，但不累计 Command/Control 快捷键事件。
- Windows 需把 Command 语义对应到 Ctrl/Win 等实际快捷键规则，并为 AltGr、IME 写明确测试。
- 当前 SQLite schema 版本为 2，秒级明细保留 31 天，长期汇总继续保留；不要在移植时无意改变数据口径。

禁止保存：

- 转换后的字符或文本。
- 密码与输入框内容。
- 完整按键序列的文本还原。
- 鼠标坐标、窗口标题、剪贴板。
- 未经用户明确选择的遥测或上传。

Windows 前台应用可通过 Win32 窗口与进程 API 获得。不要读取窗口标题来推断用户内容。统计数据库默认放在当前用户的本地应用数据目录，并复用现有数据库安全和迁移测试的思想。

## 13. UI 迁移原则

- 先建立全局 design tokens：背景、卡片、边框、绿色强调色、圆角、间距、标题与正文层级。
- 不要在每个页面重复写硬编码颜色和圆角。
- 托盘面板、统计窗口、DIY 编辑器分别使用独立 WPF Window/View，不把整个应用塞进一个超大页面。
- 允许使用 Windows 原生文件选择器、安装提示和系统设置页面。
- 所有自定义控件必须支持 100%、125%、150%、200% DPI。
- 至少测试 1366×768、1920×1080 和 4K。
- 中文界面优先使用 `Segoe UI Variable`、`Microsoft YaHei UI` 等系统可用字体，不捆绑 Apple 字体。
- 用自有 SVG/Path 或 Windows Fluent 图标替换 SF Symbols，并更新第三方许可文件。
- 对比截图时优先检查信息层级、留白、组件比例、对齐与断行，不追求 macOS 与 Windows 字体像素完全相同。

## 14. 开发阶段与验收门槛

### Phase 0：工程与跨平台模型

- 新建 `BattutaWindows.sln`、Core、Windows UI 和测试工程。
- 导入合法可复用的音频与许可证。
- 定义 `PhysicalKeyId`、音色模型、设置模型和基础测试。
- 不改现有 macOS 行为。

完成标准：解决方案可在 Windows 干净环境 restore/build/test。

### Phase 1：核心音效 MVP

- 托盘图标与弹出面板。
- 全局键盘 down/up、修饰键和鼠标按钮监听。
- 全部内置键盘与鼠标音色。
- 音色切换、两个独立音量、回弹音、自然变化。
- 音频预热、内存预载、voice mixing、设备恢复。
- 当前用户登录启动。

完成标准：在浏览器、VS Code、微信/聊天软件、Word 类应用中连续输入均稳定；无首次明显延迟、无字符采集、无管理员要求。

### Phase 2：统计

- SQLite schema 与迁移。
- 今日输入量、峰值速度、应用分布、七日趋势、年度热力图和逐键热力图。
- Windows 前台应用识别。
- 与 macOS 语义一致的核心测试。

完成标准：重复键、快捷键、跨日、时区、数据库恢复和大数据量测试通过。

### Phase 3：DIY 编辑器

- 通用、R0–R4、特殊键和逐键映射。
- 音频导入、统一转换、试听与保存启用。
- 完整击键自动拆分与手动微调。
- 安全导入导出与跨平台音色包。

完成标准：现有测试样例和 Windows 新包均可往返，恶意包验证测试通过。

### Phase 4：公开发布

- x64 Release 构建、安装与卸载。
- 开机启动、更新、回滚和数据保留。
- Windows 10/11、多 DPI、多显示器、声卡切换和休眠唤醒测试。
- 代码签名、许可证、隐私说明和下载页面。
- 之后再评估 ARM64。

完成标准：普通用户从下载到启动不需要命令行，更新不丢设置、统计或 DIY 音色。

## 15. 测试迁移清单

优先把 `SimuBoardMac/Tests/` 中的平台无关规则翻译为 C# 单元测试：

- 音色映射优先级和继承/静音行为。
- manifest 编解码、SHA-256 与安全限制。
- 音频归一化后的格式、长度和边界。
- 自动拆音的建议切点和手动调整边界。
- SemVer 与更新版本比较。
- 自然变化的均衡轮换、无连续重复和关闭时原音。
- 输入统计的日期、时区、重复键和快捷键规则。
- SQLite 迁移与损坏恢复。

Windows 特有集成测试：

- Hook 安装、卸载、超时恢复和程序退出清理。
- scan code/extended flag 到 `PhysicalKeyId` 的固定样例。
- 音频设备断开、默认设备切换、休眠唤醒。
- 托盘多显示器定位与 DPI。
- 开机启动开关。
- 安装、覆盖更新、卸载保留/清除用户数据的选择。

## 16. 发布与签名

开发阶段可以使用未签名的 Debug/portable 构建，但只给受控测试者使用。

公开发布时：

- 继续通过 GitHub Release 分发是可行的，不强制使用 Microsoft Store。
- 未签名 EXE/安装包可能触发 SmartScreen，部分设备或企业策略可能直接阻止。
- 平滑安装应使用一致的可信代码签名身份，或者发布到 Microsoft Store 由商店签名。
- macOS 的 Sparkle 不能用于 Windows。若使用 MSIX，优先评估 `.appinstaller` 自动更新；若使用传统 Setup，再评估 Velopack。
- GitHub Release 中应使用明确的平台文件名，例如 `Battuta-Windows-x64-<version>.msix`，不要与 DMG、macOS `appcast.xml` 混淆。
- 私钥、证书密码、签名 token 和发布凭据不得进入仓库。
- 安装与更新必须保留用户设置、统计数据库和 DIY 音色。

正式发布前再决定：

1. Microsoft Store 还是产品页/GitHub 直接下载。
2. MSIX 还是传统 Setup。
3. 个人/组织代码签名方案。
4. Windows 版是否与 macOS 共用版本号。

这些决定不应阻塞 Phase 0 与 Phase 1。

## 17. 不要做的事情

- 不要试图在 Windows 上继续使用 SwiftUI、AppKit、AVFAudio、ServiceManagement 或 Sparkle。
- 不要把 macOS `CGKeyCode` 数值当作 Windows 键码。
- 不要在 Hook 回调里播放文件或做数据库写入。
- 不要每次按键都创建新的声卡输出实例。
- 不要读取字符内容来实现物理键统计。
- 不要删除或整体重构 `SimuBoardMac/` 来迁就 Windows。
- 不要提交 build 产物、用户数据库、日志、证书或签名密钥。
- 不要使用来源不明的音频、Apple 限定字体或受限图标补齐 Windows 资源。
- 不要在没有 Windows 真机验证的情况下发布正式版本。
- 不要把根目录旧 `audio/` 的 151 个文件当成 macOS 完整版的 237 个资源。

## 18. 推荐给 Windows 端 Codex 的第一条任务

将下面这段话连同仓库一起交给 Windows 端 Codex：

```text
请完整阅读仓库根目录 WINDOWS_PORTING_HANDOFF.md，以及其中“必读文件”列出的资料。

先只执行 Phase 0 和 Phase 1，不要修改现有 SimuBoardMac 的行为，也不要开始统计、DIY 或公开发布。请在 BattutaWindows/ 下建立 .NET 10 + WPF 解决方案，先实现稳定的 PhysicalKeyId、全局键鼠事件队列、单 WASAPI 输出流、内存 PCM 混音、托盘面板和基础设置。

开始写代码前先给出：
1. 计划新增的工程与目录；
2. 选用的 NuGet 包及许可证；
3. Windows Hook 到 PhysicalKeyId 的映射方案；
4. 音频预载、混音和设备恢复方案；
5. 首批自动化测试与手工验收步骤。

实现后必须在 Windows 上 build/test，并报告测试设备、Windows 版本、DPI、音频设备、首次与连续输入的主观延迟、快速输入是否丢音，以及仍未覆盖的风险。不要声称完成尚未测试的功能。
```

## 19. 需要产品方补充决定的事项

开发者可以先按下列默认值推进，不必等待：

- 第一版范围：Phase 1 核心音效 MVP。
- 最低系统：Windows 10 22H2 与 Windows 11。
- 架构：x64 优先，ARM64 后续。
- 语言：先中文，字符串必须集中管理以便以后国际化。
- 分发：开发阶段 portable/Debug；正式渠道稍后决定。
- UI：品牌和信息层级保持一致，系统交互遵循 Windows。

真正需要产品方最终确认：

- 第一版是否必须包含统计。
- 第一版是否必须包含完整 DIY 编辑器。
- 是否进入 Microsoft Store。
- 跨平台 DIY 包最终扩展名。
- Windows 版版本号与 macOS 是否同步。
- 是否同时支持 ARM64。

---

交接原则：先保证输入稳定、音频及时、隐私正确，再追求完整功能和像素级视觉；所有平台无关行为由测试锁定，所有平台相关能力必须在真实 Windows 环境验证。

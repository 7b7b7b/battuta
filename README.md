# Battuta 轴体音效

Battuta（原 SimuBoard）目前包含三个版本：

- 原生 macOS 菜单栏应用：在任意应用中打字都能播放声音。
- Chrome / Edge Manifest V3 插件：只在普通网页中播放声音。
- 原生 Windows 通知区域应用：WPF 界面、系统级键鼠监听、WASAPI 音频、
  本地统计和 DIY 音色，源码位于 [`BattutaWindows`](BattutaWindows/README.md)。

## Windows 系统级版本

Windows 版使用 .NET 10 + WPF，视觉结构以 macOS SwiftUI 版本为基线；
`WH_KEYBOARD_LL` / `WH_MOUSE_LL` 只生成物理键与按钮事件，不读取字符或
鼠标坐标。音频通过单一持续 WASAPI 输出流播放预载的 48 kHz PCM，完整
复用 20 种键盘音色、5 种点击音色和 237 个现有资源。

开发构建与测试：

```powershell
dotnet restore BattutaWindows/BattutaWindows.sln
dotnet build BattutaWindows/BattutaWindows.sln -c Release --no-restore
dotnet test BattutaWindows/tests/Battuta.Core.Tests/Battuta.Core.Tests.csproj -c Release --no-build --no-restore
dotnet test BattutaWindows/tests/Battuta.Windows.Tests/Battuta.Windows.Tests.csproj -c Release --no-build --no-restore
```

## macOS 系统级版本

Xcode 工程、运行说明、DMG 与 Sparkle appcast 打包脚本位于 [`SimuBoardMac`](SimuBoardMac/README.md)。1.0.0 加入四配方键盘音色轮换、前导静音优化和经过 Ed25519 验签的应用内一键更新；构建产物位于 `SimuBoardMac/build/Battuta-1.0.0-unnotarized.dmg`。

此版本使用 macOS“输入监控”读取硬件键码、鼠标按钮类型和按下/抬起状态，不读取字符内容或点击位置；支持 20 种键盘音色、5 种鼠标/触控板点击风格和共 237 段录音，并提供 DIY 音色、本地输入统计、逐键热力图和默认开启的登录时自动启动。开启自然变化后，每段键盘录音会在四种轻微配方间均衡轮换，所有变化共享一份 PCM。为保留现有设置、音色包、统计数据和输入监控代码身份，内部 Bundle Identifier 与兼容性标识仍延用旧值。当前 DMG 使用长期固定的本地自签名身份，未使用 Developer ID，也未经过 Apple 公证。

## 浏览器插件

浏览器版无需构建步骤。在网页中按键时播放机械键盘声音，可切换 13 种轴体或键盘音色。

## 浏览器插件功能

- 13 种音色：Holy Panda、MX Brown、MX Blue、BOX Navy、Blue Alps、Cream、Alpaca、Black Ink、Red Ink、MX Black、Turquoise Tealios、Topre、Buckling Spring
- 区分键盘行以及空格、回车、退格等大键声音
- 可选按键回弹音、自然音高变化和音量
- 支持总开关以及按网站静音
- 完全本地运行，不读取、保存或发送输入内容

## 安装

1. 在 Chrome 打开 `chrome://extensions`，或在 Edge 打开 `edge://extensions`。
2. 开启“开发者模式”。
3. 选择“加载已解压的扩展程序”。
4. 选择本项目根目录 `simuboard`。
5. 打开一个普通网页并刷新，然后点击工具栏中的 Battuta 选择轴体。

浏览器内置页面、扩展商店和部分受保护页面不允许内容脚本运行，因此这些页面不会播放声音。浏览器插件也无法监听 VS Code、微信、Word 等桌面应用；系统级版本需要单独的 macOS / Windows 应用与辅助功能权限。

## 验证

```bash
npm test
```

项目没有运行时第三方依赖，也不需要打包。音频文件总计约 620 KB。

## 音频来源与许可

浏览器版音频样本来自 Thomas Lai 的 [kbsim](https://github.com/tplai/kbsim)，依照 MIT License 再分发。macOS 版另外收录了可追溯至 MIT、CC0 和 CC BY 4.0 来源的开放录音。完整许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，逐项来源、处理方式和未采用候选见 [SimuBoardMac/AUDIO_SOURCES.md](SimuBoardMac/AUDIO_SOURCES.md)。

请勿直接复制 YouTube、Keyboard Simulators 或许可不明确站点的声音用于公开发布版本。

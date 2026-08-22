# SimuBoard 轴体音效

SimuBoard 目前包含两个版本：

- 原生 macOS 菜单栏应用：在任意应用中打字都能播放声音。
- Chrome / Edge Manifest V3 插件：只在普通网页中播放声音。

## macOS 系统级版本

Xcode 工程、运行说明和 DMG 打包脚本位于 [`SimuBoardMac`](SimuBoardMac/README.md)。当前版本打包后位于 `SimuBoardMac/build/SimuBoard-0.3.0-unnotarized.dmg`，之前的 0.2.3 低延迟版本仍可作为回退基线。

此版本使用 macOS“输入监控”读取硬件键码，不读取字符内容；支持 20 种音色和 202 段录音，并提供按下/回弹音、音量与轻微音高变化。部分开放资源是一次完整按键录音，没有可拆分的回弹片段，此时界面会自动停用回弹音开关。当前 DMG 未使用 Developer ID，也未经过 Apple 公证，因此不需要开发者账号即可自行构建和分享，但其他用户首次运行时必须手动允许。

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
5. 打开一个普通网页并刷新，然后点击工具栏中的 SimuBoard 选择轴体。

浏览器内置页面、扩展商店和部分受保护页面不允许内容脚本运行，因此这些页面不会播放声音。浏览器插件也无法监听 VS Code、微信、Word 等桌面应用；系统级版本需要单独的 macOS / Windows 应用与辅助功能权限。

## 验证

```bash
npm test
```

项目没有运行时第三方依赖，也不需要打包。音频文件总计约 620 KB。

## 音频来源与许可

浏览器版音频样本来自 Thomas Lai 的 [kbsim](https://github.com/tplai/kbsim)，依照 MIT License 再分发。macOS 版另外收录了可追溯至 MIT、CC0 和 CC BY 4.0 来源的开放录音。完整许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，逐项来源、处理方式和未采用候选见 [SimuBoardMac/AUDIO_SOURCES.md](SimuBoardMac/AUDIO_SOURCES.md)。

请勿直接复制 YouTube、Keyboard Simulators 或许可不明确站点的声音用于公开发布版本。

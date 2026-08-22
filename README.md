# SimuBoard 轴体音效

SimuBoard 目前包含两个版本：

- 原生 macOS 菜单栏应用：在任意应用中打字都能播放声音。
- Chrome / Edge Manifest V3 插件：只在普通网页中播放声音。

## macOS 系统级版本

Xcode 工程、运行说明和 DMG 打包脚本位于 [`SimuBoardMac`](SimuBoardMac/README.md)。0.5.1 构建产物位于 `SimuBoardMac/build/SimuBoard-0.5.1-unnotarized.dmg`；已发布的 v0.5.0 标签和 DMG 是稳定回退基线。

此版本使用 macOS“输入监控”读取硬件键码、鼠标按钮类型和按下/抬起状态，不读取字符内容或点击位置；支持 20 种键盘音色、5 种鼠标/触控板点击风格和共 237 段录音，并提供独立的按下/回弹开关、键盘音量、点击音量与共用的轻微音高变化。0.4.0 新增独立 DIY 编辑器；0.5.0 新增触控板和鼠标点击音；0.5.1 将两类音量完全分离，并重新母带处理点击音以削弱刺耳高频。应用还可以在用户同意后自动检查新版本（最多每 24 小时一次）；手动检查仅在用户点击时访问 GitHub，不上传按键、指针位置或设置。当前 DMG 使用长期固定的本地自签名身份来保持升级后的输入监控身份稳定，但未使用 Developer ID，也未经过 Apple 公证；该证书在其他 Mac 上不受信任，用户仍需手动通过 Gatekeeper 并授予输入监控。

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

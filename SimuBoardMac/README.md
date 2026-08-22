# SimuBoard for macOS

原生 macOS 菜单栏键盘音效应用，最低支持 macOS 13。内置 13 种轴体/键盘音色和 151 段按键录音，在浏览器、编辑器、聊天软件等桌面应用中均可工作。

## 在 Xcode 中运行

1. 打开 `SimuBoardMac.xcodeproj`。
2. 选择 `SimuBoardMac` scheme 和 `My Mac`。
3. 点击 Run。
4. 点击菜单栏键盘图标，在弹窗中选择“请求授权”。
5. 在“系统设置 → 隐私与安全性 → 输入监控”中启用 SimuBoard；如果没有立即生效，退出后重新运行。

应用只使用硬件按键编号选择声音，不读取字符内容。密码和输入文本不会被记录、保存或上传。

## 构建未公证 DMG

运行：

```bash
./scripts/build-dmg.sh
```

输出位于 `build/SimuBoard-0.1.0-unnotarized.dmg`。该包是同时支持 Apple Silicon 和 Intel Mac 的 Universal App，使用免费的 ad-hoc 本地签名，并未使用 Developer ID 或 Apple 公证；构建它不需要 Apple Developer 账号。

## 安装未公证版本

1. 打开 DMG，把 `SimuBoard.app` 拖到其中的 `Applications` 快捷方式；不要直接从 DMG 运行。
2. 在“应用程序”中按住 Control 点击 SimuBoard，选择“打开”。如果仍被阻止，到“系统设置 → 隐私与安全性”点击“仍要打开”。
3. 点击菜单栏键盘图标，再点击“请求授权”。
4. 在“系统设置 → 隐私与安全性 → 输入监控”中打开 SimuBoard。
5. 退出并重新打开 SimuBoard，然后确认菜单底部显示“输入监控正在运行”。

ad-hoc 签名不提供 Apple 的开发者身份与公证担保。应用更新或移动路径后，macOS 可能要求重新允许或重新授予输入监控；面向大量普通用户发布时，Developer ID 签名与公证仍是更顺滑的方案。

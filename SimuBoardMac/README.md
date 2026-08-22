# SimuBoard for macOS

原生 macOS 菜单栏键盘音效应用，最低支持 macOS 13。内置 20 种轴体/键盘音色和 227 段按键录音，在浏览器、编辑器、聊天软件等桌面应用中均可工作。应用启动时会预热音频引擎，并在加载音色时把样本预转换为 48 kHz PCM，避免首次按键再启动引擎，也避免在 48 kHz 输出链路中实时转换资源采样率。

新增音色包括 Cherry MX Clear、Logitech G915 TKL Brown、Kailh BOX White、Kailh Low-profile Blue、Keychron Red Linear，以及 Studio Tactile / Studio Clicky。完整击键录音已经按波形里的机械事件分成独立 press/release 样本，按下与抬起会跟随真实键盘事件分别播放。逐项来源、许可和导入方式见 [`AUDIO_SOURCES.md`](AUDIO_SOURCES.md)。

## DIY 音色编辑器

点击菜单栏面板里的“DIY 音色编辑器”会按需打开独立窗口，不会在应用启动时自动弹出。编辑器支持：

- 一对通用按下/回弹音快速覆盖整把键盘。
- 按 R1–R4、功能/其他键、空格、回车和退格设置推荐分布。
- 对每一个可监听的标准按键设置继承、静音或独立按下/回弹音。
- 导入 WAV、AIFF、CAF、M4A 等系统可解码音频；支持 MP3 的系统会直接转换，开发环境也可选用已安装的 ffmpeg 兜底。
- 上传包含完整按下与抬起的一段录音，依据瞬态和能量低谷自动建议切点；可查看波形、分别试听并手动微调。
- 保存后立即启用，也可导入或导出 `.simuboardpack` 与他人分享。

自定义音频在导入时统一转换成 48 kHz、单声道、16-bit PCM WAV，并在选择音色时预载到内存。实际打字只执行内存查表与播放，不在按键路径上读磁盘。映射优先级、安全限制与包结构见 [`SOUND_PACK_FORMAT.md`](SOUND_PACK_FORMAT.md)。当前仅提供 Mac ANSI TKL 编辑界面；ISO/JIS、数字小键盘和不能稳定产生标准键盘事件的硬件键尚未单独建模。

## 更新检查

首次使用时可自行决定是否允许启动后检查更新。开启后，SimuBoard 自动检查最多每 24 小时访问一次公开 GitHub Release API，并使用 ETag 避免重复下载版本信息；手动检查仅在点击时访问，且至少间隔 65 秒。GitHub 会收到 IP 地址和常规网络请求信息；SimuBoard 不上传按键、输入内容、音色设置或设备标识。

## 验证 DIY 核心

```bash
./Tests/run-diy-core-harness.sh
```

该 harness 使用 Swift 6 严格并发编译，覆盖映射优先级、音色包校验与往返、音频归一化与内存边界、自动拆分双段导出、SemVer、更新缓存和限流。

## 在 Xcode 中运行

1. 打开 `SimuBoardMac.xcodeproj`。
2. 选择 `SimuBoardMac` scheme 和 `My Mac`。
3. 点击 Run。
4. 点击菜单栏键盘图标，在弹窗中选择“请求授权”。
5. 在“系统设置 → 隐私与安全性 → 输入监控”中启用 SimuBoard；如果没有立即生效，退出后重新运行。

应用只使用硬件按键编号选择声音，不读取字符内容。密码和输入文本不会被记录、保存或上传。

## 构建未公证 DMG

首次构建前只运行一次：

```bash
./scripts/create-local-signing-identity.sh
```

它会创建一张有效期十年的 `SimuBoard Local Code Signing` 自签名证书，保存在专用的 `~/Library/Keychains/SimuBoardRelease.keychain-db`。随机钥匙串密码只保存在本机 `~/Library/Application Support/SimuBoardBuild/signing-keychain-password`，权限为 600；打包脚本只在签名时短暂解锁，完成后会重新锁定。之后每个版本必须一直使用同一张证书；请安全备份这两个文件，且绝不要把它们提交到 Git。

然后运行：

```bash
./scripts/build-dmg.sh
```

输出位于 `build/SimuBoard-0.4.0-unnotarized.dmg`。该包是同时支持 Apple Silicon 和 Intel Mac 的 Universal App。固定的自签名证书使不同版本拥有相同的 designated requirement，从而避免 ad-hoc 每次构建都被输入监控视为新 App；它仍未使用 Developer ID 或 Apple 公证，构建不需要 Apple Developer 账号。该自签证书在其他 Mac 上不受系统信任，`codesign` / `spctl` 会报告未受信任，用户仍需按下方步骤手动通过 Gatekeeper；它不能替代正式发布所需的 Developer ID。

如有正式证书，可通过 `SIMUBOARD_SIGNING_IDENTITY="Developer ID Application: ..." ./scripts/build-dmg.sh` 指定。打包脚本会拒绝退回 ad-hoc 签名，防止更新再次悄悄破坏输入监控授权。

## 安装未公证版本

1. 打开 DMG，把 `SimuBoard.app` 拖到其中的 `Applications` 快捷方式；不要直接从 DMG 运行。
2. 在“应用程序”中按住 Control 点击 SimuBoard，选择“打开”。如果仍被阻止，到“系统设置 → 隐私与安全性”点击“仍要打开”。
3. 点击菜单栏键盘图标，再点击“请求授权”。
4. 在“系统设置 → 隐私与安全性 → 输入监控”中打开 SimuBoard。
5. 退出并重新打开 SimuBoard，然后确认菜单底部显示“输入监控正在运行”。

如果从 0.3.0 或更早的 ad-hoc 版本升级，系统设置中的蓝色开关仍可能绑定旧代码身份。请先完全退出 SimuBoard，在“输入监控”列表中选中 SimuBoard 并点击下方“−”删除旧条目，再重新添加 `/Applications/SimuBoard.app`、开启并重启 App。只把开关关掉再打开不会替换旧代码身份。

自签名只用于让 SimuBoard 各版本保持同一代码身份，不提供 Apple 的开发者身份或公证担保。面向大量普通用户发布时，Developer ID 签名与公证仍是更顺滑的方案。

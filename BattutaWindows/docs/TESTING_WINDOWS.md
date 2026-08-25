# Battuta Windows 测试说明

本文定义 Windows 移植的测试分层、运行命令和真实设备验收边界。测试事实来源是
`SimuBoardMac/Tests/`，但 Windows 测试应验证相同的行为语义，不应照抄
`CGKeyCode`、AppKit、AVFAudio 或 Sparkle 实现。

## 1. 测试分层

| 层级 | 默认运行 | 说明 |
|---|---:|---|
| Core | 是 | 纯 C# 模型、解析、聚合、格式与安全边界；不得依赖 WPF、Win32 或声卡 |
| Integration | 是 | scan code 映射、有界队列、离线混音、临时 SQLite 和文件系统 |
| UI | 否 | 需要交互桌面、STA、Explorer 和稳定显示设置 |
| Hardware | 否 | 真实 Hook、WASAPI、设备切换、休眠唤醒和输入法 |
| Packaging | 发布门禁 | x64 publish/MSIX 内容、架构、许可、安装、升级与卸载 |
| Performance | 定期运行 | 首次播放、30 秒快速输入、队列水位、CPU 与常驻内存 |

测试用例使用统一 trait：

```csharp
[Trait(TestCategories.TraitName, TestCategories.Core)]
```

普通构建机只运行 Core 和无硬件 Integration。UI、Hardware、Packaging 和
Performance 必须显式选择，不能因测试机缺少声卡或桌面而被误报为产品回归。

## 2. 常用命令

从 `BattutaWindows/` 运行：

```powershell
dotnet restore BattutaWindows.sln
dotnet build BattutaWindows.sln -c Debug --no-restore
dotnet test tests/Battuta.Core.Tests/Battuta.Core.Tests.csproj -c Debug --no-build --no-restore
dotnet test tests/Battuta.Windows.Tests/Battuta.Windows.Tests.csproj -c Debug --no-build --no-restore
```

发布前再运行：

```powershell
dotnet build BattutaWindows.sln -c Release --no-restore -warnaserror
dotnet test tests/Battuta.Core.Tests/Battuta.Core.Tests.csproj -c Release --no-build --no-restore
dotnet test tests/Battuta.Windows.Tests/Battuta.Windows.Tests.csproj -c Release --no-build --no-restore
dotnet list BattutaWindows.sln package --vulnerable --include-transitive
dotnet list BattutaWindows.sln package --deprecated
dotnet publish src/Battuta.Windows/Battuta.Windows.csproj -c Release -r win-x64 --self-contained true
```

测试工程使用 xUnit v3 的 Microsoft Testing Platform runner。直接运行单个工程时，
应把 `.csproj` 作为 `dotnet test` 的位置参数；不要改写成
`dotnet test --project ...`。后者在当前 SDK/runner 组合下会走 project-discovery
模式，并可能以 exit code 5 报告 `0 tests`。`--no-build` 也必须在同一
Configuration 已成功构建后使用。

如果仓库已提交 `packages.lock.json`，CI restore 应增加 `--locked-mode`。不要通过
关闭 TLS、签名检查或 NuGet audit 来绕过受限网络错误。

`Directory.Build.props` 会启用 nullable、NET analyzers 和推荐规则，但普通本地/Debug
构建只报告 analyzer warning。CI/Release 由上面的 `-warnaserror` 命令执行严格门禁，
避免并行开发期间被非阻断的新增 CA 建议卡住。

## 3. `Battuta.TestSupport`

两个测试工程都应引用 `tests/Battuta.TestSupport/Battuta.TestSupport.csproj`。
该项目只依赖 `Battuta.Core`，不会把 WPF、NAudio 或 SQLite 带入 Core 测试。

### 可控时间

```csharp
var clock = new FakeClock(new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero));
var provider = clock.AsProvider();
clock.Advance(TimeSpan.FromMinutes(5));
Assert.Equal(clock.Now, provider());
```

跨日、DST 和时区测试应显式传入时间与 `TimeZoneInfo`，不得依赖测试机当前日期。

### 临时目录

```csharp
using var directory = new TempDirectory("battuta-pack");
var manifestPath = directory.WriteAllText("Example.simuboardpack/manifest.json", "{}");
```

`TempDirectory.GetPath` 拒绝绝对路径和目录穿越，清理时不跟随 reparse point。
恶意 ZIP、符号链接和 junction fixture 只能指向该测试自己的临时根目录。

### 音频 fixture

```csharp
using var directory = new TempDirectory("battuta-audio");
var wave = AudioFixtureFactory.WriteCompleteKeystroke(
    directory.GetPath("complete-keystroke.wav"));
```

fixture 直接生成 PCM16 WAV，不依赖 NAudio，可用于验证 48 kHz mono 归一化、
拆音和内存上限。`WriteInvalidAudio` 用于失败路径。测试内不得分发来源不明的录音。

### 统计 fixture

```csharp
var fixture = StatsFixtureFactory.CreateTwoDayAggregateFixture(fixedNow);
var history = StatsFixtureFactory.CreateUiHistoryFixture(new DateOnly(2026, 8, 24));
```

两日 fixture 与 macOS harness 的 9/12 字符、两个应用和逐键累计口径一致；UI
fixture 默认生成 730 天、8 个应用和稳定的当前/上期数据，不使用随机数。

### STA 测试

```csharp
await StaTestHost.RunAsync(async () =>
{
    Assert.Equal(ApartmentState.STA, Thread.CurrentThread.GetApartmentState());
    await Task.Yield();
    Assert.Equal(ApartmentState.STA, Thread.CurrentThread.GetApartmentState());
});
```

`StaTestHost` 保证 async continuation 留在同一 STA，并有默认 30 秒超时。需要完整
WPF Dispatcher 消息循环、真实托盘或跨进程 UI Automation 的用例应放在 UI smoke
工程，通过独立应用进程运行，不要让普通单元测试打开用户窗口。

## 4. Core 回归门禁

首批必须覆盖：

1. `PhysicalKeyId` 唯一、稳定序列化，左右修饰键、主/小键盘 Enter 和扩展键可区分。
2. 音色解析优先级：逐键、特殊键、R0–R4、generic、内置回退；`inherit`、
   `silent` 和 broken asset。
3. 四套 gain/rate 均衡轮换、无连续重复；关闭自然变化后只播放原音。
4. 237 个内置资源、20 个键盘 profile、5 个点击 profile 的目录与解码检查。
5. manifest schema、SHA-256、大小/数量/时长限制和导入导出往返。
6. ZIP traversal、绝对/UNC/设备路径、ADS、大小写重复项、reparse point、压缩炸弹。
7. PCM 归一化、64 MiB 解码上限、算术溢出、超时/取消清理和拆音边界。
8. SemVer 2.0、更新 URL allowlist、ETag、5 分钟自动/65 秒手动节流和 rate limit。
9. repeat、快捷键、AltGr/IME、跨日/DST、失败批次、flush/clear barrier。
10. SQLite schema、31 日细节保留、永久日汇总、旧版迁移、未来 schema 与损坏恢复。

macOS harness 中读取源码字符串的断言应改为接口 fake 驱动的行为测试。

## 5. Windows 集成与隐私

自动化输入必须发送到专用测试窗口，并明确区分 injected flag；不得向用户当前前台
应用注入按键。Hook callback 测试只允许产生如下数据：

```text
PhysicalKeyId, phase, repeat, modifiers, timestamp
```

统计与日志测试必须证明不会写入字符、窗口标题、剪贴板、鼠标坐标或完整按键序列。
鼠标 smoke 只覆盖 button down/up，不采集移动、拖动和滚轮。

需要真实 Windows 会话验证：

- Hook 安装/卸载、Explorer 重启和应用退出清理。
- 中文 IME、英文布局、AltGr、外接键盘、多键同时按下。
- 浏览器、VS Code、聊天软件和 Word 类程序中的前台应用识别。
- 普通进程监听管理员进程时的明确降级，不请求管理员权限。
- WASAPI 无设备、默认设备切换、拔插耳机、蓝牙、休眠唤醒。
- 16 voice 重叠与 30 秒快速输入，不丢音、不持续增长内存。

托盘原生菜单的真实“点击菜单外关闭”测试会移动鼠标并发送一次左键点击，因此默认
只验证 Win32 合同而不会注入桌面输入。只能在专用测试桌面显式启用：

```powershell
$env:BATTUTA_REQUIRE_INTERACTIVE_TRAY_TEST = "1"
dotnet test tests/Battuta.Windows.Tests/Battuta.Windows.Tests.csproj -c Debug --filter "FullyQualifiedName~NativeContextMenuRealOutsideClickReturnsNone"
Remove-Item Env:\BATTUTA_REQUIRE_INTERACTIVE_TRAY_TEST
```

运行前关闭文档编辑器、聊天窗口等可能被外部点击影响的应用，并记录 Explorer、
任务栏位置、显示器 DPI 与高对比度状态。

## 6. UI smoke

应用应提供仅限 Debug/测试的确定性入口，并支持 fake 数据且禁用 Hook、音频、更新
网络和用户数据库：

```text
--show-menu-preview
--show-stats
--stats-history
--stats-keyboard
--show-diy
--test-data
```

截图与 UI Automation 至少覆盖：

| 界面 | 标准尺寸 | 关键断言 |
|---|---:|---|
| 托盘面板 | 360 × 760 DIP | 560–820 高度范围、点击外部/Esc 关闭、重新打开回到顶部 |
| 输入统计 | 1100 × 760 | 最小 1100 × 600；历史页两张主卡始终并排，三页无裁切 |
| DIY 编辑器 | 1240 × 760 | 最小 1120 × 660，三栏、dirty-close、保存/启用状态 |
| 自动拆音 | 760 × 630 | 切点、释放终点、覆盖确认和取消清理 |

测试 100%、125%、150%、200% DPI，以及 1366×768、1920×1080 和 4K。
所有可操作控件必须有稳定 `AutomationId`、可读 Name、正确 Tab 顺序和焦点恢复。
真实托盘锚点、多显示器和任务栏工作区不能用离屏渲染代替。

## 7. Packaging 门禁

发布目录必须验证：

- PE/RID 为 `win-x64`，版本、产品名与包清单一致。
- 237 个音频及其哈希完整，包含第三方许可和隐私说明。
- `NAudio.Wasapi` 与 SQLite native runtime 实际进入发布结果。
- 不包含 DMG、macOS Sparkle、用户数据库、日志、证书、私钥或临时 fixture。
- 安装、覆盖升级和卸载不会意外删除设置、统计或 DIY 音色。
- 固定托盘 GUID，Explorer 重启和安装路径变化后不产生重复图标记录。

## 8. 验收记录模板

每次真实设备验收记录：

```text
Commit/版本：
Windows edition / build / architecture：
显示器、分辨率、DPI、任务栏位置：
默认音频设备及连接类型：
键盘类型、布局和输入法：
首次输入主观延迟：
连续输入/16 voice/30 秒结果：
默认设备切换、拔插、休眠唤醒结果：
托盘、统计、DIY、拆音 UI 结果：
尚未覆盖的风险：
```

没有真实运行的项目必须写“未测试”，不能由编译通过推断硬件或视觉行为通过。

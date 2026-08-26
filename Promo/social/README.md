# Battuta 竖屏宣传片

## 成片

- 视频：`../../media/battuta-social-vertical-v4.mp4`
- 封面：`../../media/battuta-social-vertical-v4-cover.png`
- 规格：1080 × 1920、约 41 秒、30 fps、H.264 + AAC

视频使用仓库内的产品录屏、DIY 编辑器截图、应用图标和下载二维码。
声音演示依次使用 Logitech G915 TKL Brown、Gateron Black Ink 和
Turquoise Tealios 三段原录屏同期声，并保留各段原始增益。随后展示
DIY、输入统计和正在规划中的 Battuta 音色社区；社区页明确说明未来计划
支持用户自由上传、发现和下载音色包。其余段落不添加背景音乐、合成节奏
或额外键音。片头和片尾使用连续静音采样，避免部分播放器跳过音频时间戳
空洞。输入统计段会按原速完整播放 14.07 秒，不截断、不加速。旧版 v1、
v2、v3 仍保留，可用于对比。

## 重新生成

在仓库根目录执行：

```bash
bash Promo/social/build-vertical-promo.sh
```

也可以传入自定义输出路径：

```bash
bash Promo/social/build-vertical-promo.sh /path/to/output.mp4
```

## 发布文案

### 抖音 / 快手

> 打字，也该有好声音。Battuta 给键盘、鼠标和触控板加上真实按键音，
> 21 种键盘音色、5 种点击风格，还能 DIY 逐键定制。macOS 和 Windows
> 都能用，访问 `wormforce.net/projects/battuta` 了解与下载。

推荐标签：`#机械键盘 #效率工具 #开源软件 #macOS #Windows`

### 小红书

标题：`我给电脑装了 21 种机械键盘声音`

> 做了一个叫 Battuta 的小工具：打字、点击鼠标和触控板时，会实时播放
> 本地键音。除了现成音色，还能 DIY 逐键定制，并查看趋势、年度热力图和
> 逐键分布。它只保存聚合统计，不读取输入内容。macOS / Windows 均可用，
> 访问 `wormforce.net/projects/battuta` 免费下载。

### 朋友圈

> 最近做的 Battuta：把喜欢的键盘声音装进电脑，支持 macOS / Windows，
> 开源且本地运行。感兴趣可以扫视频结尾二维码，或者在 GitHub 搜索
> 产品官网 `wormforce.net/projects/battuta`。

## 发布建议

- 上传原始 MP4，不要先经过聊天软件二次压缩。
- 保留原始键音；若添加平台音乐，把音乐音量压低，避免盖住按键声。
- 使用配套竖屏封面，并在发布前检查平台裁切后的标题与二维码位置。

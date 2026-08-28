# Battuta 竖屏宣传片

## 通用 v4 成片

- 视频：`../../media/battuta-social-vertical-v4.mp4`
- 封面：`../../media/battuta-social-vertical-v4-cover.png`
- 规格：1080 × 1920、约 41 秒、30 fps、H.264 + AAC

通用版保留产品官网、下载二维码和完整下载 CTA，适合官网、GitHub 与允许
站外链接的平台。

## 三平台成片

- 小红书：`../../media/battuta-xiaohongshu-vertical-v1.mp4`
- 抖音：`../../media/battuta-douyin-vertical-v1.mp4`
- 朋友圈：`../../media/battuta-moments-vertical-v1.mp4`
- 配套发布文案：`PLATFORM_COPY.md`

三版同样为 1080 × 1920、约 41 秒、30 fps、H.264 + AAC。小红书与
抖音版不包含二维码、网址或站外下载 CTA；朋友圈版保留指向产品官网的
二维码。

## 内容与音频

视频使用仓库内的产品录屏、DIY 编辑器截图、应用图标和下载二维码。
声音演示依次使用 Logitech G915 TKL Brown、Gateron Black Ink 和
Turquoise Tealios 三段原录屏同期声，并保留各段原始增益。随后展示
DIY、输入统计和正在规划中的 Battuta 音色社区；社区页明确说明未来计划
支持用户自由上传、发现和下载音色包。其余段落不添加背景音乐、合成节奏
或额外键音。片头和片尾使用连续静音采样，避免部分播放器跳过音频时间戳
空洞。输入统计段会按原速完整播放 14.07 秒，不截断、不加速。旧版 v1、
v2、v3 仍保留，可用于对比。

## 重新生成

在仓库根目录生成通用 v4：

```bash
bash Promo/social/build-vertical-promo.sh
```

也可以传入自定义输出路径；`generic` 可省略：

```bash
bash Promo/social/build-vertical-promo.sh /path/to/output.mp4 generic
```

一次生成三个平台版本：

```bash
bash Promo/social/build-platform-promos.sh
```

也可以只生成一个平台版本：

```bash
bash Promo/social/build-vertical-promo.sh /path/to/output.mp4 xiaohongshu
bash Promo/social/build-vertical-promo.sh /path/to/output.mp4 douyin
bash Promo/social/build-vertical-promo.sh /path/to/output.mp4 moments
```

## 发布文案

三平台的完整发布文案和合规说明参见 `PLATFORM_COPY.md`。通用版可使用：

> 打字，也该有好声音。Battuta 给键盘、鼠标和触控板加上真实按键音，
> 21 种键盘音色、5 种点击风格，还能 DIY 逐键定制。macOS 和 Windows
> 都能用，访问 `wormforce.net/projects/battuta` 了解与下载。

推荐标签：`#机械键盘 #效率工具 #开源软件 #macOS #Windows`

## 发布建议

- 上传原始 MP4，不要先经过聊天软件二次压缩。
- 保留原始键音；若添加平台音乐，把音乐音量压低，避免盖住按键声。
- 使用配套竖屏封面，并在发布前检查平台裁切后的标题安全区及二维码位置。
- 小红书和抖音版本不要在发布时重新添加二维码、网址或导流暗语。

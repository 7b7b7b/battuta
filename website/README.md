# Battuta product website

本目录是 Battuta 的独立产品页。页面、视频、图标和当前 DMG 均为本地资源；主下载按钮不会把访客带到 GitHub 页面。

## 本地预览

```bash
npm install
npm run dev
```

默认地址为 `http://localhost:3000`。生产构建使用：

```bash
npm run build
```

## 挂载子域名时

将部署环境变量 `NEXT_PUBLIC_SITE_URL` 设置为最终的 HTTPS 地址，例如 `https://battuta.example.com`，用于生成正确的分享卡链接。

## 发布新版本时

1. 把新 DMG 放进 `public/downloads/`。
2. 更新 `app/page.tsx` 顶部的 `downloadHref`、页面版本号和安装包大小。
3. 替换 `public/og.png`，或者继续沿用当前资料卡。
4. 重新运行 `npm run build`。

`GitHub 备用下载`只作为故障回退；主下载按钮直接提供网站内的 DMG。

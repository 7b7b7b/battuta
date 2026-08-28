import type { Metadata } from 'next';
import './globals.css';

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: 'Battuta — 把喜欢的键盘声音装进你的 Mac',
  description:
    'Battuta 是一款 macOS 菜单栏键盘与点击音效应用，提供 20 种键盘音色、5 种点击风格、DIY 音色与本地输入统计。',
  icons: {
    icon: '/battuta-icon.png',
    apple: '/battuta-icon.png',
  },
  openGraph: {
    type: 'website',
    locale: 'zh_CN',
    title: 'Battuta — 把喜欢的键盘声音装进你的 Mac',
    description: '20 种键盘音色、5 种点击风格、DIY 音色与本地输入统计。',
    images: [{ url: '/og.png', width: 1920, height: 1080, alt: 'Battuta 产品资料卡' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Battuta — 把喜欢的键盘声音装进你的 Mac',
    description: '20 种键盘音色、5 种点击风格、DIY 音色与本地输入统计。',
    images: ['/og.png'],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}

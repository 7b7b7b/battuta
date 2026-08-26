#!/usr/bin/env swift

import AppKit
import Foundation

let canvasWidth: CGFloat = 1080
let canvasHeight: CGFloat = 1920

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_overlays.swift OUTPUT_DIRECTORY\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let cream = NSColor(calibratedRed: 0.956, green: 0.941, blue: 0.906, alpha: 1)
let lime = NSColor(calibratedRed: 0.812, green: 1.0, blue: 0.322, alpha: 1)
let muted = NSColor(calibratedRed: 0.67, green: 0.70, blue: 0.65, alpha: 1)
let line = NSColor(calibratedRed: 0.81, green: 1.0, blue: 0.32, alpha: 0.25)

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}

func drawText(
    _ value: String,
    top: CGFloat,
    height: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    x: CGFloat = 60,
    width: CGFloat = 960,
    alignment: NSTextAlignment = .center,
    monospaced: Bool = false
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 4

    let font = monospaced
        ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 16
    shadow.shadowOffset = NSSize(width: 0, height: -3)

    (value as NSString).draw(
        in: rectFromTop(x: x, y: top, width: width, height: height),
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
    )
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor?, stroke: NSColor?, lineWidth: CGFloat = 2) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if let fill {
        fill.setFill()
        path.fill()
    }
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawLabel(_ value: String, top: CGFloat) {
    let labelRect = rectFromTop(x: 390, y: top, width: 300, height: 54)
    drawRoundedRect(labelRect, radius: 27, fill: NSColor(calibratedRed: 0.81, green: 1.0, blue: 0.32, alpha: 0.10), stroke: line)
    drawText(value, top: top + 10, height: 36, size: 22, weight: .semibold, color: lime, x: 390, width: 300)
}

func drawVideoFrame(top: CGFloat, height: CGFloat) {
    let frame = rectFromTop(x: 28, y: top, width: 1024, height: height)
    drawRoundedRect(frame, radius: 30, fill: nil, stroke: NSColor.white.withAlphaComponent(0.18), lineWidth: 3)
}

func render(name: String, drawing: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasWidth),
        pixelsHigh: Int(canvasHeight),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "BattutaPromo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight).fill()
    drawing()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BattutaPromo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }
    try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
}

try render(name: "intro") {
    drawText("打字，也该有好声音。", top: 720, height: 100, size: 72, weight: .bold, color: cream)
    drawText("Battuta.", top: 855, height: 138, size: 116, weight: .heavy, color: lime)
    drawText("键盘 · 鼠标 · 触控板音效", top: 1020, height: 60, size: 34, weight: .medium, color: muted)
    drawRoundedRect(rectFromTop(x: 310, y: 1175, width: 460, height: 70), radius: 35, fill: NSColor.black.withAlphaComponent(0.28), stroke: line)
    drawText("真实键音 · 本地运行", top: 1190, height: 44, size: 26, weight: .semibold, color: cream, x: 310, width: 460)
}

func renderSoundOverlay(name: String, number: String, title: String, subtitle: String) throws {
    try render(name: name) {
        drawLabel("真实键音 · \(number)/3", top: 112)
        drawText(title, top: 188, height: 84, size: 54, weight: .bold, color: cream)
        drawText(subtitle, top: 282, height: 56, size: 34, weight: .semibold, color: lime)
        drawVideoFrame(top: 420, height: 774)
        drawText("同一段文字，不同的声音手感", top: 1310, height: 72, size: 46, weight: .bold, color: cream)
        drawText("原录屏同期声 · 保持原始音量", top: 1400, height: 56, size: 31, weight: .medium, color: muted)
    }
}

try renderSoundOverlay(
    name: "sound-g915",
    number: "1",
    title: "Logitech G915 TKL Brown",
    subtitle: "低矮茶轴 · 清晰利落"
)

try renderSoundOverlay(
    name: "sound-ink",
    number: "2",
    title: "Gateron Black Ink",
    subtitle: "黑墨轴 · 沉稳顺滑"
)

try renderSoundOverlay(
    name: "sound-tealios",
    number: "3",
    title: "Turquoise Tealios",
    subtitle: "顺滑线性 · 明亮回弹"
)

try render(name: "diy") {
    drawLabel("音色 DIY", top: 112)
    drawText("不只选择现成音色", top: 190, height: 78, size: 57, weight: .bold, color: cream)
    drawText("还能 DIY 逐键定制", top: 272, height: 78, size: 57, weight: .bold, color: lime)
    drawVideoFrame(top: 440, height: 658)
    drawText("按键、按下与回弹，都能自己分配", top: 1220, height: 72, size: 42, weight: .bold, color: cream)
    drawText("把一套声音，真正调成自己的键盘", top: 1315, height: 56, size: 31, weight: .medium, color: muted)
}

try render(name: "stats") {
    drawLabel("输入统计", top: 112)
    drawText("不只听见，也能看见", top: 190, height: 84, size: 58, weight: .bold, color: cream)
    drawVideoFrame(top: 420, height: 774)
    drawText("趋势 · 年度热力图 · 逐键分布", top: 1305, height: 70, size: 43, weight: .bold, color: cream)
    drawText("只保存聚合统计，不读取输入内容", top: 1400, height: 58, size: 32, weight: .semibold, color: lime)
}

try render(name: "community") {
    drawLabel("社区计划", top: 112)
    drawText("未来，把音色分享给更多人", top: 190, height: 84, size: 57, weight: .bold, color: cream)
    drawText("Battuta 音色社区 · 计划开放", top: 292, height: 56, size: 34, weight: .semibold, color: lime)

    let cardTop: CGFloat = 760
    let cardWidth: CGFloat = 292
    let cardHeight: CGFloat = 238
    let cards: [(CGFloat, String, String, String)] = [
        (64, "↑", "上传", "分享自己的音色包"),
        (394, "◎", "发现", "试听社区的新声音"),
        (724, "↓", "下载", "把喜欢的声音带走")
    ]

    for (x, symbol, title, subtitle) in cards {
        drawRoundedRect(
            rectFromTop(x: x, y: cardTop, width: cardWidth, height: cardHeight),
            radius: 30,
            fill: NSColor.black.withAlphaComponent(0.34),
            stroke: line,
            lineWidth: 2
        )
        drawText(symbol, top: cardTop + 28, height: 62, size: 54, weight: .bold, color: lime, x: x, width: cardWidth)
        drawText(title, top: cardTop + 105, height: 46, size: 34, weight: .bold, color: cream, x: x, width: cardWidth)
        drawText(subtitle, top: cardTop + 166, height: 40, size: 22, weight: .medium, color: muted, x: x + 12, width: cardWidth - 24)
    }

    drawText("自由上传，也能自由下载", top: 1135, height: 76, size: 50, weight: .bold, color: cream)
    drawText("让每一套音色包都有作者、预览与版本", top: 1235, height: 58, size: 31, weight: .medium, color: muted)
    drawRoundedRect(rectFromTop(x: 330, y: 1370, width: 420, height: 68), radius: 34, fill: NSColor.black.withAlphaComponent(0.28), stroke: line)
    drawText("正在规划中", top: 1385, height: 42, size: 27, weight: .semibold, color: lime, x: 330, width: 420)
}

try render(name: "outro") {
    drawText("Battuta.", top: 515, height: 126, size: 108, weight: .heavy, color: lime)
    drawText("把喜欢的键盘声音，装进你的电脑。", top: 655, height: 76, size: 45, weight: .bold, color: cream)
    drawRoundedRect(rectFromTop(x: 320, y: 760, width: 440, height: 68), radius: 34, fill: NSColor.black.withAlphaComponent(0.28), stroke: line)
    drawText("macOS  ·  Windows", top: 775, height: 42, size: 28, weight: .semibold, color: cream, x: 320, width: 440)
    drawRoundedRect(rectFromTop(x: 370, y: 905, width: 340, height: 340), radius: 34, fill: nil, stroke: line, lineWidth: 4)
    drawText("产品官网", top: 1300, height: 50, size: 30, weight: .semibold, color: muted)
    drawText("wormforce.net/projects/battuta", top: 1360, height: 72, size: 41, weight: .bold, color: cream, monospaced: true)
    drawText("开源 · 本地运行 · 不记录输入内容", top: 1510, height: 56, size: 27, weight: .medium, color: muted)
}

print("Rendered overlays to \(outputDirectory.path)")

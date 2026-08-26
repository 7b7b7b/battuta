#!/usr/bin/env swift

import AppKit
import CoreImage
import Foundation

let defaultURL = "https://www.wormforce.net/projects/battuta"
let defaultOutput = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("battuta-download-qr.png")

let destinationURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : defaultOutput
let encodedURL = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : defaultURL

guard let message = encodedURL.data(using: .utf8),
      let filter = CIFilter(name: "CIQRCodeGenerator") else {
    fputs("Unable to initialize QR generator.\n", stderr)
    exit(1)
}

filter.setValue(message, forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")

guard let code = filter.outputImage else {
    fputs("Unable to generate QR image.\n", stderr)
    exit(1)
}

let canvasSize = 420
let quietZoneModules = 4
let moduleCount = Int(code.extent.width)
let moduleScale = canvasSize / (moduleCount + quietZoneModules * 2)
let renderedSize = moduleCount * moduleScale
let offset = (canvasSize - renderedSize) / 2

let context = CIContext(options: [.useSoftwareRenderer: true])
let moduleBytesPerRow = moduleCount * 4
var modules = [UInt8](repeating: 0, count: moduleBytesPerRow * moduleCount)
context.render(
    code,
    toBitmap: &modules,
    rowBytes: moduleBytesPerRow,
    bounds: code.extent,
    format: .RGBA8,
    colorSpace: CGColorSpaceCreateDeviceRGB()
)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: canvasSize * 4,
    bitsPerPixel: 32
), let pixels = bitmap.bitmapData else {
    fputs("Unable to allocate QR bitmap.\n", stderr)
    exit(1)
}

memset(pixels, 255, canvasSize * canvasSize * 4)
for sourceY in 0..<moduleCount {
    for sourceX in 0..<moduleCount {
        let moduleOffset = sourceY * moduleBytesPerRow + sourceX * 4
        guard modules[moduleOffset] < 128 else { continue }

        let targetX = offset + sourceX * moduleScale
        let targetY = offset + sourceY * moduleScale
        for y in targetY..<(targetY + moduleScale) {
            for x in targetX..<(targetX + moduleScale) {
                let pixelOffset = y * canvasSize * 4 + x * 4
                pixels[pixelOffset] = 0
                pixels[pixelOffset + 1] = 0
                pixels[pixelOffset + 2] = 0
                pixels[pixelOffset + 3] = 255
            }
        }
    }
}

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode QR image as PNG.\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: destinationURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: destinationURL, options: .atomic)

print("QR: \(destinationURL.path)")
print("URL: \(encodedURL)")

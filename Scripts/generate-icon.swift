#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let output = resources.appendingPathComponent("AppIcon.icns")
let sourceOutput = resources.appendingPathComponent("AppIcon-source.png")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    let cornerRadius = CGFloat(pixels) * 0.21
    let tileRect = rect.insetBy(dx: CGFloat(pixels) * 0.035, dy: CGFloat(pixels) * 0.035)
    let background = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

    if pixels >= 128 {
        let tileShadow = NSShadow()
        tileShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.018)
        tileShadow.shadowBlurRadius = CGFloat(pixels) * 0.055
        tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        tileShadow.set()
    }

    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.99, green: 0.955, blue: 0.90, alpha: 1),
            NSColor(calibratedRed: 0.925, green: 0.815, blue: 0.72, alpha: 1)
        ]
    )?.draw(in: background, angle: 35)

    let width = CGFloat(pixels)
    drawPaperGrain(in: tileRect, pixels: pixels)

    NSColor.white.withAlphaComponent(0.22).setStroke()
    background.lineWidth = max(1, width * 0.006)
    background.stroke()

    let inset = width * 0.17
    let dialRect = rect.insetBy(dx: inset, dy: inset)
    let clay = NSColor(calibratedRed: 0.68, green: 0.30, blue: 0.21, alpha: 1)
    let clayDark = NSColor(calibratedRed: 0.48, green: 0.18, blue: 0.13, alpha: 1)
    let ink = NSColor(calibratedRed: 0.17, green: 0.15, blue: 0.13, alpha: 1)
    let moss = NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.27, alpha: 1)

    let outer = NSBezierPath(ovalIn: dialRect)
    if pixels >= 128 {
        let dialShadow = NSShadow()
        dialShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.012)
        dialShadow.shadowBlurRadius = CGFloat(pixels) * 0.035
        dialShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.13)
        dialShadow.set()
    }
    NSColor.white.withAlphaComponent(0.48).setFill()
    outer.fill()

    NSColor(calibratedRed: 0.55, green: 0.34, blue: 0.24, alpha: 0.10).setStroke()
    outer.lineWidth = max(1, width * 0.008)
    outer.stroke()

    let center = NSPoint(x: width * 0.5, y: width * 0.5)
    let nodeCenter = NSPoint(x: width * 0.68, y: width * 0.67)
    let line = NSBezierPath()
    line.move(to: center)
    line.line(to: nodeCenter)
    line.lineWidth = max(1.5, width * 0.018)
    line.lineCapStyle = .round
    NSColor(calibratedRed: 0.17, green: 0.15, blue: 0.13, alpha: 0.18).setStroke()
    line.stroke()

    let arc = NSBezierPath()
    arc.appendArc(
        withCenter: center,
        radius: width * 0.28,
        startAngle: 138,
        endAngle: 410,
        clockwise: false
    )
    arc.lineWidth = max(3, width * 0.060)
    arc.lineCapStyle = .round
    if pixels >= 128 {
        let arcShadow = NSShadow()
        arcShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.008)
        arcShadow.shadowBlurRadius = CGFloat(pixels) * 0.012
        arcShadow.shadowColor = clayDark.withAlphaComponent(0.32)
        arcShadow.set()
    }
    clay.setStroke()
    arc.stroke()

    let smallArc = NSBezierPath()
    smallArc.appendArc(
        withCenter: center,
        radius: width * 0.185,
        startAngle: 212,
        endAngle: 318,
        clockwise: false
    )
    smallArc.lineWidth = max(2, width * 0.026)
    smallArc.lineCapStyle = .round
    moss.setStroke()
    smallArc.stroke()

    let centerDot = NSBezierPath(ovalIn: NSRect(x: width * 0.43, y: width * 0.43, width: width * 0.14, height: width * 0.14))
    ink.setFill()
    centerDot.fill()

    let highlight = NSBezierPath(ovalIn: NSRect(x: width * 0.468, y: width * 0.505, width: width * 0.028, height: width * 0.028))
    NSColor.white.withAlphaComponent(0.34).setFill()
    highlight.fill()

    let nodeDot = NSBezierPath(ovalIn: NSRect(x: width * 0.64, y: width * 0.63, width: width * 0.09, height: width * 0.09))
    moss.setFill()
    nodeDot.fill()

    let nodeRim = NSBezierPath(ovalIn: NSRect(x: width * 0.64, y: width * 0.63, width: width * 0.09, height: width * 0.09))
    NSColor.white.withAlphaComponent(0.52).setStroke()
    nodeRim.lineWidth = max(1, width * 0.008)
    nodeRim.stroke()

    image.unlockFocus()
    return image
}

func drawPaperGrain(in rect: NSRect, pixels: Int) {
    guard pixels >= 256 else { return }
    var seed: UInt64 = 0xC10A_D1A6
    let count = pixels >= 1024 ? 900 : 260

    for _ in 0..<count {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let xUnit = CGFloat(seed & 0xffff) / CGFloat(UInt16.max)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let yUnit = CGFloat(seed & 0xffff) / CGFloat(UInt16.max)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let alpha = 0.018 + (CGFloat(seed & 0xff) / 255) * 0.026
        let dotSize = max(1, CGFloat(pixels) * 0.0016)
        let dotRect = NSRect(
            x: rect.minX + rect.width * xUnit,
            y: rect.minY + rect.height * yUnit,
            width: dotSize,
            height: dotSize
        )
        NSColor(calibratedWhite: 0.44, alpha: alpha).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}

func pngData(from image: NSImage) throws -> Data {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "NetEnvCheckIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to render PNG"])
    }

    return png
}

try pngData(from: drawIcon(pixels: 1024)).write(to: sourceOutput, options: .atomic)

for variant in variants {
    let image = drawIcon(pixels: variant.pixels)
    try pngData(from: image).write(to: iconset.appendingPathComponent(variant.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "NetEnvCheckIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

try? FileManager.default.removeItem(at: iconset)
print(output.path)

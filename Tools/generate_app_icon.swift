import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon.icns")
let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("subtitleextractor-icon-\(UUID().uuidString).iconset", isDirectory: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func savePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG に変換できませんでした"])
    }
    try pngData.write(to: url, options: .atomic)
}

func appIconImage(size: CGFloat) -> NSImage {
    let canvas = NSSize(width: size, height: size)
    let image = NSImage(size: canvas)
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(origin: .zero, size: canvas)
    NSColor.clear.setFill()
    rect.fill()

    let outerRect = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: size * 0.22, yRadius: size * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.42, alpha: 1.0),
        NSColor(calibratedRed: 0.28, green: 0.17, blue: 0.52, alpha: 1.0),
        NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.23, alpha: 1.0),
    ])!
    gradient.draw(in: outerPath, angle: -35)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -size * 0.02),
        blur: size * 0.06,
        color: NSColor.black.withAlphaComponent(0.28).cgColor
    )

    let viewerRect = NSRect(
        x: outerRect.minX + size * 0.14,
        y: outerRect.minY + size * 0.28,
        width: size * 0.72,
        height: size * 0.42
    )
    let viewerPath = NSBezierPath(roundedRect: viewerRect, xRadius: size * 0.08, yRadius: size * 0.08)
    NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.0, alpha: 0.96).setFill()
    viewerPath.fill()

    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    let framePath = NSBezierPath(roundedRect: viewerRect, xRadius: size * 0.08, yRadius: size * 0.08)
    NSColor.white.withAlphaComponent(0.72).setStroke()
    framePath.lineWidth = max(2, size * 0.015)
    framePath.stroke()

    let subtitleBarRect = NSRect(
        x: outerRect.minX + size * 0.13,
        y: outerRect.minY + size * 0.15,
        width: size * 0.74,
        height: size * 0.14
    )
    let subtitleBar = NSBezierPath(roundedRect: subtitleBarRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.26, alpha: 0.98).setFill()
    subtitleBar.fill()

    let accentRect = NSRect(
        x: viewerRect.minX + size * 0.045,
        y: viewerRect.maxY - size * 0.105,
        width: size * 0.16,
        height: size * 0.06
    )
    let accent = NSBezierPath(roundedRect: accentRect, xRadius: size * 0.03, yRadius: size * 0.03)
    NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.62, alpha: 0.95).setFill()
    accent.fill()

    for offset in [0.11, 0.20, 0.29] {
        let lineRect = NSRect(
            x: viewerRect.minX + size * 0.09,
            y: viewerRect.minY + size * offset,
            width: viewerRect.width - size * 0.18,
            height: size * 0.028
        )
        let line = NSBezierPath(roundedRect: lineRect, xRadius: size * 0.014, yRadius: size * 0.014)
        NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.44, alpha: 0.88).setFill()
        line.fill()
    }

    let sparklePath = NSBezierPath()
    let sparkleCenter = CGPoint(x: outerRect.maxX - size * 0.16, y: outerRect.maxY - size * 0.16)
    sparklePath.move(to: CGPoint(x: sparkleCenter.x, y: sparkleCenter.y + size * 0.06))
    sparklePath.line(to: CGPoint(x: sparkleCenter.x, y: sparkleCenter.y - size * 0.06))
    sparklePath.move(to: CGPoint(x: sparkleCenter.x - size * 0.06, y: sparkleCenter.y))
    sparklePath.line(to: CGPoint(x: sparkleCenter.x + size * 0.06, y: sparkleCenter.y))
    sparklePath.lineWidth = max(3, size * 0.015)
    sparklePath.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.95).setStroke()
    sparklePath.stroke()

    return image
}

do {
    try? fileManager.removeItem(at: iconsetURL)
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for (name, size) in variants {
        let image = appIconImage(size: size)
        try savePNG(image: image, to: iconsetURL.appendingPathComponent(name))
    }

    try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "AppIcon", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: "iconutil が失敗しました"
        ])
    }
} catch {
    fputs("App icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

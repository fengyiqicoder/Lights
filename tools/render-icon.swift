#!/usr/bin/env swift
// Render Lights app icon at all macOS iconset sizes via Core Graphics.
// Output: AppIcon.iconset/ (run `iconutil -c icns AppIcon.iconset` afterward).

import AppKit
import CoreGraphics

struct Palette {
    let bright: CGColor
    let base: CGColor
    let dark: CGColor
    let glow: CGColor

    static func cg(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    static let red = Palette(
        bright: cg(1.00, 0.50, 0.50),
        base:   cg(0.98, 0.28, 0.28),
        dark:   cg(0.70, 0.10, 0.10),
        glow:   cg(1.00, 0.30, 0.30)
    )
    static let yellow = Palette(
        bright: cg(1.00, 0.95, 0.50),
        base:   cg(1.00, 0.80, 0.20),
        dark:   cg(0.78, 0.55, 0.05),
        glow:   cg(1.00, 0.82, 0.25)
    )
    static let green = Palette(
        bright: cg(0.55, 1.00, 0.60),
        base:   cg(0.25, 0.88, 0.42),
        dark:   cg(0.06, 0.55, 0.20),
        glow:   cg(0.30, 0.92, 0.45)
    )
}

func renderIcon(size: Int) -> Data {
    let S = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

    // === Housing ===
    let margin = S * 0.06
    let housingRect = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
    let housingRadius = housingRect.width * 0.2237   // macOS Big Sur squircle ratio
    let housingPath = CGPath(roundedRect: housingRect,
                             cornerWidth: housingRadius, cornerHeight: housingRadius,
                             transform: nil)

    // Background gradient fill
    ctx.saveGState()
    ctx.addPath(housingPath)
    ctx.clip()
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1),
            CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad,
        start: CGPoint(x: 0, y: housingRect.maxY),
        end:   CGPoint(x: 0, y: housingRect.minY),
        options: [])
    ctx.restoreGState()

    // Hairline inner border for polish
    ctx.saveGState()
    ctx.setLineWidth(max(1, S * 0.004))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
    ctx.addPath(housingPath)
    ctx.strokePath()
    ctx.restoreGState()

    // === Three lights, top to bottom ===
    let socketD = housingRect.width * 0.34
    let bulbD = socketD * 0.78
    let totalSpacingHeight = housingRect.height - 3 * socketD
    let spacing = totalSpacingHeight / 4

    let palettes = [Palette.red, Palette.yellow, Palette.green]
    for (i, palette) in palettes.enumerated() {
        // CG origin is bottom-left; iterate top->down
        let cy = housingRect.maxY - spacing - socketD/2 - CGFloat(i) * (socketD + spacing)
        let cx = housingRect.midX
        let socketRect = CGRect(x: cx - socketD/2, y: cy - socketD/2,
                                width: socketD, height: socketD)
        let bulbRect = CGRect(x: cx - bulbD/2, y: cy - bulbD/2,
                              width: bulbD, height: bulbD)

        // Socket well: dark radial
        ctx.saveGState()
        ctx.addEllipse(in: socketRect)
        ctx.clip()
        let socketGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0, green: 0, blue: 0, alpha: 0.85),
                CGColor(red: 0, green: 0, blue: 0, alpha: 0.40)
            ] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(socketGrad,
            startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
            endCenter:   CGPoint(x: cx, y: cy), endRadius: socketD * 0.6,
            options: [])
        ctx.restoreGState()

        // Socket rim
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.setLineWidth(max(0.4, S * 0.0008))
        ctx.strokeEllipse(in: socketRect)
        ctx.restoreGState()

        // Outer glow halo (far)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: bulbD * 1.0,
                      color: CGColor(red: palette.glow.components![0],
                                     green: palette.glow.components![1],
                                     blue: palette.glow.components![2],
                                     alpha: 0.45))
        ctx.setFillColor(palette.base)
        ctx.fillEllipse(in: bulbRect)
        ctx.restoreGState()

        // Inner glow halo (close)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: bulbD * 0.5,
                      color: CGColor(red: palette.glow.components![0],
                                     green: palette.glow.components![1],
                                     blue: palette.glow.components![2],
                                     alpha: 0.85))
        ctx.setFillColor(palette.base)
        ctx.fillEllipse(in: bulbRect)
        ctx.restoreGState()

        // Bulb body: radial gradient bright→base→dark, off-center highlight
        ctx.saveGState()
        ctx.addEllipse(in: bulbRect)
        ctx.clip()
        let bulbGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [palette.bright, palette.base, palette.dark] as CFArray,
            locations: [0, 0.55, 1])!
        let hlCenter = CGPoint(x: cx - bulbD * 0.18, y: cy + bulbD * 0.20)
        ctx.drawRadialGradient(bulbGrad,
            startCenter: hlCenter, startRadius: 0.5,
            endCenter:   CGPoint(x: cx, y: cy), endRadius: bulbD * 0.7,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

        // Specular highlight (glassy top-left sheen)
        ctx.saveGState()
        let hlRect = bulbRect.insetBy(dx: bulbD * 0.10, dy: bulbD * 0.10)
        ctx.addEllipse(in: hlRect)
        ctx.clip()
        let hlGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0)
            ] as CFArray,
            locations: [0, 1])!
        ctx.drawLinearGradient(hlGrad,
            start: CGPoint(x: hlRect.minX, y: hlRect.maxY),
            end:   CGPoint(x: hlRect.midX, y: hlRect.midY),
            options: [])
        ctx.restoreGState()
    }

    return rep.representation(using: .png, properties: [:])!
}

// === Main ===

let outDir = "AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png",        16),
    ("icon_16x16@2x.png",     32),
    ("icon_32x32.png",        32),
    ("icon_32x32@2x.png",     64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    let data = renderIcon(size: px)
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    try data.write(to: url)
    print("✓ \(name) — \(data.count) bytes")
}

print("\nDone. Convert with: iconutil -c icns \(outDir)")

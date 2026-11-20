#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI

private func rgbaColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

private func makeSquirclePath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .path(in: rect)
        .cgPath
}

private func makeLetterTPath(centeredAt center: CGPoint, targetHeight: CGFloat) -> CGPath? {
    // Use an optical text/subheading point size (44pt) before scaling the vector outline so
    // Apple New York keeps sturdy crossbar joints instead of ultra-thin 560pt display hairlines.
    let baseFont = NSFont.systemFont(ofSize: 44, weight: .bold)
    let font: NSFont
    if let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif),
       let serifFont = NSFont(descriptor: serifDescriptor, size: 44) {
        font = serifFont
    } else if let georgia = NSFont(name: "Georgia-Bold", size: 44) {
        font = georgia
    } else {
        font = baseFont
    }

    let ctFont = font as CTFont
    var chars: [UniChar] = Array("T".utf16)
    var glyphs: [CGGlyph] = [0]
    guard CTFontGetGlyphsForCharacters(ctFont, &chars, &glyphs, chars.count),
          let rawPath = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else {
        return nil
    }

    let bounds = rawPath.boundingBoxOfPath
    guard bounds.height > 0, bounds.width > 0 else { return nil }

    let scale = targetHeight / bounds.height
    var transform = CGAffineTransform.identity
    transform = transform.translatedBy(x: center.x, y: center.y)
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.translatedBy(x: -bounds.midX, y: -bounds.midY)

    return rawPath.copy(using: &transform)
}

private func renderTitizIconPNG(pixelSize: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "TitizIconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap rep"])
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "TitizIconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let ctx = nsContext.cgContext
    let canvasSize = CGFloat(pixelSize)
    let scale = canvasSize / 1024.0
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squirclePath = makeSquirclePath(in: squircleRect, cornerRadius: 185.4)

    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // 1. Ambient macOS icon drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14 * scale),
        blur: 28 * scale,
        color: rgbaColor(18, 6, 8, 0.30)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(rgbaColor(112, 45, 56))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Broken burgundy (#702D38) vertical tonal surface clipped inside squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let tileColors = [
        rgbaColor(128, 53, 66),   // Top: #803542
        rgbaColor(112, 45, 56),   // Mid: #702D38
        rgbaColor(88, 33, 43)     // Bottom: #58212B
    ] as CFArray
    if let tileGradient = CGGradient(colorsSpace: colorSpace, colors: tileColors, locations: [0.0, 0.48, 1.0]) {
        ctx.drawLinearGradient(
            tileGradient,
            start: CGPoint(x: 512, y: 924),
            end: CGPoint(x: 512, y: 100),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Subtle top soft ambient highlight for macOS depth
    let glowColors = [
        rgbaColor(166, 82, 96, 0.16),
        rgbaColor(166, 82, 96, 0.0)
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glowGradient,
            startCenter: CGPoint(x: 512, y: 840),
            startRadius: 0,
            endCenter: CGPoint(x: 512, y: 740),
            endRadius: 560,
            options: [.drawsAfterEndLocation]
        )
    }

    // 3. Delicate inner specular rim bezel along the squircle contour
    let bezelBand = squirclePath.copy(
        strokingWithWidth: 3.0,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 10.0
    )
    ctx.saveGState()
    ctx.addPath(bezelBand)
    ctx.clip()
    let rimColors = [
        rgbaColor(247, 243, 236, 0.24),
        rgbaColor(247, 243, 236, 0.04),
        rgbaColor(36, 11, 16, 0.28)
    ] as CFArray
    if let rimGradient = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(
            rimGradient,
            start: CGPoint(x: 512, y: 924),
            end: CGPoint(x: 512, y: 100),
            options: []
        )
    }
    ctx.restoreGState()

    // 4. Sculpted New York serif "T" in broken marble white (#EFEAE1)
    if let letterPath = makeLetterTPath(centeredAt: CGPoint(x: 512, y: 506), targetHeight: 462) {
        // Warm deep shadow beneath the marble letterform
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10 * scale),
            blur: 18 * scale,
            color: rgbaColor(38, 10, 16, 0.36)
        )
        ctx.addPath(letterPath)
        ctx.setFillColor(rgbaColor(239, 234, 225))
        ctx.fillPath()
        ctx.restoreGState()

        // Broken marble white vertical gradient fill
        let letterBounds = letterPath.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(letterPath)
        ctx.clip()

        let marbleColors = [
            rgbaColor(247, 243, 236), // Top: #F7F3EC
            rgbaColor(239, 234, 225), // Mid: #EFEAE1
            rgbaColor(227, 220, 208)  // Bottom: #E3DCD0
        ] as CFArray
        if let marbleGradient = CGGradient(colorsSpace: colorSpace, colors: marbleColors, locations: [0.0, 0.48, 1.0]) {
            ctx.drawLinearGradient(
                marbleGradient,
                start: CGPoint(x: letterBounds.midX, y: letterBounds.maxY),
                end: CGPoint(x: letterBounds.midX, y: letterBounds.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Crisp subtle top light bevel inside the T outline
        let letterHighlightBand = letterPath.copy(
            strokingWithWidth: 2.2,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10.0
        )
        ctx.addPath(letterHighlightBand)
        ctx.clip()
        let bevelColors = [
            rgbaColor(255, 255, 255, 0.35),
            rgbaColor(255, 255, 255, 0.0)
        ] as CFArray
        if let bevelGradient = CGGradient(colorsSpace: colorSpace, colors: bevelColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                bevelGradient,
                start: CGPoint(x: letterBounds.midX, y: letterBounds.maxY),
                end: CGPoint(x: letterBounds.midX, y: letterBounds.midY),
                options: []
            )
        }
        ctx.restoreGState()
    }

    ctx.restoreGState() // unclip squircle
    ctx.restoreGState() // unscale

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TitizIconGen", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try pngData.write(to: url, options: .atomic)
}

let scriptURL = URL(fileURLWithPath: #filePath)
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsURL = rootURL.appendingPathComponent("assets", isDirectory: true)
let iconsetURL = assetsURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let readmeLogoURL = assetsURL.appendingPathComponent("titiz-logo.png")
let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")

let fm = FileManager.default
try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)
if fm.fileExists(atPath: iconsetURL.path) {
    try fm.removeItem(at: iconsetURL)
}
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// Master 1024x1024 logo PNG for GitHub README and documentation
try renderTitizIconPNG(pixelSize: 1024, to: readmeLogoURL)

// All 10 standard macOS .iconset sizes rendered cleanly from vector shapes
let iconsetSpecs: [(filename: String, pixels: Int)] = [
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

for spec in iconsetSpecs {
    try renderTitizIconPNG(
        pixelSize: spec.pixels,
        to: iconsetURL.appendingPathComponent(spec.filename)
    )
}

if fm.fileExists(atPath: icnsURL.path) {
    try fm.removeItem(at: icnsURL)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
let errPipe = Pipe()
process.standardError = errPipe
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    fputs("iconutil failed: \(errText)\n", stderr)
    exit(1)
}

try fm.removeItem(at: iconsetURL)
print("Generated \(readmeLogoURL.path) and \(icnsURL.path)")

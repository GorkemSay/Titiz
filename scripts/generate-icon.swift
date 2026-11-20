#!/usr/bin/env swift

import AppKit
import CoreGraphics
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

private func addPillPath(_ path: CGMutablePath, rect: CGRect, radius: CGFloat? = nil) {
    let r = radius ?? min(rect.width, rect.height) * 0.5
    path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
}

/// Builds the counter-clockwise vertical shaft + curved Ionic capital cushion + neck contour.
private func makeShaftAndCapitalBodyPath() -> CGPath {
    let path = CGMutablePath()
    // Base junction (y = 322, halfWidth = 74) -> subtle classical entasis up to neck (y = 616, halfWidth = 64)
    path.move(to: CGPoint(x: 438, y: 322))
    path.addLine(to: CGPoint(x: 586, y: 322))

    // Right flank of shaft with subtle outward entasis
    path.addCurve(
        to: CGPoint(x: 576, y: 616),
        control1: CGPoint(x: 586, y: 420),
        control2: CGPoint(x: 580, y: 530)
    )
    // Flair outward smoothly into the extended Ionic volutes forming the T crossbar
    path.addCurve(
        to: CGPoint(x: 698, y: 604),
        control1: CGPoint(x: 592, y: 644),
        control2: CGPoint(x: 642, y: 610)
    )
    path.addLine(to: CGPoint(x: 698, y: 740))
    path.addLine(to: CGPoint(x: 326, y: 740))
    path.addLine(to: CGPoint(x: 326, y: 604))
    // Mirror flair from the left volute back into the left column neck
    path.addCurve(
        to: CGPoint(x: 448, y: 616),
        control1: CGPoint(x: 382, y: 610),
        control2: CGPoint(x: 432, y: 644)
    )
    // Left flank of shaft descending to base
    path.addCurve(
        to: CGPoint(x: 438, y: 322),
        control1: CGPoint(x: 444, y: 530),
        control2: CGPoint(x: 438, y: 420)
    )
    path.closeSubpath()
    return path
}

/// Unified counter-clockwise silhouette of the Ionic Marble Column "T":
/// abacus slab, twin extended inward-curling volutes, necking collar, entasis shaft, and Attic stepped base.
private func makeIonicColumnTSilhouette() -> CGPath {
    let silhouette = CGMutablePath()

    // Main shaft + capital bridge
    silhouette.addPath(makeShaftAndCapitalBodyPath())

    // Twin extended volute circular medallions extending cleanly beyond the central crown to form T's curled arms
    let voluteRadius: CGFloat = 68
    silhouette.addEllipse(in: CGRect(
        x: 326 - voluteRadius,
        y: 672 - voluteRadius,
        width: voluteRadius * 2,
        height: voluteRadius * 2
    ))
    silhouette.addEllipse(in: CGRect(
        x: 698 - voluteRadius,
        y: 672 - voluteRadius,
        width: voluteRadius * 2,
        height: voluteRadius * 2
    ))

    // Refined central Ionic abacus molding flush between volute centers (`x: 326...698`) so there are no detached corner wedges
    addPillPath(silhouette, rect: CGRect(x: 324, y: 738, width: 376, height: 22), radius: 7)

    // Astragal / necking collar bridging the capital to the column shaft
    addPillPath(silhouette, rect: CGRect(x: 432, y: 612, width: 160, height: 22), radius: 11)

    // Attic stepped pedestal base forming the grounded serif foot of T
    addPillPath(silhouette, rect: CGRect(x: 424, y: 304, width: 176, height: 22), radius: 11)
    addPillPath(silhouette, rect: CGRect(x: 434, y: 284, width: 156, height: 22), radius: 7)
    addPillPath(silhouette, rect: CGRect(x: 396, y: 260, width: 232, height: 28), radius: 7)

    return silhouette
}

/// Builds a closed tapered groove ribbon that glides horizontally from center along the top canalis
/// and spirals inward 2.15 turns into the volute eye (`mirrored` flips across `x = 512`).
private func makeVoluteSpiralGroovePath(mirrored: Bool) -> CGPath {
    let center = CGPoint(x: 326, y: 672)
    var samples: [(point: CGPoint, halfWidth: CGFloat)] = []

    // 1. Horizontal entry along top of the canalis (x = 512 -> 326, y = 724)
    let bridgeSteps = 18
    for i in 0..<bridgeSteps {
        let t = CGFloat(i) / CGFloat(bridgeSteps)
        let x = 512 - t * (512 - 328)
        let y: CGFloat = 724
        samples.append((CGPoint(x: x, y: y), 4.8))
    }

    // 2. Smooth inward spiral around left volute center (theta = pi/2 .. pi/2 + 2.08 * 2pi)
    let spiralSteps = 160
    let startAngle = CGFloat.pi * 0.5
    let totalSweep = CGFloat.pi * 2.0 * 2.08
    let rStart: CGFloat = 52.0
    let rEnd: CGFloat = 10.5

    for i in 0...spiralSteps {
        let u = CGFloat(i) / CGFloat(spiralSteps)
        let angle = startAngle + u * totalSweep
        // Slightly front-loaded contraction gives classic balanced scroll spacing
        let r = rStart * pow(rEnd / rStart, pow(u, 0.96))
        let pt = CGPoint(
            x: center.x + r * cos(angle),
            y: center.y + r * sin(angle)
        )
        let halfW = 4.8 - u * 2.3
        samples.append((pt, halfW))
    }

    var leftEdge: [CGPoint] = []
    var rightEdge: [CGPoint] = []
    leftEdge.reserveCapacity(samples.count)
    rightEdge.reserveCapacity(samples.count)

    for idx in samples.indices {
        let p = samples[idx].point
        let prev = samples[max(0, idx - 1)].point
        let next = samples[min(samples.count - 1, idx + 1)].point
        let dx = next.x - prev.x
        let dy = next.y - prev.y
        let len = max(0.0001, hypot(dx, dy))
        let nx = -dy / len
        let ny = dx / len
        let w = samples[idx].halfWidth
        leftEdge.append(CGPoint(x: p.x + nx * w, y: p.y + ny * w))
        rightEdge.append(CGPoint(x: p.x - nx * w, y: p.y - ny * w))
    }

    func mapPoint(_ p: CGPoint) -> CGPoint {
        mirrored ? CGPoint(x: 1024 - p.x, y: p.y) : p
    }

    let path = CGMutablePath()
    guard let firstL = leftEdge.first else { return path }
    path.move(to: mapPoint(firstL))
    for p in leftEdge.dropFirst() {
        path.addLine(to: mapPoint(p))
    }
    for p in rightEdge.reversed() {
        path.addLine(to: mapPoint(p))
    }
    path.closeSubpath()
    return path
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

    // 4. Sculpted Ionic Greek marble column forming "T" in broken marble white (#EFEAE1)
    let columnSilhouette = makeIonicColumnTSilhouette()
    let columnBounds = columnSilhouette.boundingBoxOfPath

    // Warm burgundy drop shadow beneath unified column silhouette
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10 * scale),
        blur: 18 * scale,
        color: rgbaColor(36, 9, 15, 0.38)
    )
    ctx.addPath(columnSilhouette)
    ctx.setFillColor(rgbaColor(239, 234, 225))
    ctx.fillPath(using: .winding)
    ctx.restoreGState()

    // Clip to column silhouette and render marble surface + carved architectural details
    ctx.saveGState()
    ctx.addPath(columnSilhouette)
    ctx.clip(using: .winding)

    let marbleColors = [
        rgbaColor(248, 244, 237), // Top: #F8F4ED
        rgbaColor(239, 234, 225), // Mid: #EFEAE1
        rgbaColor(223, 215, 202)  // Bottom: #DFD7CA
    ] as CFArray
    if let marbleGradient = CGGradient(colorsSpace: colorSpace, colors: marbleColors, locations: [0.0, 0.48, 1.0]) {
        ctx.drawLinearGradient(
            marbleGradient,
            start: CGPoint(x: columnBounds.midX, y: columnBounds.maxY),
            end: CGPoint(x: columnBounds.midX, y: columnBounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Subtle cylindrical 3D curvature shading restricted strictly to the vertical shaft
    let cylinderColors = [
        rgbaColor(196, 184, 170, 0.24),
        rgbaColor(255, 255, 255, 0.14),
        rgbaColor(196, 184, 170, 0.24)
    ] as CFArray
    if let cylinderGradient = CGGradient(colorsSpace: colorSpace, colors: cylinderColors, locations: [0.0, 0.45, 1.0]) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 420, y: 324, width: 184, height: 292))
        ctx.drawLinearGradient(
            cylinderGradient,
            start: CGPoint(x: 432, y: 470),
            end: CGPoint(x: 592, y: 470),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }

    // Horizontal architectural molding creases (abacus seam, lower canalis curve, collar & base tiers)
    let grooveColor = rgbaColor(106, 40, 51, 0.56)
    let softGrooveColor = rgbaColor(106, 40, 51, 0.42)

    // Center abacus underside seam seamlessly blending into both volute tops
    ctx.setStrokeColor(softGrooveColor)
    ctx.setLineWidth(4.0)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 332, y: 738))
    ctx.addLine(to: CGPoint(x: 692, y: 738))
    ctx.strokePath()

    // Graceful cushioned lower canalis arch connecting the lower volute curls smoothly across center
    ctx.setStrokeColor(softGrooveColor)
    ctx.setLineWidth(4.0)
    ctx.move(to: CGPoint(x: 374, y: 650))
    ctx.addCurve(
        to: CGPoint(x: 650, y: 650),
        control1: CGPoint(x: 448, y: 662),
        control2: CGPoint(x: 576, y: 662)
    )
    ctx.strokePath()

    // Necking / astragal molding grooves bridging capital to shaft
    for grooveY in [CGFloat(634), CGFloat(612)] {
        ctx.setStrokeColor(grooveColor)
        ctx.setLineWidth(4.0)
        ctx.move(to: CGPoint(x: 444, y: grooveY))
        ctx.addLine(to: CGPoint(x: 580, y: grooveY))
        ctx.strokePath()
    }

    // Attic stepped base tier seams (inset inside rounded corners)
    ctx.setStrokeColor(softGrooveColor)
    ctx.setLineWidth(3.8)
    ctx.move(to: CGPoint(x: 436, y: 324))
    ctx.addLine(to: CGPoint(x: 588, y: 324))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: 438, y: 304))
    ctx.addLine(to: CGPoint(x: 586, y: 304))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: 440, y: 286))
    ctx.addLine(to: CGPoint(x: 584, y: 286))
    ctx.strokePath()

    // Twin inward-curling Ionic volute spirals extending outward as T arms
    let spiralFill = rgbaColor(104, 38, 49, 0.78)
    for isMirrored in [false, true] {
        let spiralPath = makeVoluteSpiralGroovePath(mirrored: isMirrored)
        ctx.addPath(spiralPath)
        ctx.setFillColor(spiralFill)
        ctx.fillPath()

        // Carved circular eye (oculus) at the heart of each spiral
        let eyeCenterX: CGFloat = isMirrored ? (1024 - 326) : 326
        let eyeRadius: CGFloat = 10.5
        let eyeRect = CGRect(
            x: eyeCenterX - eyeRadius,
            y: 672 - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        )
        ctx.setFillColor(spiralFill)
        ctx.fillEllipse(in: eyeRect)
    }

    // 4 carved vertical marble flutes (concave channels along shaft)
    let fluteOffsets: [(x: CGFloat, halfWidth: CGFloat)] = [
        (-45, 8.5),
        (-15.5, 9.5),
        (15.5, 9.5),
        (45, 8.5)
    ]
    let fluteColors = [
        rgbaColor(108, 43, 54, 0.42),
        rgbaColor(166, 138, 132, 0.18),
        rgbaColor(255, 255, 255, 0.25)
    ] as CFArray
    if let fluteGradient = CGGradient(colorsSpace: colorSpace, colors: fluteColors, locations: [0.0, 0.55, 1.0]) {
        for flute in fluteOffsets {
            let fx = 512 + flute.x
            let fluteRect = CGRect(
                x: fx - flute.halfWidth,
                y: 342,
                width: flute.halfWidth * 2,
                height: 254
            )
            let flutePath = CGPath(
                roundedRect: fluteRect,
                cornerWidth: flute.halfWidth,
                cornerHeight: flute.halfWidth,
                transform: nil
            )
            ctx.saveGState()
            ctx.addPath(flutePath)
            ctx.clip()
            ctx.drawLinearGradient(
                fluteGradient,
                start: CGPoint(x: fluteRect.minX, y: fluteRect.midY),
                end: CGPoint(x: fluteRect.maxX, y: fluteRect.midY),
                options: []
            )
            ctx.restoreGState()
        }
    }

    ctx.restoreGState() // unclip column silhouette

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

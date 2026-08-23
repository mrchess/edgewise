// Builds Edgewise's .icns.
//
// Uses Assets/AppIcon.png when present, and otherwise draws a placeholder mark so the
// repo always builds a complete app bundle without carrying binary assets.
//
// A supplied source that is fully opaque is treated as artwork needing macOS
// treatment: it gets inset and clipped to the system squircle, matching how every
// first-party icon sits on the canvas. A source with transparency is assumed to be
// already shaped and is used as-is.
import AppKit

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "AppIcon.icns"
let sourcePath = arguments.count > 2 ? arguments[2] : "Assets/AppIcon.png"

// MARK: - Squircle

/// Apple's icon silhouette is a continuous-curvature rounded rectangle, not a plain
/// one. `NSBezierPath` has no continuous-corner API, so this approximates it with the
/// same cubic construction Core Animation uses.
func squircle(in rect: NSRect) -> NSBezierPath {
    let radius = rect.width * 0.2237   // macOS icon corner ratio
    let limit = min(rect.width, rect.height) / 2
    let r = min(radius, limit)
    let k = r * 0.1288                 // continuous-curvature control offset

    let path = NSBezierPath()
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

    path.move(to: NSPoint(x: minX + r, y: minY))
    path.line(to: NSPoint(x: maxX - r, y: minY))
    path.curve(to: NSPoint(x: maxX, y: minY + r),
               controlPoint1: NSPoint(x: maxX - k, y: minY),
               controlPoint2: NSPoint(x: maxX, y: minY + k))
    path.line(to: NSPoint(x: maxX, y: maxY - r))
    path.curve(to: NSPoint(x: maxX - r, y: maxY),
               controlPoint1: NSPoint(x: maxX, y: maxY - k),
               controlPoint2: NSPoint(x: maxX - k, y: maxY))
    path.line(to: NSPoint(x: minX + r, y: maxY))
    path.curve(to: NSPoint(x: minX, y: maxY - r),
               controlPoint1: NSPoint(x: minX + k, y: maxY),
               controlPoint2: NSPoint(x: minX, y: maxY - k))
    path.line(to: NSPoint(x: minX, y: minY + r))
    path.curve(to: NSPoint(x: minX + r, y: minY),
               controlPoint1: NSPoint(x: minX, y: minY + k),
               controlPoint2: NSPoint(x: minX + k, y: minY))
    path.close()
    return path
}

// MARK: - Placeholder artwork

func drawPlaceholder(size: CGFloat) {
    let s = size / 1024
    let full = NSRect(x: 0, y: 0, width: size, height: size)
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
               ending:   NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!
        .draw(in: squircle(in: full), angle: -90)

    let stripW = 720 * s, stripH = 202 * s
    let strip = NSRect(x: (size - stripW) / 2, y: (size - stripH) / 2,
                       width: stripW, height: stripH)
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: strip, xRadius: 20 * s, yRadius: 20 * s).fill()
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    let border = NSBezierPath(roundedRect: strip, xRadius: 20 * s, yRadius: 20 * s)
    border.lineWidth = 3 * s
    border.stroke()

    let centre = NSPoint(x: strip.midX + 150 * s, y: strip.midY)
    for (index, radius) in [58, 96, 138].enumerated() {
        NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 0.36 - Double(index) * 0.11)
            .setStroke()
        let r = CGFloat(radius) * s
        let ring = NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r,
                                               width: r * 2, height: r * 2))
        ring.lineWidth = 7 * s
        ring.stroke()
    }
    NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 1).setFill()
    let dot: CGFloat = 34 * s
    NSBezierPath(ovalIn: NSRect(x: centre.x - dot, y: centre.y - dot,
                                width: dot * 2, height: dot * 2)).fill()
}

// MARK: - Rendering

let source = NSImage(contentsOfFile: sourcePath)
if source != nil {
    print("using artwork from \(sourcePath)")
} else {
    print("no artwork at \(sourcePath) — drawing placeholder")
}

/// True when every pixel is opaque, meaning the artwork is a full-bleed square that
/// still needs to be inset and clipped to the icon silhouette.
func isFullyOpaque(_ image: NSImage) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return true }
    guard rep.hasAlpha else { return true }
    let stepX = max(rep.pixelsWide / 32, 1), stepY = max(rep.pixelsHigh / 32, 1)
    for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent < 0.99 {
                return false
            }
        }
    }
    return true
}

let needsShaping = source.map(isFullyOpaque) ?? false
if needsShaping { print("artwork is opaque — insetting and clipping to the icon shape") }

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size),
        pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    if let source {
        if needsShaping {
            // macOS icon artwork occupies ~82% of the canvas, centred.
            let inset = size * 0.09
            let box = NSRect(x: inset, y: inset,
                             width: size - inset * 2, height: size - inset * 2)
            NSGraphicsContext.saveGraphicsState()
            squircle(in: box).addClip()
            source.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
    } else {
        drawPlaceholder(size: size)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Edgewise-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    try! render(size: CGFloat(size))
        .write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("icon written to \(output)")

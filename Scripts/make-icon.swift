// Builds Edgewise's .icns.
//
// Uses Assets/AppIcon.png when present, and otherwise draws a placeholder mark so the
// repo always builds a complete app bundle without carrying binary assets.
//
// Supplied artwork is usually a full-bleed square with the rounded icon silhouette
// already drawn in and the corners filled with flat colour. Drawing that as-is leaves
// hard corner blocks; clipping it to a silhouette of our own leaves dark crescents
// wherever the two radii disagree. So the artwork's own corner radius is measured and
// used as the clip, which matches its shape exactly.
import AppKit

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "AppIcon.icns"
let sourcePath = arguments.count > 2 ? arguments[2] : "Assets/AppIcon.png"

// MARK: - Icon silhouette

/// Apple's icon shape is a continuous-curvature rounded rectangle, not a plain one.
/// `NSBezierPath` has no continuous-corner API, so this approximates it with the same
/// cubic construction Core Animation uses.
///
/// `cornerRatio` is the corner radius as a fraction of the width. Apple's own icons
/// use 0.2237; artwork with a different radius passes its own.
func squircle(in rect: NSRect, cornerRatio: CGFloat = 0.2237) -> NSBezierPath {
    let r = min(rect.width * cornerRatio, min(rect.width, rect.height) / 2)
    let k = r * 0.1288   // continuous-curvature control-point offset

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

// MARK: - Artwork inspection

/// The corner radius the artist drew, as a fraction of the image width.
///
/// Along the very top row of a rounded rectangle the shape's flat edge begins exactly
/// one radius in from the left, so scanning that row inward locates the radius.
///
/// The subtlety is what counts as "the shape". Icon art is usually drawn with a soft
/// shadow or vignette outside the silhouette, so the first pixel that merely *differs*
/// from the corner colour lands partway into that shadow and measures the radius far
/// too small — which then leaves a dark crescent when used as a clip. Instead this
/// scans for the point where the pixel arrives at the artwork's own interior colour,
/// which is the true edge of the solid shape.
///
/// Returns nil when the row never resolves, meaning the artwork is not a rounded
/// shape sitting on a flat ground.
func measuredCornerRatio(of rep: NSBitmapImageRep) -> CGFloat? {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    guard width > 16, height > 16 else { return nil }

    // A row just inside the top edge, and the interior colour along it.
    let probeY = max(height / 40, 2)
    guard let interior = rep.colorAt(x: width / 2, y: probeY),
          let corner = rep.colorAt(x: 0, y: 0) else { return nil }

    // If the corner already matches the interior there is no distinct shape to find.
    let cornerDelta = abs(corner.redComponent - interior.redComponent)
        + abs(corner.greenComponent - interior.greenComponent)
        + abs(corner.blueComponent - interior.blueComponent)
    guard cornerDelta > 0.05 else { return nil }

    func reachedInterior(_ x: Int) -> Bool {
        guard let colour = rep.colorAt(x: x, y: probeY) else { return false }
        return abs(colour.redComponent - interior.redComponent) < 0.035
            && abs(colour.greenComponent - interior.greenComponent) < 0.035
            && abs(colour.blueComponent - interior.blueComponent) < 0.035
    }

    var x = 0
    while x < width / 2, !reachedInterior(x) { x += 1 }
    guard x > 0, x < width / 2 else { return nil }

    // The probe row sits slightly below the top edge, so the shape has already begun
    // curving inward there and x slightly overstates the radius — which is the safe
    // direction to err: a marginally rounder clip removes shadow rather than leaving it.
    return CGFloat(x) / CGFloat(width)
}

/// True when every sampled pixel is opaque, meaning the artwork is a full-bleed square
/// rather than something already cut out with an alpha channel.
func isFullyOpaque(_ rep: NSBitmapImageRep) -> Bool {
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

// MARK: - Set-up

let source = NSImage(contentsOfFile: sourcePath)
let sourceRep: NSBitmapImageRep? = source
    .flatMap(\.tiffRepresentation)
    .flatMap(NSBitmapImageRep.init(data:))

/// Nil when the artwork already carries its own alpha and should be drawn untouched.
let clipRatio: CGFloat? = {
    guard let sourceRep, isFullyOpaque(sourceRep) else { return nil }
    let measured = measuredCornerRatio(of: sourceRep)
    if let measured {
        print(String(format: "artwork corner radius measured at %.1f%% of width", measured * 100))
    } else {
        print("could not measure a corner radius — using the standard macOS silhouette")
    }
    return measured ?? 0.2237
}()

if source == nil {
    print("no artwork at \(sourcePath) — drawing placeholder")
} else {
    print("using artwork from \(sourcePath)")
    if clipRatio == nil { print("artwork has an alpha channel — drawing it as-is") }
}

// MARK: - Rendering

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size),
        pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    if let source {
        // macOS icon artwork occupies ~82% of its canvas, centred, leaving the
        // breathing room every first-party icon has in the Dock.
        let inset = size * 0.09
        let box = NSRect(x: inset, y: inset,
                         width: size - inset * 2, height: size - inset * 2)

        if let clipRatio {
            NSGraphicsContext.saveGraphicsState()
            // Clipping at the artwork's own measured radius follows the silhouette it
            // was drawn with, so no flat corner colour survives and no gap opens up.
            squircle(in: box, cornerRatio: clipRatio).addClip()
            source.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            source.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
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

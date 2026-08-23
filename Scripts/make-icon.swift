// Builds Edgewise's .icns.
//
// Uses Assets/AppIcon.png when present, and otherwise draws a placeholder mark so the
// repo always builds a complete app bundle without carrying binary assets.
//
// Artwork should be a full-bleed square — flat to all four edges, with no rounded
// silhouette and no shadow of its own. The rounding is ours to apply, because only we
// know the exact silhouette macOS expects.
//
// This matters more than it sounds. Art that arrives with its own corners already drawn
// has to agree with our clip to the pixel, and it never does: clip a touch tighter than
// the artist drew and their corner colour survives as a dark crescent, clip a touch
// looser and a sliver of shadow shows. Measuring the artwork's radius to reconcile the
// two does not rescue it either, because a soft shadow makes the edge a gradient rather
// than a boundary and the measurement swings wildly with the threshold. So the rule is
// simply that the artwork must be full-bleed; anything else is flagged for the artist to
// fix rather than papered over here.
import AppKit

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "AppIcon.icns"
let sourcePath = arguments.count > 2 ? arguments[2] : "Assets/AppIcon.png"

// MARK: - Icon silhouette

/// Apple's icon shape is a continuous-curvature rounded rectangle — a squircle — not a
/// plain one. The difference is that curvature ramps up gradually instead of jumping
/// from zero to 1/r the instant the straight edge ends, so there is no visible kink
/// where edge meets corner. `NSBezierPath` has no continuous-corner API, so each corner
/// is built from the three cubics that are the standard approximation of that shape.
///
/// A single arc-like cubic per corner cannot express this: it has one span in which to
/// both turn ninety degrees and blend its curvature at either end, and it can only do
/// one of the two. Three segments split the job — a long shallow lead-in, a tight turn,
/// and a mirrored lead-out — which is why the constants below come in a symmetric pair
/// of ramps rather than a single control-point offset.
///
/// The corner therefore *begins* 1.5287·r back from the elbow, well before a circular
/// corner of the same nominal radius would, and hugs the edge for most of that run. Get
/// this wrong in the tightening direction and the shape reads as a rounded square with
/// a crease at each corner, most obviously at 128px and 256px where the corner is a few
/// dozen pixels across — big enough to see the crease, small enough that it dominates.
///
/// `cornerRatio` is the radius as a fraction of the width; Apple's icons use 0.2237.
func squircle(in rect: NSRect, cornerRatio: CGFloat = 0.2237) -> NSBezierPath {
    // Cap the radius so that neighbouring corners cannot overlap: each consumes
    // 1.5287·r of the edge it starts on, so two of them must fit within one side.
    let reach: CGFloat = 1.528665
    let r = min(rect.width * cornerRatio, min(rect.width, rect.height) / (2 * reach))

    let path = NSBezierPath()

    /// Emits one corner. `elbow` is the sharp point the corner replaces; `back` points
    /// from it along the incoming edge and `fwd` along the outgoing one, both unit
    /// vectors. Working in this local frame lets all four corners share one description
    /// instead of four hand-mirrored copies, which is where sign errors used to live.
    func corner(elbow: NSPoint, back: NSPoint, fwd: NSPoint) {
        func p(_ b: CGFloat, _ f: CGFloat) -> NSPoint {
            NSPoint(x: elbow.x + back.x * b * r + fwd.x * f * r,
                    y: elbow.y + back.y * b * r + fwd.y * f * r)
        }
        // Lead-in: leaves the straight edge tangentially and barely departs from it.
        path.line(to: p(1.528665, 0))
        path.curve(to: p(0.631494, 0.074911),
                   controlPoint1: p(1.088493, 0),
                   controlPoint2: p(0.868407, 0))
        // The turn itself, symmetric about the corner's diagonal.
        path.curve(to: p(0.074911, 0.631494),
                   controlPoint1: p(0.372824, 0.169060),
                   controlPoint2: p(0.169060, 0.372824))
        // Lead-out: the mirror image of the lead-in, rejoining the next edge tangentially.
        path.curve(to: p(0, 1.528665),
                   controlPoint1: p(0, 0.868407),
                   controlPoint2: p(0, 1.088493))
    }

    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    let left = NSPoint(x: -1, y: 0), right = NSPoint(x: 1, y: 0)
    let down = NSPoint(x: 0, y: -1), up = NSPoint(x: 0, y: 1)

    // Anticlockwise from the bottom edge. Each `corner` call opens with a `line(to:)`,
    // so the initial `move` only has to reach the first corner's starting point.
    path.move(to: NSPoint(x: minX + r * reach, y: minY))
    corner(elbow: NSPoint(x: maxX, y: minY), back: left, fwd: up)
    corner(elbow: NSPoint(x: maxX, y: maxY), back: down, fwd: left)
    corner(elbow: NSPoint(x: minX, y: maxY), back: right, fwd: down)
    corner(elbow: NSPoint(x: minX, y: minY), back: up, fwd: right)
    path.close()
    return path
}

// MARK: - Artwork inspection

/// True when the artwork looks like it has a silhouette of its own baked in — a rounded
/// shape sitting on a contrasting ground, rather than the flat full-bleed square wanted.
///
/// The test is deliberately crude: compare each corner pixel against one a short step
/// diagonally inward. A silhouette puts a shape boundary between those two points, so
/// they land on opposite sides of it and disagree sharply. Full-bleed art has only its
/// background wash between them and barely moves.
///
/// The step has to be short *and* diagonal. Short, because a long one crosses enough of
/// a graded background to look like a boundary all by itself — sampling an edge midpoint
/// instead of a nearby diagonal point reports this very artwork as silhouetted, purely
/// on the strength of its top-to-bottom gradient. Diagonal, because that is the one
/// direction where a corner boundary is guaranteed to fall between the samples. At 12%
/// of the width the step clears any plausible silhouette edge — a 0.2237-radius squircle
/// crosses the diagonal only 6.5% in — while spanning too little of the canvas for a
/// gradient to fake.
///
/// Note that this only ever decides *whether* a silhouette is present, never how big.
/// Measuring the radius is exactly what could not be made to hold still, since a soft
/// edge returns whatever answer the threshold asks for. A yes/no on a contrast this
/// large is stable in a way a measurement never was, and warning the artist beats
/// clipping to a number nobody trusts.
func hasBakedSilhouette(_ rep: NSBitmapImageRep) -> Bool {
    let w = rep.pixelsWide - 1, h = rep.pixelsHigh - 1
    guard w > 16, h > 16 else { return false }
    let stepX = Int(CGFloat(w) * 0.12), stepY = Int(CGFloat(h) * 0.12)

    func differs(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Bool {
        guard let a = rep.colorAt(x: x, y: y),
              let b = rep.colorAt(x: x + dx, y: y + dy) else { return false }
        let delta = abs(a.redComponent - b.redComponent)
            + abs(a.greenComponent - b.greenComponent)
            + abs(a.blueComponent - b.blueComponent)
        return delta > 0.15
    }

    return differs(0, 0, stepX, stepY)
        || differs(w, 0, -stepX, stepY)
        || differs(w, h, -stepX, -stepY)
        || differs(0, h, stepX, -stepY)
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

/// Whether to impose the macOS silhouette. Artwork carrying its own alpha has already
/// been cut out by the artist, so it is drawn untouched; opaque full-bleed artwork gets
/// clipped, which is the case this script exists to serve.
let shouldClip = sourceRep.map(isFullyOpaque) ?? false

if source == nil {
    print("no artwork at \(sourcePath) — drawing placeholder")
} else {
    print("using artwork from \(sourcePath)")
    if !shouldClip {
        print("artwork has an alpha channel — drawing it as-is")
    } else if let sourceRep, hasBakedSilhouette(sourceRep) {
        // Not fatal: clipping still produces an icon, just one with fringing in the
        // corners where our silhouette and the artist's fail to coincide. Say so
        // loudly, because the defect is easy to miss until it is sitting in the Dock.
        print("warning: \(sourcePath) appears to have its own rounded silhouette baked in.")
        print("warning: supply full-bleed artwork instead — corners may fringe otherwise.")
    }
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

        if shouldClip {
            NSGraphicsContext.saveGraphicsState()
            // Core Graphics antialiases the clip itself, so the artwork's own pixels
            // reach the boundary at full strength and fade only through coverage. That
            // is what keeps the curve clean: nothing is drawn over the edge afterwards,
            // so there is no seam colour to go dark or light against the desktop.
            squircle(in: box).addClip()
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

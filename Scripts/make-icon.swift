// Draws Edgewise's icon: a wide 32:9 strip with a touch point on it.
// Written in code so the repo carries no binary assets.
import AppKit

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon.icns"

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size),
        pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = size / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: 224 * s, yRadius: 224 * s)
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
               ending:   NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!
        .draw(in: bg, angle: -90)

    // The panel: a 32:9 strip.
    let stripW = 720 * s, stripH = 202 * s
    let strip = NSRect(x: (size - stripW) / 2, y: (size - stripH) / 2,
                       width: stripW, height: stripH)
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: strip, xRadius: 20 * s, yRadius: 20 * s).fill()
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    let border = NSBezierPath(roundedRect: strip, xRadius: 20 * s, yRadius: 20 * s)
    border.lineWidth = 3 * s
    border.stroke()

    // Touch point plus its ripple.
    let center = NSPoint(x: strip.midX + 150 * s, y: strip.midY)
    for (index, radius) in [58, 96, 138].enumerated() {
        NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 0.36 - Double(index) * 0.11)
            .setStroke()
        let r = CGFloat(radius) * s
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                               width: r * 2, height: r * 2))
        ring.lineWidth = 7 * s
        ring.stroke()
    }
    NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 1).setFill()
    let dot: CGFloat = 34 * s
    NSBezierPath(ovalIn: NSRect(x: center.x - dot, y: center.y - dot,
                                width: dot * 2, height: dot * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Edgewise-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let data = draw(size: CGFloat(size)).representation(using: .png, properties: [:])!
    try! data.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("icon written to \(output)")

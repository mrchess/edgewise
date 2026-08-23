// Draws the install window background: app on the left, an arrow, Applications on
// the right. Generated in code so the repo carries no binary assets.
//
// Emits a 1x and a 2x PNG; build-app.sh combines them into a multi-resolution TIFF so
// the window looks right on Retina and non-Retina displays alike.
import AppKit

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// Window content size in points. Icon centres sit at y = 172 measured from the top.
let width: CGFloat = 660
let height: CGFloat = 400
let appIconCentre = CGPoint(x: 180, y: 172)
let applicationsCentre = CGPoint(x: 480, y: 172)

func render(scale: CGFloat) -> Data {
    let pixelsWide = Int(width * scale), pixelsHigh = Int(height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)

    // AppKit draws from the bottom-left; convert the top-down centres above.
    func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }
    let appPoint = flip(appIconCentre)
    let applicationsPoint = flip(applicationsCentre)

    // Background gradient, matching the app icon.
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
               ending:   NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // A faint 32:9 strip behind everything — a nod to the panel itself.
    let stripW: CGFloat = 560, stripH = stripW * 9 / 32
    let strip = NSRect(x: (width - stripW) / 2, y: (height - stripH) / 2 - 6,
                       width: stripW, height: stripH)
    NSColor(calibratedWhite: 1, alpha: 0.03).setFill()
    NSBezierPath(roundedRect: strip, xRadius: 14, yRadius: 14).fill()

    // Title.
    let title = "Edgewise"
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.95),
    ]
    let titleSize = title.size(withAttributes: titleAttributes)
    title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 78),
               withAttributes: titleAttributes)

    let subtitle = "Drag Edgewise into your Applications folder"
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.55),
    ]
    let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
    subtitle.draw(at: NSPoint(x: (width - subtitleSize.width) / 2, y: height - 104),
                  withAttributes: subtitleAttributes)

    // Arrow between the two icons, clear of both icon labels.
    let accent = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 0.85)
    accent.setStroke()
    accent.setFill()

    let arrowY = appPoint.y + 4
    let arrowStart = appPoint.x + 78
    let arrowEnd = applicationsPoint.x - 78

    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: arrowStart, y: arrowY))
    shaft.line(to: NSPoint(x: arrowEnd - 16, y: arrowY))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.setLineDash([9, 7], count: 2, phase: 0)
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowEnd, y: arrowY))
    head.line(to: NSPoint(x: arrowEnd - 17, y: arrowY + 10))
    head.line(to: NSPoint(x: arrowEnd - 17, y: arrowY - 10))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
    try! render(scale: scale).write(to: url)
    print("wrote \(url.path)")
}

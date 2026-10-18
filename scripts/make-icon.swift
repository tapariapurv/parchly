// Renders the Inkdown app icon set. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Paper squircle on the macOS icon grid (824pt body, 100pt margin) with a soft shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.28).cgColor)
    NSColor(srgbRed: 0.965, green: 0.955, blue: 0.937, alpha: 1).setFill()
    shape.fill()
    ctx.restoreGState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.985, green: 0.978, blue: 0.962, alpha: 1), NSColor(srgbRed: 0.918, green: 0.902, blue: 0.872, alpha: 1)])!
        .draw(in: body, angle: -90)

    // Faint ruled lines, like a page.
    NSColor(srgbRed: 0.45, green: 0.36, blue: 0.22, alpha: 0.10).setFill()
    for y in stride(from: 250.0, through: 760.0, by: 85.0) { NSRect(x: 190, y: y, width: 644, height: 6).fill() }
    // Tan margin bar (the blockquote accent).
    NSColor(srgbRed: 0.79, green: 0.69, blue: 0.54, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 190, y: 230, width: 16, height: 560), xRadius: 8, yRadius: 8).fill()

    // Ink drop: round base, pointed top.
    let drop = NSBezierPath()
    let c = NSPoint(x: 540, y: 430), r: CGFloat = 190
    drop.move(to: NSPoint(x: c.x, y: 820))
    drop.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + 40, y: 720), controlPoint2: NSPoint(x: c.x + r, y: 600))
    drop.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 180, clockwise: true)
    drop.curve(to: NSPoint(x: c.x, y: 820), controlPoint1: NSPoint(x: c.x - r, y: 600), controlPoint2: NSPoint(x: c.x - 40, y: 720))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(srgbRed: 0.1, green: 0.08, blue: 0.05, alpha: 0.35).cgColor)
    NSGradient(colors: [NSColor(srgbRed: 0.2, green: 0.19, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.07, green: 0.065, blue: 0.06, alpha: 1)])!
        .draw(in: drop, angle: -90)
    ctx.restoreGState()

    // Down arrow knocked out of the drop.
    let arrow = NSBezierPath()
    arrow.lineWidth = 46; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: c.x, y: 560)); arrow.line(to: NSPoint(x: c.x, y: 330))
    arrow.move(to: NSPoint(x: c.x - 92, y: 420)); arrow.line(to: NSPoint(x: c.x, y: 326)); arrow.line(to: NSPoint(x: c.x + 92, y: 420))
    NSColor(srgbRed: 0.965, green: 0.955, blue: 0.937, alpha: 1).setStroke()
    arrow.stroke()
    // Highlight on the drop.
    NSColor(white: 1, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 125, y: c.y + 40, width: 60, height: 110)).fill()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let dir = "App/Assets.xcassets/AppIcon.appiconset"
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
try! #"{"info":{"version":1,"author":"xcode"}}"#.write(toFile: "App/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)

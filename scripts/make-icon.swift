// Renders the Parchly app icon set: a dog-eared parchment page with a serif P and a caret. Run: swift scripts/make-icon.swift
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
    NSColor(srgbRed: 0.93, green: 0.88, blue: 0.79, alpha: 1).setFill()
    shape.fill()
    ctx.restoreGState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.96, green: 0.92, blue: 0.84, alpha: 1), NSColor(srgbRed: 0.86, green: 0.78, blue: 0.64, alpha: 1)])!
        .draw(in: body, angle: -90)

    // A page with a dog-eared corner.
    let page = NSRect(x: 262, y: 200, width: 500, height: 610), fold: CGFloat = 120
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: page.minX + 28, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX - 28, y: page.minY))
    sheet.curve(to: NSPoint(x: page.maxX, y: page.minY + 28), controlPoint1: NSPoint(x: page.maxX - 12, y: page.minY), controlPoint2: NSPoint(x: page.maxX, y: page.minY + 12))
    sheet.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    sheet.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    sheet.line(to: NSPoint(x: page.minX + 28, y: page.maxY))
    sheet.curve(to: NSPoint(x: page.minX, y: page.maxY - 28), controlPoint1: NSPoint(x: page.minX + 12, y: page.maxY), controlPoint2: NSPoint(x: page.minX, y: page.maxY - 12))
    sheet.line(to: NSPoint(x: page.minX, y: page.minY + 28))
    sheet.curve(to: NSPoint(x: page.minX + 28, y: page.minY), controlPoint1: NSPoint(x: page.minX, y: page.minY + 12), controlPoint2: NSPoint(x: page.minX + 12, y: page.minY))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor(srgbRed: 0.35, green: 0.25, blue: 0.1, alpha: 0.28).cgColor)
    NSColor(srgbRed: 1, green: 0.992, blue: 0.976, alpha: 1).setFill()
    sheet.fill()
    ctx.restoreGState()
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold + 10, y: page.maxY - fold + 10))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    NSColor(srgbRed: 0.87, green: 0.82, blue: 0.74, alpha: 1).setFill()
    corner.fill()

    // Serif "P", a caret and two ruled lines of text.
    let font = NSFont(descriptor: NSFont.systemFont(ofSize: 400, weight: .black).fontDescriptor.withDesign(.serif)!, size: 400)!
    let p = NSAttributedString(string: "P", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.094, green: 0.082, blue: 0.075, alpha: 1)])
    let size = p.size()
    p.draw(at: NSPoint(x: page.minX + 70, y: page.minY + 245 - size.height * 0.2))
    NSColor(srgbRed: 0.188, green: 0.478, blue: 0.996, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: page.minX + 330, y: page.minY + 300, width: 22, height: 230), xRadius: 11, yRadius: 11).fill()
    NSColor(srgbRed: 0.79, green: 0.70, blue: 0.58, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: page.minX + 70, y: page.minY + 170, width: 360, height: 22), xRadius: 11, yRadius: 11).fill()
    NSBezierPath(roundedRect: NSRect(x: page.minX + 70, y: page.minY + 110, width: 250, height: 22), xRadius: 11, yRadius: 11).fill()

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

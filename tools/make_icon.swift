import AppKit

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let u = s / 1024
    let cs = CGColorSpaceCreateDeviceRGB()

    let body = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let squircle = CGPath(roundedRect: body, cornerWidth: 190 * u, cornerHeight: 190 * u, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * u), blur: 34 * u, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(squircle); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let ink = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.13, green: 0.12, blue: 0.15, alpha: 1), CGColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ink, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    let glow = CGGradient(colorsSpace: cs, colors: [CGColor(red: 1, green: 0.3, blue: 0.15, alpha: 0.55), CGColor(red: 1, green: 0.3, blue: 0.15, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512 * u, y: 512 * u), startRadius: 0, endCenter: CGPoint(x: 512 * u, y: 512 * u), endRadius: 430 * u, options: [])
    let dots = CGColor(gray: 1, alpha: 0.06)
    ctx.setFillColor(dots)
    var y: CGFloat = body.minY + 30 * u
    while y < body.maxY { var x = body.minX + 30 * u; while x < body.maxX { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 5 * u, height: 5 * u)); x += 52 * u }; y += 52 * u }
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 0.95))
    ctx.setLineWidth(34 * u)
    ctx.strokeEllipse(in: CGRect(x: 512 * u - 250 * u, y: 512 * u - 250 * u, width: 500 * u, height: 500 * u))

    let dot = CGRect(x: 512 * u - 150 * u, y: 512 * u - 150 * u, width: 300 * u, height: 300 * u)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 50 * u, color: CGColor(red: 1, green: 0.3, blue: 0.15, alpha: 0.95))
    ctx.addEllipse(in: dot); ctx.clip()
    let sig = CGGradient(colorsSpace: cs, colors: [CGColor(red: 1, green: 0.58, blue: 0.22, alpha: 1), CGColor(red: 1, green: 0.28, blue: 0.14, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sig, start: CGPoint(x: dot.minX, y: dot.maxY), end: CGPoint(x: dot.maxX, y: dot.minY), options: [])
    ctx.restoreGState()

    let bubble = CGRect(x: 620 * u, y: 190 * u, width: 200 * u, height: 200 * u)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: CGColor(gray: 0, alpha: 0.6))
    ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1)); ctx.fillEllipse(in: bubble.insetBy(dx: -12 * u, dy: -12 * u))
    ctx.restoreGState()
    ctx.setFillColor(CGColor(red: 0.78, green: 1.0, blue: 0.24, alpha: 1)); ctx.fillEllipse(in: bubble)
    let face = bubble
    ctx.saveGState()
    ctx.addEllipse(in: face); ctx.clip()
    ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.02, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: face.midX - 30 * u, y: face.midY + 4 * u, width: 60 * u, height: 60 * u))
    ctx.fillEllipse(in: CGRect(x: face.midX - 70 * u, y: face.minY - 44 * u, width: 140 * u, height: 124 * u))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256), ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] {
    try! draw(size: px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))\(name.contains("@2x") ? "@2x" : "").png"))
}

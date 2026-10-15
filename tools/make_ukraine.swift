import AppKit

let W = 3200, H = 1800
let out = CommandLine.arguments[1]

let blue: UInt32 = 0x0057B7
let navy: UInt32 = 0x003A7A
let sky: UInt32 = 0x2B7FD0
let gold: UInt32 = 0xFFD700
let wheat: UInt32 = 0xFFF0A0

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func render(_ name: String, _ body: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    body(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: "\(out)/\(name).jpg"))
}

func fill(_ ctx: CGContext, _ top: UInt32, _ bottom: UInt32) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(top), c(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)), end: .zero, options: [])
}

func glow(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, hex: UInt32, alpha: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(hex, alpha), c(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

render("23-ukraine-sky") { ctx in
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(blue), c(sky), c(gold)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.82, y: CGFloat(H) * 0.12), radius: 1500, hex: wheat, alpha: 0.55)
}

func waves(_ name: String, bg1: UInt32, bg2: UInt32, line: UInt32, accent: UInt32, count: Int, seed: Double) {
    render(name) { ctx in
        fill(ctx, bg1, bg2)
        ctx.setLineCap(.round)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count)
            ctx.beginPath()
            var x: CGFloat = -20
            while x <= CGFloat(W) + 20 {
                let y0 = CGFloat(H) * (0.1 + 0.8 * t)
                let a1 = sin(Double(x) * 0.0016 + seed + Double(t) * 3.4) * 120
                let a2 = sin(Double(x) * 0.0043 + seed * 2 + Double(t) * 7.0) * 38
                let a3 = sin(Double(x) * 0.0009 - seed) * 210 * Double(t)
                let y = y0 + CGFloat(a1 + a2 + a3)
                if x < 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
                x += 8
            }
            let hi = i % 9 == 0
            ctx.setStrokeColor(hi ? c(accent, 0.95) : c(line, 0.3))
            ctx.setLineWidth(hi ? 4 : 2.2)
            ctx.strokePath()
        }
    }
}

func rings(_ name: String, bg1: UInt32, bg2: UInt32, line: UInt32, accent: UInt32, center: CGPoint, step: CGFloat) {
    render(name) { ctx in
        fill(ctx, bg1, bg2)
        var r = step
        var i = 0
        while r < 4200 {
            let hi = i % 7 == 0
            ctx.setStrokeColor(hi ? c(accent, 0.95) : c(line, 0.26))
            ctx.setLineWidth(hi ? 5 : 2.4)
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            r += step; i += 1
        }
    }
}

func halftone(_ name: String, bg: UInt32, dot: UInt32, accent: UInt32) {
    render(name) { ctx in
        ctx.setFillColor(c(bg)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let step: CGFloat = 54
        var y: CGFloat = step / 2
        var row = 0
        while y < CGFloat(H) {
            var x: CGFloat = (row % 2 == 0) ? step / 2 : step
            while x < CGFloat(W) {
                let d = hypot(x - CGFloat(W) * 0.8, y - CGFloat(H) * 0.8) / hypot(CGFloat(W), CGFloat(H))
                let r = max(1.5, (1 - min(d * 1.7, 1)) * step * 0.46)
                ctx.setFillColor(d < 0.12 ? c(accent) : c(dot, 0.9))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += step
            }
            y += step * 0.866; row += 1
        }
    }
}

func bands(_ name: String, bg: UInt32, colors: [UInt32]) {
    render(name) { ctx in
        ctx.setFillColor(c(bg)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.saveGState()
        ctx.rotate(by: -.pi / 9)
        var x: CGFloat = -900
        var i = 0
        while x < CGFloat(W) + 900 {
            let w: CGFloat = CGFloat([70, 150, 40, 110, 220][i % 5])
            ctx.setFillColor(c(colors[i % colors.count], 0.95))
            ctx.fill(CGRect(x: x, y: -900, width: w, height: CGFloat(H) + 1800))
            x += w + CGFloat([90, 40, 160, 70, 120][i % 5]); i += 1
        }
        ctx.restoreGState()
    }
}

waves("24-ukraine-waves", bg1: navy, bg2: blue, line: gold, accent: wheat, count: 64, seed: 2.7)
rings("25-ukraine-rings", bg1: blue, bg2: navy, line: gold, accent: wheat, center: CGPoint(x: 600, y: 1500), step: 58)
halftone("27-ukraine-halftone", bg: blue, dot: gold, accent: wheat)
bands("28-ukraine-bands", bg: navy, colors: [gold, blue, wheat, sky])

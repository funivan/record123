import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct Blob { var x: Double; var y: Double; var r: Double; var hex: UInt32; var a: Double = 1 }
struct Paper { var name: String; var base: UInt32; var blobs: [Blob]; var twirl: Double = 0.0; var grain: Double = 0.06 }

func col(_ hex: UInt32, _ a: Double = 1) -> CIColor {
    CIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: a)
}

let papers: [Paper] = [
    Paper(name: "01-ember", base: 0x1A0B12, blobs: [Blob(x: 0.15, y: 0.85, r: 0.7, hex: 0xFF5A2E), Blob(x: 0.85, y: 0.2, r: 0.65, hex: 0xD4217A), Blob(x: 0.6, y: 0.7, r: 0.4, hex: 0xFFB347, a: 0.8)], twirl: 0.5),
    Paper(name: "02-dusk", base: 0x10112B, blobs: [Blob(x: 0.2, y: 0.2, r: 0.7, hex: 0x6C4CFF), Blob(x: 0.85, y: 0.75, r: 0.7, hex: 0xFF5FA2), Blob(x: 0.55, y: 0.5, r: 0.45, hex: 0x2B7BFF, a: 0.8)], twirl: 0.6),
    Paper(name: "03-lagoon", base: 0x04202B, blobs: [Blob(x: 0.8, y: 0.25, r: 0.7, hex: 0x12C2B5), Blob(x: 0.2, y: 0.7, r: 0.7, hex: 0x1B5FD6), Blob(x: 0.5, y: 0.45, r: 0.4, hex: 0x4FD8FF, a: 0.8)], twirl: 0.5),
    Paper(name: "04-moss", base: 0x0B1A12, blobs: [Blob(x: 0.25, y: 0.3, r: 0.65, hex: 0x3FBF6B), Blob(x: 0.8, y: 0.8, r: 0.6, hex: 0x0F7A63), Blob(x: 0.7, y: 0.3, r: 0.35, hex: 0xC6FF3D, a: 0.85)], twirl: 0.4),
    Paper(name: "05-cotton", base: 0xFBE9EE, blobs: [Blob(x: 0.2, y: 0.25, r: 0.7, hex: 0xFF9EC0), Blob(x: 0.85, y: 0.35, r: 0.6, hex: 0xC8B6FF), Blob(x: 0.6, y: 0.85, r: 0.6, hex: 0xFFC9A3)], twirl: 0.5, grain: 0.04),
    Paper(name: "06-sand", base: 0xF3EBDD, blobs: [Blob(x: 0.8, y: 0.2, r: 0.65, hex: 0xF4B183), Blob(x: 0.2, y: 0.8, r: 0.65, hex: 0xE8908F), Blob(x: 0.5, y: 0.5, r: 0.45, hex: 0xB9C7A2, a: 0.8)], twirl: 0.4, grain: 0.04),
    Paper(name: "07-ink", base: 0x07070A, blobs: [Blob(x: 0.25, y: 0.3, r: 0.7, hex: 0x3A2E7A), Blob(x: 0.8, y: 0.75, r: 0.6, hex: 0x1E3A8A), Blob(x: 0.55, y: 0.9, r: 0.4, hex: 0x5B1A5E, a: 0.8)], twirl: 0.5),
    Paper(name: "08-citrus", base: 0xFFF3C4, blobs: [Blob(x: 0.15, y: 0.2, r: 0.6, hex: 0xFFD93D), Blob(x: 0.85, y: 0.8, r: 0.7, hex: 0xFF8A3D), Blob(x: 0.7, y: 0.2, r: 0.4, hex: 0xB7E34A, a: 0.9)], twirl: 0.5, grain: 0.04),
    Paper(name: "09-glacier", base: 0xE6F1FA, blobs: [Blob(x: 0.2, y: 0.7, r: 0.7, hex: 0x9ED2F5), Blob(x: 0.8, y: 0.3, r: 0.65, hex: 0xB9B8F8), Blob(x: 0.55, y: 0.5, r: 0.4, hex: 0xA8EBD8, a: 0.9)], twirl: 0.4, grain: 0.035),
    Paper(name: "10-nebula", base: 0x0A0618, blobs: [Blob(x: 0.25, y: 0.75, r: 0.7, hex: 0x7B2FF7), Blob(x: 0.8, y: 0.3, r: 0.65, hex: 0xF107A3), Blob(x: 0.6, y: 0.8, r: 0.4, hex: 0x00C6FF, a: 0.8)], twirl: 0.9),
    Paper(name: "11-rose-gold", base: 0x2A1519, blobs: [Blob(x: 0.8, y: 0.25, r: 0.65, hex: 0xE8A0A0), Blob(x: 0.25, y: 0.75, r: 0.6, hex: 0x7A1F3D), Blob(x: 0.55, y: 0.55, r: 0.4, hex: 0xF2C48D, a: 0.85)], twirl: 0.5),
    Paper(name: "12-mono", base: 0x121214, blobs: [Blob(x: 0.3, y: 0.3, r: 0.7, hex: 0x5A5A66), Blob(x: 0.85, y: 0.8, r: 0.6, hex: 0x2E2E36), Blob(x: 0.7, y: 0.25, r: 0.35, hex: 0x8A8A96, a: 0.7)], twirl: 0.5),
    Paper(name: "13-signal", base: 0x0E0E12, blobs: [Blob(x: 0.1, y: 0.9, r: 0.75, hex: 0xFF4D2E), Blob(x: 0.95, y: 0.1, r: 0.35, hex: 0xC6FF3D, a: 0.85), Blob(x: 0.55, y: 0.6, r: 0.3, hex: 0xFF8A3D, a: 0.5)], twirl: 0.6),
    Paper(name: "14-sunrise", base: 0x2B1B4D, blobs: [Blob(x: 0.5, y: 1.0, r: 0.9, hex: 0xFF7A45), Blob(x: 0.15, y: 0.55, r: 0.55, hex: 0xFF4F8B), Blob(x: 0.9, y: 0.6, r: 0.5, hex: 0xFFD166, a: 0.8)], twirl: 0.4),
]

let W = 3200.0, H = 1800.0
let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let rect = CGRect(x: 0, y: 0, width: W, height: H)

for p in papers {
    var img = CIImage(color: col(p.base)).cropped(to: rect)
    for b in p.blobs {
        let g = CIFilter.radialGradient()
        g.center = CGPoint(x: b.x * W, y: b.y * H)
        g.radius0 = 0
        g.radius1 = Float(b.r * W * 0.62)
        g.color0 = col(b.hex, b.a)
        g.color1 = col(b.hex, 0)
        img = g.outputImage!.cropped(to: rect).composited(over: img)
    }
    if p.twirl > 0 {
        let t = CIFilter.twirlDistortion()
        t.inputImage = img.clampedToExtent()
        t.center = CGPoint(x: W * 0.55, y: H * 0.5)
        t.radius = Float(W * 0.55)
        t.angle = Float(p.twirl)
        img = t.outputImage!.cropped(to: rect)
    }
    let noise = CIFilter.randomGenerator().outputImage!.cropped(to: rect)
    let m = CIFilter.colorMatrix()
    m.inputImage = noise
    m.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
    m.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
    m.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
    m.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(p.grain))
    m.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    img = m.outputImage!.composited(over: img).cropped(to: rect)
    let url = URL(fileURLWithPath: "\(out)/\(p.name).jpg")
    try! ctx.writeJPEGRepresentation(of: img, to: url, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.88])
}

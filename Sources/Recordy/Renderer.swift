import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

final class RenderState {
    private let lock = NSLock()
    private var _project: Project
    private var _timeline: Timeline
    private var _offset = 0.0
    let dir: URL

    init(project: Project, dir: URL) {
        self.dir = dir
        _project = project
        _timeline = Timeline(project: project)
    }

    func update(_ p: Project) {
        let tl = Timeline(project: p)
        lock.lock(); _project = p; _timeline = tl; lock.unlock()
    }

    func setOffset(_ o: Double) {
        lock.lock(); _offset = o; lock.unlock()
    }

    var snapshot: (Project, Timeline, Double) {
        lock.lock(); defer { lock.unlock() }
        return (_project, _timeline, _offset)
    }
}

func outputSize(for p: Project) -> CGSize {
    let src = p.sourceSize
    let original = Double(src.width) / Double(max(src.height, 1))
    let ratio = p.style.aspect.ratio(original: original)
    let short = p.style.resolution > 0 ? Double(p.style.resolution) : Double(min(src.width, src.height))
    var w: Double, h: Double
    if ratio >= 1 { h = short; w = short * ratio } else { w = short; h = short / ratio }
    w = (w / 2).rounded() * 2
    h = (h / 2).rounded() * 2
    return CGSize(width: w, height: h)
}

final class CompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    nonisolated(unsafe) let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let state: RenderState

    init(timeRange: CMTimeRange, screen: CMPersistentTrackID, camera: CMPersistentTrackID?, state: RenderState) {
        self.timeRange = timeRange
        self.screenTrackID = screen
        self.cameraTrackID = camera
        self.state = state
        var ids = [NSNumber(value: screen)]
        if let camera { ids.append(NSNumber(value: camera)) }
        requiredSourceTrackIDs = ids
    }
}

final class Compositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    private let queue = DispatchQueue(label: "recordy.compositor")
    private let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    private var underlayKey = ""
    private var underlay: CIImage?
    private let blur = BackgroundBlur()
    private var screenMaskKey = ""
    private var screenMask: CIImage?
    private var borderKey = ""
    private var borderRing: CIImage?
    private var cameraDecorKey = ""
    private var cameraDecor: (shadow: CIImage, ring: CIImage, mask: CIImage)?

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            guard let inst = request.videoCompositionInstruction as? CompositionInstruction,
                  let out = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "recordy", code: 1))
                return
            }
            let screen = request.sourceFrame(byTrackID: inst.screenTrackID)
            let cam = inst.cameraTrackID.flatMap { request.sourceFrame(byTrackID: $0) }
            let (project, timeline, offset) = inst.state.snapshot
            let t = request.compositionTime.seconds + offset
            self.render(project: project, timeline: timeline, dir: inst.state.dir, t: t, screen: screen, camera: cam, into: out)
            request.finish(withComposedVideoFrame: out)
        }
    }

    private func gradientImage(style: Style, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        func c(_ x: RGBA) -> CIColor { CIColor(red: x.r, green: x.g, blue: x.b, alpha: x.a) }
        if !style.bgGradient { return CIImage(color: c(style.bgColor1)).cropped(to: rect) }
        let a = style.bgAngle * .pi / 180
        let dx = cos(a), dy = -sin(a)
        let half = (abs(dx) * size.width + abs(dy) * size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let f = CIFilter.linearGradient()
        f.point0 = CGPoint(x: center.x - dx * half, y: center.y - dy * half)
        f.point1 = CGPoint(x: center.x + dx * half, y: center.y + dy * half)
        f.color0 = c(style.bgColor1)
        f.color1 = c(style.bgColor2)
        return f.outputImage!.cropped(to: rect)
    }

    private func maskCG(_ size: CGSize, radius: Double, stroke: Double? = nil) -> CGImage? {
        let w = max(Int(size.width.rounded(.up)), 1), h = max(Int(size.height.rounded(.up)), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        if let stroke {
            let r = CGRect(x: stroke / 2, y: stroke / 2, width: CGFloat(w) - stroke, height: CGFloat(h) - stroke)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: max(radius - stroke / 2, 0), cornerHeight: max(radius - stroke / 2, 0), transform: nil))
            ctx.setLineWidth(stroke)
            ctx.strokePath()
        } else {
            let r = CGRect(x: 0, y: 0, width: w, height: h)
            let rad = min(radius, min(r.width, r.height) / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
            ctx.fillPath()
        }
        return ctx.makeImage()
    }

    private func mask(_ size: CGSize, radius: Double) -> CIImage {
        CIImage(cgImage: maskCG(size, radius: radius)!)
    }

    private func tinted(_ image: CIImage, _ color: RGBA, alpha: Double = 1) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))
        f.biasVector = CIVector(x: color.r * alpha, y: color.g * alpha, z: color.b * alpha, w: 0)
        return f.outputImage!
    }

    private func fadeAlpha(_ image: CIImage, _ a: Double) -> CIImage {
        guard a < 0.999 else { return image }
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: CGFloat(a), y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: CGFloat(a), z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: CGFloat(a), w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))
        return f.outputImage!
    }

    private func patternImage(style s: Style, size: CGSize) -> CIImage? {
        let min = Swift.min(size.width, size.height)
        let lum = s.bgImageFile == nil ? 0.299 * s.bgColor1.r + 0.587 * s.bgColor1.g + 0.114 * s.bgColor1.b : 0.3
        let ink: CGFloat = lum > 0.55 ? 0 : 1
        switch s.bgPattern {
        case .none: return nil
        case .grain:
            let noise = CIFilter.randomGenerator().outputImage!.cropped(to: CGRect(origin: .zero, size: size))
            let m = CIFilter.colorMatrix()
            m.inputImage = noise
            m.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            m.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            m.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            m.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.3)
            return m.outputImage
        default:
            let w = Int(size.width), h = Int(size.height)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: ink, alpha: 0.16))
            ctx.setStrokeColor(CGColor(gray: ink, alpha: 0.32))
            let unit = min / 1080
            switch s.bgPattern {
            case .dots:
                let step = 34 * unit, r = 2.2 * unit
                var y = step / 2
                while y < size.height { var x = step / 2; while x < size.width { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)); x += step }; y += step }
            case .grid:
                let step = 60 * unit
                ctx.setLineWidth(max(1.5, 1.5 * unit))
                var x: CGFloat = 0
                while x < size.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.strokePath()
            default:
                let step = 28 * unit
                ctx.setLineWidth(max(2, 2.5 * unit))
                var x = -size.height
                while x < size.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x + size.height, y: size.height)); x += step }
                ctx.strokePath()
            }
            return ctx.makeImage().map { CIImage(cgImage: $0) }
        }
    }

    static func contentRect(project: Project, out: CGSize) -> CGRect {
        let pad = project.style.padding * min(out.width, out.height)
        let avail = CGSize(width: out.width - 2 * pad, height: out.height - 2 * pad)
        let src = project.sourceSize
        let ar = Double(src.width) / Double(max(src.height, 1))
        var w = avail.width, h = w / ar
        if h > avail.height { h = avail.height; w = h * ar }
        w = w.rounded(); h = h.rounded()
        return CGRect(x: ((out.width - w) / 2).rounded(), y: ((out.height - h) / 2).rounded(), width: w, height: h)
    }

    private func buildUnderlay(project: Project, dir: URL, out: CGSize, rect: CGRect) -> CIImage {
        let s = project.style
        let key = "\(out.width)x\(out.height)|\(rect)|\(s.bgColor1)|\(s.bgColor2)|\(s.bgGradient)|\(s.bgAngle)|\(s.bgImageFile ?? "")|\(s.cornerRadius)|\(s.shadow)|\(s.bgPattern)"
        if key == underlayKey, let u = underlay { return u }
        let bounds = CGRect(origin: .zero, size: out)
        var img = gradientImage(style: s, size: out)
        if let f = s.bgImageFile, let u = BackgroundImages.url(f, projectDir: dir), let src = CIImage(contentsOf: u) {
            let sc = max(out.width / src.extent.width, out.height / src.extent.height)
            let scaled = src.transformed(by: CGAffineTransform(scaleX: sc, y: sc))
            let e = scaled.extent
            img = scaled.transformed(by: CGAffineTransform(translationX: (out.width - e.width) / 2 - e.minX, y: (out.height - e.height) / 2 - e.minY)).cropped(to: bounds)
        }
        if let p = patternImage(style: s, size: out) { img = p.cropped(to: bounds).composited(over: img) }
        if s.shadow > 0.01 {
            let radius = s.cornerRadius * min(rect.width, rect.height)
            let m = mask(rect.size, radius: radius)
            let sh = tinted(m, RGBA(r: 0, g: 0, b: 0), alpha: 0.55 * s.shadow)
            let blurRadius = 0.035 * min(out.width, out.height) * (0.5 + s.shadow)
            let offset = 0.012 * min(out.width, out.height)
            let moved = sh.transformed(by: CGAffineTransform(translationX: rect.minX, y: out.height - rect.maxY - offset))
            let blurred = moved.applyingGaussianBlur(sigma: blurRadius / 2).cropped(to: bounds)
            img = blurred.composited(over: img)
        }
        let cg = ci.createCGImage(img, from: bounds)!
        let result = CIImage(cgImage: cg)
        underlayKey = key
        underlay = result
        return result
    }

    private func decor(shape: CameraShape, size: CGSize, pad: Double, style: Style, out: CGSize) -> (shadow: CIImage, ring: CIImage, mask: CIImage) {
        let scale = min(out.width, out.height) / 1080
        let bw = style.cameraBorder * scale
        let key = "\(shape)|\(size)|\(pad)|\(bw)|\(style.cameraBorderColor)"
        if key == cameraDecorKey, let d = cameraDecor { return d }
        let radius = shape.radius(for: size)
        let m = mask(size, radius: radius)
        let gbounds = CGRect(x: 0, y: 0, width: size.width + 2 * pad, height: size.height + 2 * pad)
        let sh = tinted(m, RGBA(r: 0, g: 0, b: 0), alpha: 0.5)
            .transformed(by: CGAffineTransform(translationX: pad, y: pad - 0.006 * min(out.width, out.height)))
        let shadow = sh.applyingGaussianBlur(sigma: pad / 4).cropped(to: gbounds)
        let shadowCG = CIImage(cgImage: ci.createCGImage(shadow, from: gbounds)!)
        var ring = CIImage.empty()
        if bw > 0.1, let rcg = maskCG(size, radius: radius, stroke: bw) {
            ring = tinted(CIImage(cgImage: rcg), style.cameraBorderColor)
                .transformed(by: CGAffineTransform(translationX: pad, y: pad))
        }
        let d = (shadowCG, ring, m)
        cameraDecorKey = key
        cameraDecor = d
        return d
    }

    private func render(project: Project, timeline: Timeline, dir: URL, t: Double, screen: CVPixelBuffer?, camera: CVPixelBuffer?, into out: CVPixelBuffer) {
        let outSize = CGSize(width: CVPixelBufferGetWidth(out), height: CVPixelBufferGetHeight(out))
        let bounds = CGRect(origin: .zero, size: outSize)
        let rect = Compositor.contentRect(project: project, out: outSize)
        var image = buildUnderlay(project: project, dir: dir, out: outSize, rect: rect)

        if let screen {
            let full = CIImage(cvPixelBuffer: screen)
            let sw = full.extent.width, sh = full.extent.height
            let z = timeline.zoomState(at: t)
            let vw = sw / z.scale, vh = sh / z.scale
            let x0 = min(max(z.center.x * sw - vw / 2, 0), sw - vw)
            let yTop = min(max(z.center.y * sh - vh / 2, 0), sh - vh)
            let crop = CGRect(x: x0, y: sh - yTop - vh, width: vw, height: vh)
            let screenRect = rect
            let sx = screenRect.width / vw, sy = screenRect.height / vh
            let tf = CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
                .concatenating(CGAffineTransform(scaleX: sx, y: sy))
                .concatenating(CGAffineTransform(translationX: screenRect.minX, y: outSize.height - screenRect.maxY))
            let radius = project.style.cornerRadius * min(rect.width, rect.height)
            var content = full.transformed(by: tf, highQualityDownsample: true)
                .cropped(to: CGRect(x: screenRect.minX, y: outSize.height - screenRect.maxY, width: screenRect.width, height: screenRect.height))
            let unionCI = CGRect(x: rect.minX, y: outSize.height - rect.maxY, width: rect.width, height: rect.height)
            let maskKey = "\(rect.size)|\(radius)"
            if maskKey != screenMaskKey || screenMask == nil {
                screenMaskKey = maskKey
                screenMask = mask(rect.size, radius: radius)
            }
            let m = screenMask!
                .transformed(by: CGAffineTransform(translationX: rect.minX, y: outSize.height - rect.maxY))
            content = content.cropped(to: unionCI)
                .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: m])
            image = content.composited(over: image)
            let bw = project.style.screenBorder * min(outSize.width, outSize.height) / 1080
            if bw > 0.1 {
                let key = "\(rect.size)|\(radius)|\(bw)|\(project.style.screenBorderColor)"
                if key != borderKey, let cg = maskCG(rect.size, radius: radius, stroke: bw) {
                    borderKey = key
                    borderRing = tinted(CIImage(cgImage: cg), project.style.screenBorderColor, alpha: project.style.screenBorderColor.a)
                }
                if let ring = borderRing {
                    image = ring.transformed(by: CGAffineTransform(translationX: rect.minX, y: outSize.height - rect.maxY)).composited(over: image)
                }
            }
        }

        if let camera, let pose = timeline.cameraPose(at: t) {
            image = drawCamera(camera, pose: pose, project: project, out: outSize).composited(over: image)
        }
        ci.render(image, to: out, bounds: bounds, colorSpace: cs)
    }

    private func drawCamera(_ buf: CVPixelBuffer, pose: CameraPose, project: Project, out: CGSize) -> CIImage {
        let style = project.style
        let base = style.cameraSize * min(out.width, out.height)
        let size = pose.shape.size(base: base)
        let tw = size.width.rounded(), th = size.height.rounded()
        let tsize = CGSize(width: tw, height: th)
        let pad = (0.03 * min(out.width, out.height)).rounded()
        let d = decor(shape: pose.shape, size: tsize, pad: pad, style: style, out: out)

        var cam = style.cameraBlur ? blur.apply(buf) : CIImage(cvPixelBuffer: buf)
        let cw = cam.extent.width, ch = cam.extent.height
        if style.cameraMirror {
            cam = cam.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -cw, y: 0))
        }
        let sc = max(tw / cw, th / ch)
        cam = cam.transformed(by: CGAffineTransform(scaleX: sc, y: sc))
        let e = cam.extent
        cam = cam.transformed(by: CGAffineTransform(translationX: (tw - e.width) / 2 - e.minX + pad, y: (th - e.height) / 2 - e.minY + pad))
        let maskPlaced = d.mask.transformed(by: CGAffineTransform(translationX: pad, y: pad))
        cam = cam.cropped(to: CGRect(x: pad, y: pad, width: tw, height: th))
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: maskPlaced])

        var group = d.ring.composited(over: cam).composited(over: d.shadow)
        let margin = 0.035 * min(out.width, out.height)
        let left = margin + pose.anchor.x * (out.width - 2 * margin - tw)
        let top = margin + pose.anchor.y * (out.height - 2 * margin - th)
        let gw = tw + 2 * pad, gh = th + 2 * pad
        let popScale = 0.88 + 0.12 * pose.pop
        let originX = left - pad, originY = out.height - top - th - pad
        let center = CGPoint(x: originX + gw / 2, y: originY + gh / 2)
        let tf = CGAffineTransform(translationX: -gw / 2, y: -gh / 2)
            .concatenating(CGAffineTransform(scaleX: popScale, y: popScale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        group = group.transformed(by: tf)
        return fadeAlpha(group, pose.alpha)
    }
}

enum CompositionBuilder {
    struct Built {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix?
        let duration: Double
    }

    static func build(project: Project, dir: URL, state: RenderState) async throws -> Built {
        let comp = AVMutableComposition()
        let lo = project.trimStart, hi = project.trimEnd
        let outSize = outputSize(for: project)

        func insert(_ file: String, offset: Double, mediaType: AVMediaType) async throws -> CMPersistentTrackID? {
            let asset = AVURLAsset(url: dir.appendingPathComponent(file))
            guard let track = try await asset.loadTracks(withMediaType: mediaType).first else { return nil }
            let dur = try await asset.load(.duration).seconds
            let a = max(offset, lo), b = min(offset + dur, hi)
            guard b > a else { return nil }
            guard let dst = comp.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            let range = CMTimeRange(start: CMTime(seconds: a - offset, preferredTimescale: 600),
                                    duration: CMTime(seconds: b - a, preferredTimescale: 600))
            try dst.insertTimeRange(range, of: track, at: CMTime(seconds: a - lo, preferredTimescale: 600))
            return dst.trackID
        }

        guard let screenID = try await insert(project.screenFile, offset: project.screenOffset, mediaType: .video) else {
            throw NSError(domain: "recordy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Screen track missing"])
        }
        var cameraID: CMPersistentTrackID?
        if let f = project.cameraFile { cameraID = try? await insert(f, offset: project.cameraOffset, mediaType: .video) }
        var audioMix: AVMutableAudioMix?
        if let clips = project.audioClips {
            var params: [AVMutableAudioMixInputParameters] = []
            for c in clips where !c.muted && c.volume > 0.001 {
                let asset = AVURLAsset(url: dir.appendingPathComponent(c.file))
                guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                      let fileDur = try? await track.load(.timeRange).duration.seconds else { continue }
                let a = max(c.start, lo)
                let b = min(c.end, hi, c.start + fileDur - c.srcStart)
                guard b - a > 0.02, let dst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let range = CMTimeRange(start: CMTime(seconds: c.srcStart + (a - c.start), preferredTimescale: 600),
                                        duration: CMTime(seconds: b - a, preferredTimescale: 600))
                try dst.insertTimeRange(range, of: track, at: CMTime(seconds: a - lo, preferredTimescale: 600))
                let ip = AVMutableAudioMixInputParameters(track: dst)
                let vol = Float(c.volume)
                let fade = min(0.02, (b - a) / 2)
                let fadeT = CMTime(seconds: fade, preferredTimescale: 600)
                ip.setVolumeRamp(fromStartVolume: 0, toEndVolume: vol, timeRange: CMTimeRange(start: CMTime(seconds: a - lo, preferredTimescale: 600), duration: fadeT))
                ip.setVolume(vol, at: CMTime(seconds: a - lo + fade, preferredTimescale: 600))
                ip.setVolumeRamp(fromStartVolume: vol, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: b - lo - fade, preferredTimescale: 600), duration: fadeT))
                params.append(ip)
            }
            if !params.isEmpty {
                let mix = AVMutableAudioMix()
                mix.inputParameters = params
                audioMix = mix
            }
        } else {
            _ = try await insert(project.screenFile, offset: project.screenOffset, mediaType: .audio)
            if let f = project.micFile { _ = try await insert(f, offset: project.micOffset, mediaType: .audio) }
        }

        state.setOffset(lo)
        let total = CMTime(seconds: hi - lo, preferredTimescale: 600)
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = Compositor.self
        vc.renderSize = outSize
        vc.frameDuration = CMTime(value: 1, timescale: 60)
        vc.instructions = [CompositionInstruction(timeRange: CMTimeRange(start: .zero, duration: total), screen: screenID, camera: cameraID, state: state)]
        return Built(composition: comp, videoComposition: vc, audioMix: audioMix, duration: hi - lo)
    }
}

@MainActor
final class Exporter: ObservableObject {
    @Published var progress = 0.0
    @Published var running = false
    @Published var error: String?
    @Published var lastOutput: URL?

    func export(project: Project, dir: URL, to url: URL) async {
        running = true; progress = 0; error = nil
        defer { running = false }
        do {
            try? FileManager.default.removeItem(at: url)
            let state = RenderState(project: project, dir: dir)
            let built = try await CompositionBuilder.build(project: project, dir: dir, state: state)
            guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "recordy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
            }
            session.videoComposition = built.videoComposition
            session.audioMix = built.audioMix
            session.outputURL = url
            session.outputFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
            nonisolated(unsafe) let exportSession = session
            let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                let p = Double(exportSession.progress)
                Task { @MainActor in self?.progress = p }
            }
            await session.export()
            timer.invalidate()
            if session.status == .completed {
                progress = 1
                lastOutput = url
            } else {
                throw session.error ?? NSError(domain: "recordy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

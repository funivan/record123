import AppKit
import CoreImage
import Vision

final class BackgroundBlur {
    private let request: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()

    func apply(_ buffer: CVPixelBuffer) -> CIImage {
        let image = CIImage(cvPixelBuffer: buffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer)
        guard (try? handler.perform([request])) != nil, let maskBuffer = request.results?.first?.pixelBuffer else { return image }
        let e = image.extent
        let raw = CIImage(cvPixelBuffer: maskBuffer)
        let mask = raw.transformed(by: CGAffineTransform(scaleX: e.width / raw.extent.width, y: e.height / raw.extent.height))
            .clampedToExtent().applyingGaussianBlur(sigma: 2).cropped(to: e)
        let sigma = max(e.width, e.height) * 0.015
        let backgroundOnly = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.clear.cropped(to: e),
            kCIInputMaskImageKey: mask.applyingFilter("CIColorInvert"),
        ])
        let blurred = backgroundOnly.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: e)
            .unpremultiplyingAlpha().settingAlphaOne(in: e)
        return image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: blurred, kCIInputMaskImageKey: mask])
    }
}

final class BlurredPreview: @unchecked Sendable {
    static let shared = BlurredPreview()
    private let lock = NSLock()
    private var _enabled = false
    private var busy = false
    private let queue = DispatchQueue(label: "recordy.blur.preview")
    private let blur = BackgroundBlur()
    private let ci = CIContext()
    private let layers = NSHashTable<CALayer>.weakObjects()

    var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set {
            lock.lock(); _enabled = newValue; lock.unlock()
            DispatchQueue.main.async { self.refreshLayers() }
        }
    }

    func register(_ layer: CALayer) {
        layers.add(layer)
        refreshLayers()
    }

    func submit(_ buffer: CVPixelBuffer) {
        lock.lock()
        guard _enabled, !busy else { lock.unlock(); return }
        busy = true
        lock.unlock()
        queue.async {
            let image = self.blur.apply(buffer)
            let cg = self.ci.createCGImage(image, from: image.extent)
            self.lock.lock(); self.busy = false; self.lock.unlock()
            DispatchQueue.main.async {
                guard self.enabled else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for l in self.layers.allObjects { l.contents = cg }
                CATransaction.commit()
            }
        }
    }

    private func refreshLayers() {
        let on = enabled
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in layers.allObjects {
            l.isHidden = !on
            if !on { l.contents = nil }
        }
        CATransaction.commit()
    }

    static func makeLayer(mirrored: Bool) -> CALayer {
        let l = CALayer()
        l.contentsGravity = .resizeAspectFill
        l.masksToBounds = true
        l.isHidden = true
        if mirrored { l.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1)) }
        return l
    }

    static func layout(_ l: CALayer, in bounds: CGRect) {
        l.bounds = CGRect(origin: .zero, size: bounds.size)
        l.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

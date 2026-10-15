import AppKit
import AVFoundation

final class CameraOverlay {
    private var panel: NSPanel?
    private var preview: AVCaptureVideoPreviewLayer?
    private var blurLayer: CALayer?
    private let maskLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private var screen: NSScreen?
    private var style = Style()
    private(set) var corner = CameraCorner.bottomRight
    private(set) var shape = CameraShape.circle
    private var visible = true

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    private var meterPanel: NSPanel?
    private let meterFill = CALayer()

    func prepare(on screen: NSScreen, style: Style, corner: CameraCorner, shape: CameraShape) {
        self.screen = screen
        self.style = style
        self.corner = corner
        self.shape = shape
    }

    func showMeter() {
        guard meterPanel == nil, screen != nil else { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 30), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 190, height: 30))
        v.material = .hudWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 15
        v.layer?.masksToBounds = true
        let icon = NSImageView(frame: NSRect(x: 10, y: 6, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        icon.contentTintColor = .white
        v.addSubview(icon)
        let track = CALayer()
        track.frame = CGRect(x: 36, y: 12, width: 142, height: 6)
        track.cornerRadius = 3
        track.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        meterFill.frame = CGRect(x: 0, y: 0, width: 0, height: 6)
        meterFill.cornerRadius = 3
        meterFill.backgroundColor = NSColor.systemGreen.cgColor
        track.addSublayer(meterFill)
        v.layer?.addSublayer(track)
        p.contentView = v
        meterPanel = p
        positionMeter(animated: false)
        p.orderFrontRegardless()
    }

    func setLevel(_ l: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        meterFill.frame.size.width = 142 * CGFloat(l)
        meterFill.backgroundColor = (l > 0.9 ? NSColor.systemRed : l > 0.7 ? NSColor.systemYellow : NSColor.systemGreen).cgColor
        CATransaction.commit()
    }

    private func positionMeter(animated: Bool) {
        guard let meterPanel, let screen else { return }
        let f = frame()
        let w = meterPanel.frame.width
        let x = min(max(f.midX - w / 2, screen.frame.minX + 8), screen.frame.maxX - w - 8)
        let below = corner == .topLeft || corner == .topRight
        let y = below ? f.minY - 8 - 30 : f.maxY + 8
        let r = NSRect(x: x, y: y, width: w, height: 30)
        if animated { meterPanel.animator().setFrame(r, display: true) } else { meterPanel.setFrame(r, display: true) }
    }

    func show(on screen: NSScreen, session: AVCaptureSession, style: Style, corner: CameraCorner, shape: CameraShape) {
        prepare(on: screen, style: style, corner: corner, shape: shape)
        panel?.orderOut(nil)
        let p = NSPanel(contentRect: frame(), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = NSView(frame: NSRect(origin: .zero, size: p.frame.size))
        v.wantsLayer = true
        let pl = AVCaptureVideoPreviewLayer(session: session)
        pl.videoGravity = .resizeAspectFill
        if let c = pl.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = style.cameraMirror
        }
        v.layer?.addSublayer(pl)
        let bl = BlurredPreview.makeLayer(mirrored: style.cameraMirror)
        pl.addSublayer(bl)
        blurLayer = bl
        BlurredPreview.shared.register(bl)
        ringLayer.fillColor = nil
        ringLayer.strokeColor = NSColor.white.cgColor
        ringLayer.lineWidth = 3
        v.layer?.addSublayer(ringLayer)
        p.contentView = v
        preview = pl
        panel = p
        layoutLayers()
        p.orderFrontRegardless()
    }

    private func size() -> CGSize {
        guard let screen else { return .zero }
        return shape.size(base: style.cameraSize * screen.frame.height * 0.85)
    }

    private func frame() -> NSRect {
        guard let screen else { return .zero }
        let f = screen.frame
        let s = size()
        let m = 0.035 * min(f.width, f.height) + 0.07 * min(f.width, f.height) * 0.6
        let u = corner.unit
        let left = f.minX + m + u.x * (f.width - 2 * m - s.width)
        let top = m + u.y * (f.height - 2 * m - s.height)
        return NSRect(x: left, y: f.maxY - top - s.height, width: s.width, height: s.height)
    }

    private func layoutLayers() {
        guard let panel else { return }
        let b = NSRect(origin: .zero, size: panel.frame.size)
        preview?.frame = b
        if let blurLayer { BlurredPreview.layout(blurLayer, in: b) }
        let path = CGPath(roundedRect: b.insetBy(dx: 1.5, dy: 1.5), cornerWidth: shape.radius(for: b.size), cornerHeight: shape.radius(for: b.size), transform: nil)
        maskLayer.path = CGPath(roundedRect: b, cornerWidth: shape.radius(for: b.size), cornerHeight: shape.radius(for: b.size), transform: nil)
        preview?.mask = maskLayer
        ringLayer.frame = b
        ringLayer.path = path
    }

    func update(corner: CameraCorner, shape: CameraShape, visible: Bool) {
        self.corner = corner
        self.shape = shape
        self.visible = visible
        guard let panel else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().setFrame(frame(), display: true)
            panel.animator().alphaValue = visible ? 1 : 0
        }
        panel.contentView?.frame = NSRect(origin: .zero, size: panel.frame.size)
        layoutLayers()
        positionMeter(animated: true)
        CATransaction.commit()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        preview = nil
        blurLayer = nil
        meterPanel?.orderOut(nil)
        meterPanel = nil
    }

    var hasCamera: Bool { panel != nil }

    func moveMeter() { positionMeter(animated: true) }

    func setLayout(corner: CameraCorner, shape: CameraShape) {
        self.corner = corner
        self.shape = shape
        if panel != nil { update(corner: corner, shape: shape, visible: true) } else { positionMeter(animated: true) }
    }
}

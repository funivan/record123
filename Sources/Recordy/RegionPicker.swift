import AppKit

struct CaptureRegion: Codable, Equatable {
    var displayID: CGDirectDisplayID
    var rect: CGRect
}

@MainActor
final class RegionPicker {
    private static var active: RegionPicker?
    nonisolated static let minSelectionSize: CGFloat = 64
    private var panel: NSPanel?
    private var done: ((CGRect?) -> Void)?

    static func pick(on screen: NSScreen, initial: CGRect?) async -> CGRect? {
        await withCheckedContinuation { continuation in
            let picker = RegionPicker()
            active = picker
            picker.present(on: screen, initial: initial) { rect in
                active = nil
                continuation.resume(returning: rect)
            }
        }
    }

    private func present(on screen: NSScreen, initial: CGRect?, done: @escaping (CGRect?) -> Void) {
        self.done = done
        let p = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.selection = initial
        v.onFinish = { [weak self] rect in self?.finish(rect) }
        p.contentView = v
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
    }

    nonisolated static func isValidSelection(_ rect: CGRect?) -> Bool {
        guard let rect else { return false }
        return rect.width >= minSelectionSize && rect.height >= minSelectionSize
    }

    private func finish(_ rect: CGRect?) {
        panel?.orderOut(nil)
        panel = nil
        let d = done
        done = nil
        d?(rect)
    }
}

@MainActor
final class RegionFrame {
    private var panel: NSPanel?

    func show(on screen: NSScreen, rect: CGRect) {
        hide()
        let p = NSPanel(contentRect: NSRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = RegionBorderView(frame: NSRect(origin: .zero, size: rect.size))
        panel = p
        p.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class RegionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.white.setStroke()
        border.stroke()
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct Edges: OptionSet {
    let rawValue: Int
    static let left = Edges(rawValue: 1 << 0)
    static let right = Edges(rawValue: 1 << 1)
    static let top = Edges(rawValue: 1 << 2)
    static let bottom = Edges(rawValue: 1 << 3)
}

private enum Drag {
    case create(anchor: CGPoint)
    case move(grab: CGPoint, start: CGRect)
    case resize(Edges, start: CGRect)
}

final class SelectionView: NSView {
    var selection: CGRect? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onFinish: ((CGRect?) -> Void)?
    private var drag: Drag?
    private var didDrag = false
    private let grabZone: CGFloat = 10

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard let s = selection else { return }
        let z = grabZone
        addCursorRect(s, cursor: .openHand)
        addCursorRect(CGRect(x: s.minX - z, y: s.minY, width: 2 * z, height: s.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: s.maxX - z, y: s.minY, width: 2 * z, height: s.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: s.minX, y: s.minY - z, width: s.width, height: 2 * z), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: s.minX, y: s.maxY - z, width: s.width, height: 2 * z), cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        let p = clamp(convert(event.locationInWindow, from: nil))
        didDrag = false
        if let s = selection, let edges = grab(at: p, in: s) {
            drag = edges.isEmpty
                ? .move(grab: CGPoint(x: p.x - s.minX, y: p.y - s.minY), start: s)
                : .resize(edges, start: s)
        } else {
            drag = .create(anchor: p)
            selection = CGRect(origin: p, size: .zero)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        didDrag = true
        let p = clamp(convert(event.locationInWindow, from: nil))
        switch drag {
        case .create(let anchor):
            selection = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
        case .move(let grab, let start):
            let x = min(max(p.x - grab.x, 0), bounds.width - start.width)
            let y = min(max(p.y - grab.y, 0), bounds.height - start.height)
            selection = CGRect(origin: CGPoint(x: x, y: y), size: start.size)
        case .resize(let edges, let start):
            var x1 = start.minX, x2 = start.maxX, y1 = start.minY, y2 = start.maxY
            if edges.contains(.left) { x1 = p.x }
            if edges.contains(.right) { x2 = p.x }
            if edges.contains(.top) { y1 = p.y }
            if edges.contains(.bottom) { y2 = p.y }
            selection = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        }
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        guard didDrag, isValid(selection) else { return }
        didDrag = false
        onFinish?(selection?.integral)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish?(nil)
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        let dim = NSBezierPath(rect: bounds)
        if let s = selection {
            dim.append(NSBezierPath(rect: s))
            dim.windingRule = .evenOdd
        }
        dim.fill()
        drawLabel("Drag to select an area", at: CGPoint(x: bounds.midX, y: 40), centered: true)
        guard let s = selection, s.width > 0, s.height > 0 else { return }
        let border = NSBezierPath(rect: s.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.white.setStroke()
        border.stroke()
        if isValid(s) {
            drawLabel("\(Int(s.width)) × \(Int(s.height))", at: CGPoint(x: s.minX, y: max(s.minY - 34, 4)), centered: false)
        } else {
            drawLabel("Too small (min \(Int(RegionPicker.minSelectionSize)) × \(Int(RegionPicker.minSelectionSize)))", at: CGPoint(x: s.minX, y: max(s.minY - 34, 4)), centered: false)
        }
    }

    private func grab(at p: CGPoint, in s: CGRect) -> Edges? {
        let z = grabZone
        guard s.insetBy(dx: -z, dy: -z).contains(p) else { return nil }
        var edges: Edges = []
        if abs(p.x - s.minX) <= z { edges.insert(.left) } else if abs(p.x - s.maxX) <= z { edges.insert(.right) }
        if abs(p.y - s.minY) <= z { edges.insert(.top) } else if abs(p.y - s.maxY) <= z { edges.insert(.bottom) }
        return edges
    }

    private func isValid(_ r: CGRect?) -> Bool {
        RegionPicker.isValidSelection(r)
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func drawLabel(_ text: String, at origin: CGPoint, centered: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let x = centered ? origin.x - (size.width + 16) / 2 : origin.x
        let box = NSRect(x: x, y: origin.y, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        str.draw(at: NSPoint(x: box.minX + 8, y: box.minY + 4))
    }
}

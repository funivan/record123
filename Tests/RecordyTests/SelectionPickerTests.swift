import Testing
import AppKit
@testable import Recordy

@MainActor
struct SelectionPickerTests {
    nonisolated static let size = CGSize(width: 1000, height: 800)

    @MainActor final class Harness {
        let view = SelectionView(frame: NSRect(origin: .zero, size: SelectionPickerTests.size))
        var finished: [CGRect?] = []
        init() { view.onFinish = { [unowned self] in self.finished.append($0) } }

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: SelectionPickerTests.size.height - y) }

        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point(x, y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func down(_ x: CGFloat, _ y: CGFloat) { view.mouseDown(with: mouse(.leftMouseDown, x, y)) }
        func move(_ x: CGFloat, _ y: CGFloat) { view.mouseDragged(with: mouse(.leftMouseDragged, x, y)) }
        func up(_ x: CGFloat, _ y: CGFloat) { view.mouseUp(with: mouse(.leftMouseUp, x, y)) }

        func drag(from a: CGPoint, to b: CGPoint) {
            down(a.x, a.y)
            move((a.x + b.x) / 2, (a.y + b.y) / 2)
            move(b.x, b.y)
            up(b.x, b.y)
        }

        func key(_ code: UInt16) {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            view.keyDown(with: e)
        }
    }

    @Test("Given a valid drag, when the mouse is released, then the area is applied without a key press")
    func validDragApplies() {
        let h = Harness()
        h.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
        #expect(h.finished.count == 1)
        #expect(h.finished.first! == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test("Given a drag of exactly 64 by 64, when the mouse is released, then the area is applied")
    func boundaryDragApplies() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 114, y: 114))
        #expect(h.finished.count == 1)
    }

    @Test("Given a drag of 63 by 63, when the mouse is released, then the picker stays open")
    func smallDragStaysOpen() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 113, y: 113))
        #expect(h.finished.isEmpty)
    }

    @Test("Given a drag that is wide but too short, when the mouse is released, then the picker stays open")
    func thinDragStaysOpen() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 500, y: 100))
        #expect(h.finished.isEmpty)
    }

    @Test("Given a click without a drag, when the mouse is released, then the picker stays open")
    func clickStaysOpen() {
        let h = Harness()
        h.down(200, 200)
        h.up(200, 200)
        #expect(h.finished.isEmpty)
    }

    @Test("Given a too small drag, when the user then drags a valid area, then only the valid area is applied")
    func retryAfterSmallDrag() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 80))
        h.drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 500, y: 450))
        #expect(h.finished.count == 1)
        #expect(h.finished.first! == CGRect(x: 200, y: 200, width: 300, height: 250))
    }

    @Test("Given a drag past the view edge, when the mouse is released, then the area is clamped to the screen")
    func dragClamped() {
        let h = Harness()
        h.drag(from: CGPoint(x: 800, y: 600), to: CGPoint(x: 1500, y: 1200))
        let r = h.finished.first!!
        #expect(r.maxX <= Self.size.width && r.maxY <= Self.size.height)
        #expect(r == CGRect(x: 800, y: 600, width: 200, height: 200))
    }

    @Test("Given an existing selection, when its right edge is dragged and released, then the resized area is applied")
    func resizeExisting() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(300, 200)
        h.move(350, 200)
        h.move(400, 200)
        h.up(400, 200)
        #expect(h.finished.first! == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test("Given an existing selection, when it is resized below 64 and released, then the picker stays open")
    func resizeTooSmall() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(300, 200)
        h.move(130, 200)
        h.up(130, 200)
        #expect(h.finished.isEmpty)
    }

    @Test("Given an existing selection, when it is moved and released, then the moved area is applied with the same size")
    func moveExisting() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(200, 200)
        h.move(300, 260)
        h.up(300, 260)
        #expect(h.finished.first! == CGRect(x: 200, y: 160, width: 200, height: 200))
    }

    @Test("Given an existing selection, when the user only clicks inside it, then the picker stays open")
    func clickInsideExisting() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(200, 200)
        h.up(200, 200)
        #expect(h.finished.isEmpty)
    }

    @Test("Given the picker is open, when Escape is pressed, then it cancels with no area")
    func escapeCancels() {
        let h = Harness()
        h.key(53)
        #expect(h.finished.count == 1)
        #expect(h.finished.first! == nil)
    }

    @Test("Given a valid selection was dragged and the picker is open, when Return is pressed, then nothing is finished")
    func returnDoesNothing() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 300, height: 300)
        h.key(36)
        h.key(76)
        #expect(h.finished.isEmpty)
    }

    @Test("Given a valid drag already applied, when the mouse is released again without dragging, then it is not applied twice")
    func noDoubleApply() {
        let h = Harness()
        h.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
        h.up(400, 300)
        #expect(h.finished.count == 1)
    }
}

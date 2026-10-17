import Testing
import AppKit
@testable import Recordy

@MainActor
// Feature: Selected area is applied as soon as it is drawn
//   The user picks a part of the screen to record. The area is applied when the
//   mouse is released, and the white frame that marks the area only shows while
//   it is useful.
//
//   Background:
//     Given the app is open on the home screen
//     And the recording mode "Selected area" is chosen
//     And no recording is in progress
//
//   Rules: the area is applied when the mouse is released, and the picker needs no keys.
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

    // Scenario: A valid drag applies the area
    //   Given the area picker is open
    //   When the user drags out an area of at least 64 by 64 and releases the mouse
    //   Then the picker closes
    //   And the area is applied
    //   But no key was pressed
    @Test("A valid drag applies the area")
    func validDragApplies() {
        let h = Harness()
        h.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
        #expect(h.finished.count == 1)
        #expect(h.finished.first! == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    // Scenario: A drag of exactly 64 by 64 applies the area
    //   Given the area picker is open
    //   When the user drags out an area of 64 by 64 and releases the mouse
    //   Then the area is applied
    @Test("A drag of exactly 64 by 64 applies the area")
    func boundaryDragApplies() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 114, y: 114))
        #expect(h.finished.count == 1)
    }

    // Scenario: A drag of 63 by 63 keeps the picker open
    //   Given the area picker is open
    //   When the user drags out an area of 63 by 63 and releases the mouse
    //   Then the picker stays open
    @Test("A drag of 63 by 63 keeps the picker open")
    func smallDragStaysOpen() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 113, y: 113))
        #expect(h.finished.isEmpty)
    }

    // Scenario: A wide but short drag keeps the picker open
    //   Given the area picker is open
    //   When the user drags out an area of 450 by 50 and releases the mouse
    //   Then the picker stays open
    @Test("A wide but short drag keeps the picker open")
    func thinDragStaysOpen() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 500, y: 100))
        #expect(h.finished.isEmpty)
    }

    // Scenario: A click without a drag keeps the picker open
    //   Given the area picker is open
    //   When the user clicks without dragging
    //   Then the picker stays open
    @Test("A click without a drag keeps the picker open")
    func clickStaysOpen() {
        let h = Harness()
        h.down(200, 200)
        h.up(200, 200)
        #expect(h.finished.isEmpty)
    }

    // Scenario: The user can try again after a drag that was too small
    //   Given the area picker is open
    //   And the user dragged an area that was too small
    //   When the user drags out a valid area and releases the mouse
    //   Then only the valid area is applied
    @Test("The user can try again after a drag that was too small")
    func retryAfterSmallDrag() {
        let h = Harness()
        h.drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 80))
        h.drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 500, y: 450))
        #expect(h.finished.count == 1)
        #expect(h.finished.first! == CGRect(x: 200, y: 200, width: 300, height: 250))
    }

    // Scenario: A drag past the screen edge is clamped
    //   Given the area picker is open
    //   When the user drags past the edge of the screen and releases the mouse
    //   Then the applied area ends at the screen edge
    @Test("A drag past the screen edge is clamped")
    func dragClamped() {
        let h = Harness()
        h.drag(from: CGPoint(x: 800, y: 600), to: CGPoint(x: 1500, y: 1200))
        let r = h.finished.first!!
        #expect(r.maxX <= Self.size.width && r.maxY <= Self.size.height)
        #expect(r == CGRect(x: 800, y: 600, width: 200, height: 200))
    }

    // Scenario: Resizing a selection applies it on release
    //   Given the area picker is open with a selection already drawn
    //   When the user resizes the selection to at least 64 by 64 and releases the mouse
    //   Then the picker closes
    //   And the changed area is applied
    @Test("Resizing a selection applies it on release")
    func resizeExisting() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(300, 200)
        h.move(350, 200)
        h.move(400, 200)
        h.up(400, 200)
        #expect(h.finished.first! == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    // Scenario: Shrinking a selection below the minimum keeps the picker open
    //   Given the area picker is open with a selection already drawn
    //   When the user shrinks the selection below 64 by 64 and releases the mouse
    //   Then the picker stays open
    @Test("Shrinking a selection below the minimum keeps the picker open")
    func resizeTooSmall() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(300, 200)
        h.move(130, 200)
        h.up(130, 200)
        #expect(h.finished.isEmpty)
    }

    // Scenario: Moving a selection applies it on release
    //   Given the area picker is open with a selection already drawn
    //   When the user moves the selection and releases the mouse
    //   Then the picker closes
    //   And the moved area is applied with the same size
    @Test("Moving a selection applies it on release")
    func moveExisting() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(200, 200)
        h.move(300, 260)
        h.up(300, 260)
        #expect(h.finished.first! == CGRect(x: 200, y: 160, width: 200, height: 200))
    }

    // Scenario: A click inside a selection keeps the picker open
    //   Given the area picker is open with a selection already drawn
    //   When the user clicks inside the selection without dragging
    //   Then the picker stays open
    @Test("A click inside a selection keeps the picker open")
    func clickInsideExisting() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 200, height: 200)
        h.down(200, 200)
        h.up(200, 200)
        #expect(h.finished.isEmpty)
    }

    // Scenario: Esc cancels the picker silently
    //   Given the area picker is open
    //   When the user presses Esc
    //   Then the picker closes
    //   And no area is applied
    //   But no message is shown
    @Test("Esc cancels the picker silently")
    func escapeCancels() {
        let h = Harness()
        h.key(53)
        #expect(h.finished.count == 1)
        #expect(h.finished.first! == nil)
    }

    // Scenario: Return does not finish the picker
    //   Given the area picker is open with a valid selection drawn
    //   When the user presses Return
    //   Then the picker stays open
    @Test("Return does not finish the picker")
    func returnDoesNothing() {
        let h = Harness()
        h.view.selection = CGRect(x: 100, y: 100, width: 300, height: 300)
        h.key(36)
        h.key(76)
        #expect(h.finished.isEmpty)
    }

    // Scenario: A release without a drag does not apply the area twice
    //   Given the area picker is open
    //   And a valid drag was already applied
    //   When the mouse is released again without dragging
    //   Then the area is applied only once
    @Test("A release without a drag does not apply the area twice")
    func noDoubleApply() {
        let h = Harness()
        h.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
        h.up(400, 300)
        #expect(h.finished.count == 1)
    }

    // @manual
    // Scenario: The hint mentions no keys
    //   When the area picker is open
    //   Then the hint reads "Drag to select an area"
    //   But the hint does not mention Enter or Esc
}

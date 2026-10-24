import Testing
import CoreGraphics
@testable import Record123

struct RegionFrameTests {
    static let phases: [RecPhase] = [.idle, .countdown(3), .countdown(0), .recording, .saving]

    /*
      Scenario: The frame is shown only on the idle home screen with an active area
        Given any recording phase, editor state, window visibility and area state
        When the frame visibility is decided
        Then the frame is shown only when idle, no editor, window visible and an area is active
    */
    @Test("The frame is shown only on the idle home screen with an active area")
    func truthTable() {
        for phase in Self.phases {
            for editor in [false, true] {
                for win in [false, true] {
                    for region in [false, true] {
                        let expected = phase == .idle && !editor && win && region
                        let got = AppState.shouldShowRegionFrame(phase: phase, editorOpen: editor, mainWindowVisible: win, hasActiveRegion: region)
                        #expect(got == expected, "\(phase) editor=\(editor) win=\(win) region=\(region)")
                    }
                }
            }
        }
    }

    @Test func onlyOneTrueCombination() {
        #expect(AppState.shouldShowRegionFrame(phase: .idle, editorOpen: false, mainWindowVisible: true, hasActiveRegion: true))
        #expect(!AppState.shouldShowRegionFrame(phase: .saving, editorOpen: false, mainWindowVisible: true, hasActiveRegion: true))
    }

    /*
      Scenario: An area needs at least 64 by 64
        Given a selected area
        When its size is checked
        Then it is valid only when both sides are at least 64
    */
    @Test("An area needs at least 64 by 64")
    func validSelection() {
        #expect(RegionPicker.minSelectionSize == 64)
        #expect(RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 64, height: 64)))
        #expect(RegionPicker.isValidSelection(CGRect(x: 10, y: 10, width: 500, height: 300)))
        #expect(!RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 63.9, height: 64)))
        #expect(!RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 64, height: 63)))
        #expect(!RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 0, height: 0)))
        #expect(!RegionPicker.isValidSelection(nil))
    }
}

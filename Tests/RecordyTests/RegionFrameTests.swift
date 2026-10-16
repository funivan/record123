import Testing
import CoreGraphics
@testable import Recordy

struct RegionFrameTests {
    static let phases: [RecPhase] = [.idle, .countdown(3), .countdown(0), .recording, .saving]

    @Test func truthTable() {
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

    @Test func validSelection() {
        #expect(RegionPicker.minSelectionSize == 64)
        #expect(RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 64, height: 64)))
        #expect(RegionPicker.isValidSelection(CGRect(x: 10, y: 10, width: 500, height: 300)))
        #expect(!RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 63.9, height: 64)))
        #expect(!RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 64, height: 63)))
        #expect(!RegionPicker.isValidSelection(CGRect(x: 0, y: 0, width: 0, height: 0)))
        #expect(!RegionPicker.isValidSelection(nil))
    }
}

import Testing
@testable import Recordy

struct RegionFrameScenarioTests {
    private func shown(_ phase: RecPhase = .idle, editor: Bool = false, window: Bool = true, region: Bool = true) -> Bool {
        AppState.shouldShowRegionFrame(phase: phase, editorOpen: editor, mainWindowVisible: window, hasActiveRegion: region)
    }

    @Test("Given the home screen, an active area and idle recording, then the frame is shown")
    func homeShowsFrame() {
        #expect(shown())
    }

    @Test("Given an open or loading editor, then the frame is hidden")
    func editorHidesFrame() {
        #expect(!shown(editor: true))
    }

    @Test("Given the user returns from the editor to the home screen, then the frame is shown again")
    func backShowsFrame() {
        #expect(!shown(editor: true))
        #expect(shown(editor: false))
    }

    @Test("Given a countdown, a recording or saving, then the frame is hidden")
    func busyHidesFrame() {
        #expect(!shown(.countdown(3)))
        #expect(!shown(.countdown(1)))
        #expect(!shown(.recording))
        #expect(!shown(.saving))
    }

    @Test("Given the main window is closed or minimised, then the frame is hidden, and restoring it shows the frame again")
    func windowHidesFrame() {
        #expect(!shown(window: false))
        #expect(shown(window: true))
    }

    @Test("Given no active area, then the frame is hidden")
    func noRegionHidesFrame() {
        #expect(!shown(region: false))
    }

    @Test("Given a recording just stopped and the project is loading, then the frame stays hidden")
    func stopThenLoadingStaysHidden() {
        #expect(!shown(.recording))
        #expect(!shown(.saving))
        #expect(!shown(.idle, editor: true))
    }
}

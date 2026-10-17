import Testing
@testable import Recordy

// Feature: The area frame shows only on the home screen
//   Rule: The frame is shown only on the home screen with an active area
//   Background: see SelectionPickerTests
struct RegionFrameScenarioTests {
    private func shown(_ phase: RecPhase = .idle, editor: Bool = false, window: Bool = true, region: Bool = true) -> Bool {
        AppState.shouldShowRegionFrame(phase: phase, editorOpen: editor, mainWindowVisible: window, hasActiveRegion: region)
    }

    // Scenario: The frame is shown on the home screen
    //   Given an area is active
    //   When the main window shows the home screen
    //   Then the area frame is on screen
    @Test("The frame is shown on the home screen")
    func homeShowsFrame() {
        #expect(shown())
    }

    // Scenario: The frame is hidden in the editor
    //   Given an area is active
    //   When the editor is open or loading
    //   Then the area frame is not on screen
    @Test("The frame is hidden in the editor")
    func editorHidesFrame() {
        #expect(!shown(editor: true))
    }

    // Scenario: The frame returns after Back to Recordings
    //   Given an area is active
    //   And the user is in the editor
    //   When the user clicks Back to Recordings
    //   Then the area frame is on screen
    @Test("The frame returns after Back to Recordings")
    func backShowsFrame() {
        #expect(!shown(editor: true))
        #expect(shown(editor: false))
    }

    // Scenario: The frame is hidden during the countdown, recording and saving
    //   Given an area is active
    //   When the countdown, a recording or saving is in progress
    //   Then the area frame is not on screen
    @Test("The frame is hidden during the countdown, recording and saving")
    func busyHidesFrame() {
        #expect(!shown(.countdown(3)))
        #expect(!shown(.countdown(1)))
        #expect(!shown(.recording))
        #expect(!shown(.saving))
    }

    // Scenario: The frame follows the main window visibility
    //   Given an area is active
    //   When the main window is closed or minimised
    //   Then the area frame is not on screen
    //   But it is on screen again once the window is back
    @Test("The frame follows the main window visibility")
    func windowHidesFrame() {
        #expect(!shown(window: false))
        #expect(shown(window: true))
    }

    // Scenario: The frame is hidden while no area is active
    //   Given no area is active
    //   When the main window shows the home screen
    //   Then the area frame is not on screen
    @Test("The frame is hidden while no area is active")
    func noRegionHidesFrame() {
        #expect(!shown(region: false))
    }

    // Scenario: The frame stays hidden while the editor loads after a recording
    //   Given an area is active
    //   When a recording has stopped and the editor is still loading
    //   Then the area frame is not on screen
    @Test("The frame stays hidden while the editor loads after a recording")
    func stopThenLoadingStaysHidden() {
        #expect(!shown(.recording))
        #expect(!shown(.saving))
        #expect(!shown(.idle, editor: true))
    }

    // @ui
    // Scenario: The frame is hidden when the main window is closed or minimised
    //   Given an area is active
    //   When the user closes or minimises the main window
    //   Then the area frame is not on screen
    //
    // @ui
    // Scenario: The frame returns after the window is restored
    //   Given an area is active
    //   And the main window was closed or minimised
    //   When the user brings the main window back
    //   Then the area frame is on screen
}

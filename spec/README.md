# Specs

`selected-area.feature` describes the behaviour of issue #1 (selected area is applied automatically, and the area frame only shows on the home screen) in Gherkin. Scenarios are plain English. They are not run by a Gherkin runner. Each one is mapped by hand to a Swift Testing test, a UI script check, or a manual step.

Run the unit tests with `swift test`.

## How scenarios map to verification

Unit tests, in `Tests/RecordyTests/`:
- `SelectionPickerTests.swift` drives the picker view with synthetic mouse and key events. Test display names follow "Given ..., when ..., then ...".
  - valid drag applies, exactly 64 by 64 applies, 63 by 63 stays open, thin drag stays open
  - click without drag stays open, retry after a small drag, clamping to the screen
  - resize, move, shrink below the minimum, click inside an existing selection
  - Esc (key code 53) cancels with no area, Return (36 and 76) finishes nothing, no double apply
- `RegionFrameScenarioTests.swift` and `RegionFrameTests.swift` check the pure frame rule for home, editor open or loading, countdown, recording, saving, window hidden and no area. The full truth table is in `RegionFrameTests.truthTable`.

Verified by UI script or manually (not unit-testable):
- Picker hint text: it is drawn in the view, not exposed as a value. Checked by eye in the running app. A full-screen screenshot of the picker also captures whatever is behind it, so none is kept.
- A real mouse drag closes the real picker and shows the area text on the home screen: `evidence/issue-1/drag-applied.jpg`.
- Frame hidden in the editor: `evidence/issue-1/editor.jpg` and `evidence/issue-1/frame-visibility.txt`.
- Frame hidden when the main window is closed or minimised, and back after restoring: `evidence/issue-1/frame-visibility.txt`. These need real window notifications, so they are UI-script checks only.
- Back to Recordings brings the frame back: `evidence/issue-1/frame-visibility.txt`.
- Frame while the editor is loading right after a recording stops, and during countdown, recording and saving: the rule is unit-tested, but the real flow needs a real screen recording (permissions, hardware). Manual: with "Selected area" active, record 2-3 s, stop, and confirm the white frame does not flash while the editor loads. Also confirm it is not visible during the countdown and recording.

## Evidence notes

The area frame panel has `sharingType = .none`, so `screencapture` never captures it, and the screenshots (JPEG, cropped to the app window) show the home screen text only. Frame presence is proved with the window list from `CGWindowListCopyWindowInfo`, the layer-25 400x350 entry, saved in `evidence/issue-1/frame-visibility.txt`.

No screen recording is included: the drag is covered by the screenshots and the window list. The screenshots show whatever was behind the app window on the test machine.

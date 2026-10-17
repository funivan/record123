import Testing
import CoreGraphics
@testable import Recordy

/*
  Feature: The home screen starts with useful recording defaults
    A new user can press Record straight away. The main display is recorded in
    full, the MacBook microphone is on and the MacBook camera is shown. A choice
    the user made before is kept.

    Background:
      Given the app is open on the home screen
      And no recording is in progress

    Rules: the main display is recorded by default, the MacBook camera and
    microphone are used by default, a choice made before is respected, denied
    access selects nothing, and system audio is off by default.
*/
struct DeviceDefaultsTests {
    private let iphoneMic = DeviceOption(id: "0F5C2A11-iPhone-Continuity-Mic", builtIn: false)
    private let macMic = DeviceOption(id: "BuiltInMicrophoneDevice", builtIn: true)
    private let externalMic = DeviceOption(id: "AppleUSBAudioEngine:Focusrite:Scarlett:1234", builtIn: false)
    private let iphoneCam = DeviceOption(id: "A1B2C3D4-iPhone-Continuity-Camera", builtIn: false)
    private let macCam = DeviceOption(id: "47B4B64B-0000-0000-0000-FACETIMEHDCAM", builtIn: true)
    private let externalCam = DeviceOption(id: "0x1420000046d0825", builtIn: false)

    private func pick(_ stored: String?, _ available: [DeviceOption], systemDefault: String? = nil, denied: Bool = false) -> String {
        DeviceDefaults.selection(stored: stored, available: available, systemDefault: systemDefault, accessDenied: denied)
    }

    /*
      Scenario: The built-in microphone wins over other microphones
        Given the user never chose a microphone
        And the MacBook microphone and an iPhone microphone are available
        When the app starts
        Then the MacBook microphone is selected
    */
    @Test("The built-in microphone wins over other microphones")
    func macBookMicrophoneByDefault() {
        #expect(pick(nil, [iphoneMic, macMic]) == macMic.id)
        #expect(pick(nil, [iphoneMic, macMic], systemDefault: iphoneMic.id) == macMic.id)
        #expect(pick(nil, [macMic, iphoneMic]) == macMic.id)
    }

    /*
      Scenario: The built-in camera wins over other cameras
        Given the user never chose a camera
        And the MacBook camera and an iPhone camera are available
        When the app starts
        Then the MacBook camera is selected
    */
    @Test("The built-in camera wins over other cameras")
    func macBookCameraByDefault() {
        #expect(pick(nil, [iphoneCam, macCam]) == macCam.id)
        #expect(pick(nil, [iphoneCam, externalCam, macCam], systemDefault: iphoneCam.id) == macCam.id)
        #expect(pick(nil, [macCam, iphoneCam]) == macCam.id)
    }

    /*
      Scenario: The system default is used when there is no built-in device
        Given the user never chose a camera or microphone
        And no built-in device is available
        And the system has a default device
        When the app starts
        Then the system default device is selected
    */
    @Test("The system default is used when there is no built-in device")
    func systemDefaultWithoutBuiltIn() {
        #expect(pick(nil, [iphoneMic, externalMic], systemDefault: externalMic.id) == externalMic.id)
        #expect(pick(nil, [iphoneCam, externalCam], systemDefault: iphoneCam.id) == iphoneCam.id)
    }

    /*
      Scenario: Nothing is selected without a built-in device or a usable system default
        Given the user never chose a camera or microphone
        And no built-in device is available
        And the system default is missing or not in the list
        When the app starts
        Then nothing is selected
    */
    @Test("Nothing is selected without a built-in device or a usable system default")
    func noBuiltInAndNoUsableSystemDefault() {
        #expect(pick(nil, [iphoneMic, externalMic], systemDefault: nil) == "")
        #expect(pick(nil, [iphoneMic, externalMic], systemDefault: "UnpluggedDefault") == "")
        #expect(pick(nil, [iphoneMic], systemDefault: "") == "")
    }

    /*
      Scenario: Nothing is shown when no device exists
        Given the user never chose a camera or microphone
        And no device of that kind is available
        When the app starts
        Then "No camera" or "No microphone" is shown
    */
    @Test("Nothing is shown when no device exists")
    func noDevicesAtAll() {
        #expect(pick(nil, []) == "")
        #expect(pick(nil, [], systemDefault: macMic.id) == "")
    }

    /*
      Scenario: An explicit "none" is kept
        Given the user chose "No camera" or "No microphone" before
        And the MacBook camera and microphone are available
        When the app starts
        Then "No camera" or "No microphone" is still shown
    */
    @Test("An explicit \"none\" is kept")
    func explicitNoneIsKept() {
        #expect(pick("", [iphoneMic, macMic], systemDefault: macMic.id) == "")
        #expect(pick("", [iphoneCam, macCam], systemDefault: macCam.id) == "")
    }

    /*
      Scenario: A chosen device is kept while it is connected
        Given the user chose an external microphone before
        And it is still connected
        When the app starts
        Then the external microphone is selected
        But the MacBook microphone is not
    */
    @Test("A chosen device is kept while it is connected")
    func availableStoredDeviceIsKept() {
        #expect(pick(externalMic.id, [iphoneMic, externalMic, macMic], systemDefault: macMic.id) == externalMic.id)
        #expect(pick(externalCam.id, [macCam, externalCam]) == externalCam.id)
    }

    /*
      Scenario: The MacBook device replaces a chosen device that is gone
        Given the user chose an external camera or microphone before
        And it is no longer connected
        When the list of devices is refreshed
        Then the MacBook camera or microphone is selected
    */
    @Test("The MacBook device replaces a chosen device that is gone")
    func goneStoredDeviceFallsBackToBuiltIn() {
        #expect(pick(externalMic.id, [iphoneMic, macMic]) == macMic.id)
        #expect(pick(externalCam.id, [iphoneCam, macCam]) == macCam.id)
    }

    /*
      Scenario: The system default replaces a chosen device that is gone
        Given the chosen device is no longer connected
        And there is no built-in device
        When the list of devices is refreshed
        Then the system default is selected, or nothing when it is not available
    */
    @Test("The system default replaces a chosen device that is gone")
    func goneStoredDeviceFallsBackLikeNeverChosen() {
        #expect(pick(externalMic.id, [iphoneMic], systemDefault: iphoneMic.id) == iphoneMic.id)
        #expect(pick(externalMic.id, [iphoneMic], systemDefault: externalMic.id) == "")
        #expect(pick(externalMic.id, []) == "")
    }

    /*
      Scenario: A denied or restricted device is not selected
        Given camera or microphone access is denied or restricted for Recordy
        When the list of devices is refreshed
        Then "No camera" or "No microphone" is shown
    */
    @Test("A denied or restricted device is not selected")
    func deniedAccessSelectsNothing() {
        let all = [iphoneMic, externalMic, macMic]
        #expect(pick(nil, all, systemDefault: macMic.id, denied: true) == "")
        #expect(pick(externalMic.id, all, systemDefault: macMic.id, denied: true) == "")
        #expect(pick("", all, systemDefault: macMic.id, denied: true) == "")
        #expect(pick(nil, [], denied: true) == "")
    }

    private let main: CGDirectDisplayID = 1
    private let external: CGDirectDisplayID = 5
    private let other: CGDirectDisplayID = 9

    /*
      Scenario: The chosen display is kept while it is connected
        Given the chosen display is connected
        When the list of displays is refreshed
        Then the chosen display stays selected
    */
    @Test("The chosen display is kept while it is connected")
    func chosenDisplayIsKept() {
        #expect(DeviceDefaults.display(current: external, available: [main, external], main: main) == external)
        #expect(DeviceDefaults.display(current: external, available: [external, other], main: main) == external)
    }

    /*
      Scenario: The main display replaces a display that is gone
        Given the chosen display is no longer connected
        And the main display is connected
        When the list of displays is refreshed
        Then the main display is selected
    */
    @Test("The main display replaces a display that is gone")
    func mainDisplayWhenChosenIsGone() {
        #expect(DeviceDefaults.display(current: other, available: [external, main], main: main) == main)
    }

    /*
      Scenario: The first display is used when the main display is not listed
        Given neither the chosen display nor the main display is in the list
        And another display is connected
        When the list of displays is refreshed
        Then the first display in the list is selected
    */
    @Test("The first display is used when the main display is not listed")
    func firstDisplayWhenNeitherIsAvailable() {
        #expect(DeviceDefaults.display(current: other, available: [external, 7], main: main) == external)
    }

    /*
      Scenario: The selection is left alone when no display is listed
        Given no display is listed
        When the list of displays is refreshed
        Then the selection is unchanged
    */
    @Test("The selection is left alone when no display is listed")
    func emptyDisplayListLeavesSelection() {
        #expect(DeviceDefaults.display(current: main, available: [], main: main) == nil)
    }

    /*
      @ui
      Scenario: A new user records the main display
        When the app starts
        Then the screen picker shows the main display
        And "Full display" is selected

      @ui
      Scenario: System audio stays off
        Given the user never changed "Record system audio"
        When the app starts
        Then "Record system audio" is off
    */
}

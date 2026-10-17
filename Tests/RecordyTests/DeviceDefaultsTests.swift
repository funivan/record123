import Testing
import CoreGraphics
@testable import Recordy

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

    @Test("Given the user never chose a microphone and the MacBook microphone and an iPhone microphone are available, when the app starts, then the audio picker shows the MacBook microphone")
    func macBookMicrophoneByDefault() {
        #expect(pick(nil, [iphoneMic, macMic]) == macMic.id)
        #expect(pick(nil, [iphoneMic, macMic], systemDefault: iphoneMic.id) == macMic.id)
        #expect(pick(nil, [macMic, iphoneMic]) == macMic.id)
    }

    @Test("Given the user never chose a camera and the MacBook camera and an iPhone camera are available, when the app starts, then the camera picker shows the MacBook camera")
    func macBookCameraByDefault() {
        #expect(pick(nil, [iphoneCam, macCam]) == macCam.id)
        #expect(pick(nil, [iphoneCam, externalCam, macCam], systemDefault: iphoneCam.id) == macCam.id)
        #expect(pick(nil, [macCam, iphoneCam]) == macCam.id)
    }

    @Test("Given the user never chose a camera or microphone, no built-in device is available and the system has a default device, when the app starts, then the system default device is selected")
    func systemDefaultWithoutBuiltIn() {
        #expect(pick(nil, [iphoneMic, externalMic], systemDefault: externalMic.id) == externalMic.id)
        #expect(pick(nil, [iphoneCam, externalCam], systemDefault: iphoneCam.id) == iphoneCam.id)
    }

    @Test("Given the user never chose a device, no built-in device is available and the system default is missing or not in the list, when the app starts, then nothing is selected")
    func noBuiltInAndNoUsableSystemDefault() {
        #expect(pick(nil, [iphoneMic, externalMic], systemDefault: nil) == "")
        #expect(pick(nil, [iphoneMic, externalMic], systemDefault: "UnpluggedDefault") == "")
        #expect(pick(nil, [iphoneMic], systemDefault: "") == "")
    }

    @Test("Given the user never chose a camera or microphone and no device of that kind is available, when the app starts, then \"No camera\" or \"No microphone\" is shown")
    func noDevicesAtAll() {
        #expect(pick(nil, []) == "")
        #expect(pick(nil, [], systemDefault: macMic.id) == "")
    }

    @Test("Given the user chose \"No camera\" or \"No microphone\" before and the MacBook camera and microphone are available, when the app starts, then \"No camera\" or \"No microphone\" is still shown")
    func explicitNoneIsKept() {
        #expect(pick("", [iphoneMic, macMic], systemDefault: macMic.id) == "")
        #expect(pick("", [iphoneCam, macCam], systemDefault: macCam.id) == "")
    }

    @Test("Given the user chose an external microphone before and it is still connected, when the app starts, then the external microphone is selected, not the MacBook one")
    func availableStoredDeviceIsKept() {
        #expect(pick(externalMic.id, [iphoneMic, externalMic, macMic], systemDefault: macMic.id) == externalMic.id)
        #expect(pick(externalCam.id, [macCam, externalCam]) == externalCam.id)
    }

    @Test("Given the user chose an external camera or microphone before and it is no longer connected, when the list of devices is refreshed, then the MacBook camera or microphone is selected")
    func goneStoredDeviceFallsBackToBuiltIn() {
        #expect(pick(externalMic.id, [iphoneMic, macMic]) == macMic.id)
        #expect(pick(externalCam.id, [iphoneCam, macCam]) == macCam.id)
    }

    @Test("Given the chosen device is gone and there is no built-in device, when the list of devices is refreshed, then the system default is selected, or nothing when it is not available")
    func goneStoredDeviceFallsBackLikeNeverChosen() {
        #expect(pick(externalMic.id, [iphoneMic], systemDefault: iphoneMic.id) == iphoneMic.id)
        #expect(pick(externalMic.id, [iphoneMic], systemDefault: externalMic.id) == "")
        #expect(pick(externalMic.id, []) == "")
    }

    @Test("Given camera or microphone access is denied or restricted for Recordy, when the list of devices is refreshed, then \"No camera\" or \"No microphone\" is shown")
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

    @Test("Given the chosen display is connected, when the list of displays is refreshed, then it stays selected")
    func chosenDisplayIsKept() {
        #expect(DeviceDefaults.display(current: external, available: [main, external], main: main) == external)
        #expect(DeviceDefaults.display(current: external, available: [external, other], main: main) == external)
    }

    @Test("Given the chosen display is no longer connected and the main display is connected, when the list of displays is refreshed, then the main display is selected")
    func mainDisplayWhenChosenIsGone() {
        #expect(DeviceDefaults.display(current: other, available: [external, main], main: main) == main)
    }

    @Test("Given neither the chosen display nor the main display is in the list and another display is connected, when the list of displays is refreshed, then the first display in the list is selected")
    func firstDisplayWhenNeitherIsAvailable() {
        #expect(DeviceDefaults.display(current: other, available: [external, 7], main: main) == external)
    }

    @Test("Given no display is listed, when the list of displays is refreshed, then the selection is left unchanged")
    func emptyDisplayListLeavesSelection() {
        #expect(DeviceDefaults.display(current: main, available: [], main: main) == nil)
    }
}

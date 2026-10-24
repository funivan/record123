import Foundation
import Carbon.HIToolbox

enum HotkeyAction: UInt32, CaseIterable {
    case toggleRecording = 1, zoomIn, zoomOut, cameraMove, cameraShape, cameraToggle, stopRecording

    var keyCode: UInt32 {
        switch self {
        case .toggleRecording: return UInt32(kVK_ANSI_R)
        case .zoomIn: return UInt32(kVK_ANSI_I)
        case .zoomOut: return UInt32(kVK_ANSI_O)
        case .cameraMove: return UInt32(kVK_ANSI_M)
        case .cameraShape: return UInt32(kVK_ANSI_N)
        case .cameraToggle: return UInt32(kVK_ANSI_H)
        case .stopRecording: return UInt32(kVK_ANSI_E)
        }
    }

    var keyLabel: String {
        switch self {
        case .toggleRecording: return "R"
        case .zoomIn: return "I"
        case .zoomOut: return "O"
        case .cameraMove: return "M"
        case .cameraShape: return "N"
        case .cameraToggle: return "H"
        case .stopRecording: return "E"
        }
    }

    var title: String {
        switch self {
        case .toggleRecording: return "Start / stop recording"
        case .zoomIn: return "Zoom in on cursor"
        case .zoomOut: return "Zoom out"
        case .cameraMove: return "Move camera to next corner"
        case .cameraShape: return "Change camera shape"
        case .cameraToggle: return "Show / hide camera"
        case .stopRecording: return "Stop recording and open in editor"
        }
    }

    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let modifierLabel = "⌃⌥⌘"
}

final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var handler: ((HotkeyAction) -> Void)?
    private var refs: [EventHotKeyRef?] = []
    private var installed = false

    func register() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = HotkeyAction(rawValue: id.id) {
                DispatchQueue.main.async { HotkeyCenter.shared.handler?(action) }
            }
            return noErr
        }, 1, &spec, nil, nil)
        for a in HotkeyAction.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x52434F52), id: a.rawValue)
            RegisterEventHotKey(a.keyCode, HotkeyAction.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
    }
}

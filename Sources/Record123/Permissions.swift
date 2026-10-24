import SwiftUI
import AVFoundation
import AppKit
import ScreenCaptureKit

enum PermissionKind: String, CaseIterable, Identifiable {
    case screen, mic, camera
    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen: return "Screen recording"
        case .mic: return "Microphone"
        case .camera: return "Camera"
        }
    }

    var icon: String {
        switch self {
        case .screen: return "display"
        case .mic: return "mic.fill"
        case .camera: return "video.fill"
        }
    }

    var detail: String {
        switch self {
        case .screen: return "Required to record your display."
        case .mic: return "Needed to record your voice."
        case .camera: return "Needed for the camera overlay."
        }
    }

    var required: Bool { self == .screen }

    var settingsURL: URL {
        let pane: String
        switch self {
        case .screen: pane = "Privacy_ScreenCapture"
        case .mic: pane = "Privacy_Microphone"
        case .camera: pane = "Privacy_Camera"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var granted: [PermissionKind: Bool] = [:]
    @Published var requestedScreen = false
    @Published var skipped = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func isGranted(_ k: PermissionKind) -> Bool { granted[k] ?? false }
    var screenOK: Bool { isGranted(.screen) }
    var allOK: Bool { PermissionKind.allCases.allSatisfy(isGranted) }

    func refresh() {
        var next: [PermissionKind: Bool] = [:]
        next[.screen] = CGPreflightScreenCaptureAccess()
        next[.mic] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        next[.camera] = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if next != granted { granted = next }
    }

    func configure(_ k: PermissionKind) {
        switch k {
        case .screen:
            if UserDefaults.standard.bool(forKey: "screenAccessRequested") {
                Task {
                    _ = try? await SCShareableContent.current
                    NSWorkspace.shared.open(k.settingsURL)
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            } else {
                UserDefaults.standard.set(true, forKey: "screenAccessRequested")
                CGRequestScreenCaptureAccess()
            }
            requestedScreen = true
        case .mic, .camera:
            let type: AVMediaType = k == .mic ? .audio : .video
            if AVCaptureDevice.authorizationStatus(for: type) == .notDetermined {
                AVCaptureDevice.requestAccess(for: type) { [weak self] _ in
                    DispatchQueue.main.async { self?.refresh() }
                }
            } else {
                NSWorkspace.shared.open(k.settingsURL)
            }
        }
    }

    nonisolated static func resetAndRelaunch() {
        let id = Bundle.main.bundleIdentifier ?? "com.funivan.record123"
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "All", id]
        try? reset.run()
        reset.waitUntilExit()
        UserDefaults.standard.removeObject(forKey: "screenAccessRequested")
        DispatchQueue.main.async { relaunchApp() }
    }

    func relaunch() { Self.relaunchApp() }

    nonisolated static func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

struct PermissionsSetupView: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield").font(.system(size: 44, weight: .thin)).foregroundStyle(Theme.signal)
            Text("Allow access to get started").font(Theme.serif(22, italic: true))
            Text("Record123 needs a few permissions from macOS before it can record.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                ForEach(PermissionKind.allCases) { k in PermissionStepRow(model: model, kind: k) }
            }
            .frame(maxWidth: 440)
            if model.screenOK {
                Button("Continue without them") { model.skipped = true }.buttonStyle(SoftButtonStyle())
            }
            if model.requestedScreen && !model.screenOK {
                VStack(spacing: 8) {
                    Text("Enabled Screen Recording in System Settings but it still shows as missing? macOS only applies it after the app restarts.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Restart Record123") { model.relaunch() }.buttonStyle(SoftButtonStyle())
                }
                .frame(maxWidth: 440)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PermissionStepRow: View {
    @ObservedObject var model: PermissionsModel
    let kind: PermissionKind

    var body: some View {
        let ok = model.isGranted(kind)
        HStack(spacing: 12) {
            Image(systemName: kind.icon).frame(width: 28).foregroundStyle(ok ? Color.green : Theme.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 13, weight: .medium))
                Text(kind.detail + (kind.required ? "" : " Optional.")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ok {
                Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12, weight: .medium))
            } else {
                Button("Configure") { model.configure(kind) }.buttonStyle(SoftButtonStyle())
            }
        }
        .padding(12)
        .background(Theme.bone.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PermissionsStatusBar: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        HStack(spacing: 14) {
            ForEach(PermissionKind.allCases) { k in
                if model.isGranted(k) {
                    Label("\(k.title) – OK", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { model.configure(k) } label: {
                        Label("\(k.title) – Configure", systemImage: "exclamationmark.triangle.fill").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.signal)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

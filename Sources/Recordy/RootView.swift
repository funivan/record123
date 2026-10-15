import SwiftUI
import AVFoundation
import ScreenCaptureKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        ZStack {
            AppBackground()
            if let editor = state.editor {
                EditorView(model: editor)
            } else {
                HomeView()
            }
        }
        .alert("Recordy", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .onAppear { state.refreshDevices() }
        .preferredColorScheme(themes.palette.scheme)
        .tint(themes.palette.accent)
        .id(themes.kind)
    }
}

enum RecorderPanel: String, OrderedPanel {
    case screen, camera, audio

    static let defaultOrder: [RecorderPanel] = [.screen, .audio, .camera]

    var title: String {
        switch self {
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .audio: return "Audio"
        }
    }

    var icon: String {
        switch self {
        case .screen: return "display"
        case .camera: return "video.fill"
        case .audio: return "mic.fill"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(PanelOrder.recorderKey) private var recorderOrder = ""

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Recordy").font(Theme.serif(26, italic: true))
                            if Theme.p.surface != nil {
                                Text("Screen · Camera · Signal").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.bone.opacity(0.5))
                            } else {
                                Text("SCREEN · CAMERA · SIGNAL").font(Theme.mono(9.5)).tracking(1.6).foregroundStyle(Theme.signal)
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    if Theme.inverseSurface != nil { recordTile }

                    ForEach(recorderPanels, id: \.self) { panel in
                        switch panel {
                        case .screen: screenCard
                        case .camera: cameraCard
                        case .audio: audioCard
                        }
                    }

                    if Theme.inverseSurface == nil { HStack(spacing: 10) {
                        Button { state.toggleTest() } label: {
                            Label(state.testing ? "Stop test" : "Test setup", systemImage: state.testing ? "stop.fill" : "waveform.and.mic")
                        }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(state.isBusy)

                        Button { state.toggleRecording() } label: {
                            Label(buttonTitle, systemImage: "record.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GradientButtonStyle(gradient: Theme.record))
                        .disabled(state.phase == .saving || state.phase == .recording)
                    } }
                    if state.testing {
                        Text(state.selectedCamera.isEmpty ? "Speak to see the level on your screen." : "Camera and mic level are shown on your screen at the chosen corner.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .frame(width: 400)
            .onChange(of: state.startCorner) { _, _ in state.applyTestLayout() }
            .onChange(of: state.startShape) { _, _ in state.applyTestLayout() }

            Rectangle().fill(Theme.bone.opacity(0.08)).frame(width: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text("Recordings").font(Theme.serif(24, italic: true))
                if state.projects.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "record.circle").font(.system(size: 44, weight: .thin)).foregroundStyle(Theme.signal)
                        Text("Nothing on tape yet").font(Theme.serif(20, italic: true))
                        Text("Press Record or \(HotkeyAction.modifierLabel)R to start.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
                            ForEach(state.projects) { ref in ProjectCard(ref: ref) }
                        }
                    }
                }
                HotkeysPanel()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var recorderPanels: [RecorderPanel] { PanelOrder.load(recorderOrder) }

    var screenCard: some View {
        Card(title: "Screen", icon: "display") {
            Picker("", selection: $state.selectedDisplay) {
                ForEach(state.displays, id: \.displayID) { Text(state.displayName($0)).tag($0.displayID) }
            }
            .labelsHidden()
            PillSegmented(options: [(false, "Full display"), (true, "Selected area")], selection: $state.captureArea)
            if state.captureArea {
                HStack {
                    Text(state.activeRegion(for: state.selectedDisplay).map { "\(Int($0.width)) × \(Int($0.height)) at \(Int($0.minX)), \(Int($0.minY))" } ?? "No area selected on this display")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(state.activeRegion(for: state.selectedDisplay) == nil ? "Select area…" : "Change area…") { state.chooseArea() }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    var cameraCard: some View {
        Card(title: "Camera", icon: "video.fill") {
            Picker("", selection: $state.selectedCamera) {
                Text("No camera").tag("")
                ForEach(state.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            .labelsHidden()
            if !state.selectedCamera.isEmpty {
                HStack {
                    Picker("Shape", selection: $state.startShape) {
                        ForEach(CameraShape.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Position", selection: $state.startCorner) {
                        ForEach(CameraCorner.allCases) { Text($0.label).tag($0) }
                    }
                }
                Toggle("Blur background", isOn: $state.cameraBlur)
                    .help("Blur everything behind you. You can change it later in the editor.")
                cameraPreview
            }
        }
    }

    var audioCard: some View {
        Card(title: "Audio", icon: "mic.fill") {
            Picker("", selection: $state.selectedMic) {
                Text("No microphone").tag("")
                ForEach(state.mics, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            .labelsHidden()
            if !state.selectedMic.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                    LevelBar(level: state.testing ? state.micLevel : 0)
                }
            }
            Toggle("Record system audio", isOn: $state.systemAudio)
        }
    }

    @ViewBuilder var cameraPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4))
            if state.testing && state.testHasCamera {
                CameraPreview(session: state.previewSession)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Label("Press “Test setup” for live preview", systemImage: "video.slash").font(.caption).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    var recordTile: some View {
        let recording = state.phase == .recording
        let busy = state.isBusy
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording ? "Recording" : "Ready to record").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Text(recording ? formatTime(state.elapsed) : buttonTitle == "Record" ? "00:00" : buttonTitle)
                    .font(.system(size: 34, weight: .medium)).monospacedDigit().foregroundStyle(.white)
            }
            HStack(alignment: .bottom) {
                Button { state.toggleTest() } label: {
                    Label(state.testing ? "Stop test" : "Test setup", systemImage: state.testing ? "stop.fill" : "waveform.and.mic")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Spacer()
                Button { state.toggleRecording() } label: {
                    Text(recording ? "Stop" : state.phase == .saving ? "Saving" : busy ? "Cancel" : "Record")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Theme.signal, in: Capsule())
                        .shadow(color: Theme.signal.opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(state.phase == .saving)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground(radius: Theme.p.radius, dark: true)
    }

    var buttonTitle: String {
        switch state.phase {
        case .idle: return "Record"
        case .countdown(let n): return "Starting in \(n)…"
        case .recording: return "Recording…"
        case .saving: return "Saving…"
        }
    }
}

struct HotkeysPanel: View {
    @EnvironmentObject var state: AppState
    @State private var showAll = false

    var body: some View {
        if state.projects.isEmpty {
            Card(title: "Hotkeys", icon: "keyboard") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(HotkeyAction.allCases, id: \.rawValue) { HotkeyRow(action: $0) }
                }
            }
        } else {
            HStack(spacing: 16) {
                HotkeyKey(action: .toggleRecording)
                Text("Record").font(.caption).foregroundStyle(.secondary)
                HotkeyKey(action: .stopRecording)
                Text("Stop recording").font(.caption).foregroundStyle(.secondary)
                Button("All hotkeys") { showAll = true }
                    .buttonStyle(SoftButtonStyle())
                    .popover(isPresented: $showAll, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(HotkeyAction.allCases, id: \.rawValue) { HotkeyRow(action: $0) }
                        }
                        .padding(16)
                    }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct HotkeyRow: View {
    let action: HotkeyAction

    var body: some View {
        HStack {
            HotkeyKey(action: action)
            Text(action.title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HotkeyKey: View {
    let action: HotkeyAction

    var body: some View {
        Text("\(HotkeyAction.modifierLabel)\(action.keyLabel)")
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.bone.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct RecordingDropDelegate: DropDelegate {
    let target: ProjectRef
    let state: AppState
    @Binding var edge: VerticalEdge?
    let height: CGFloat

    func validateDrop(info: DropInfo) -> Bool { state.draggingRecording != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = info.location.y < height / 2 ? .top : .bottom
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { edge = nil }

    func performDrop(info: DropInfo) -> Bool {
        let after = edge == .bottom
        edge = nil
        guard let dragged = state.draggingRecording else { return false }
        state.draggingRecording = nil
        state.moveRecording(dragged, relativeTo: target, after: after)
        return true
    }
}

struct ProjectCard: View {
    @EnvironmentObject var state: AppState
    let ref: ProjectRef
    @State private var hover = false
    @State private var dropEdge: VerticalEdge?
    @State private var height: CGFloat = 0

    var body: some View {
        let dark = Theme.inverseSurface != nil
        let radius = Theme.p.surface != nil ? Theme.p.radius : 14
        VStack(alignment: .leading, spacing: 0) {
            VideoThumb(dir: ref.dir)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: dark ? radius - 10 : 0, style: .continuous))
                .padding(dark ? 10 : 0)
                .overlay(alignment: .bottomTrailing) {
                    Text(formatTime(ref.duration)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 2)
                        .padding(8)
                }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.name.replacingOccurrences(of: "Recording ", with: "")).font(Theme.serif(14)).lineLimit(1)
                        .foregroundStyle(dark ? Color.white : Theme.bone)
                    Text(ref.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        .foregroundStyle(dark ? Color.white.opacity(0.5) : Theme.bone.opacity(0.5))
                }
                Spacer()
                Menu {
                    Button("Edit") { state.open(ref.dir) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ref.dir]) }
                    Button("Move to Trash", role: .destructive) { state.delete(ref) }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(dark ? Color.white.opacity(0.6) : Theme.bone.opacity(0.6)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(dark ? EdgeInsets(top: 4, leading: 14, bottom: 14, trailing: 14) : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        }
        .tileBackground(radius: radius, hover: hover, dark: dark)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(alignment: dropEdge == .bottom ? .bottom : .top) {
            if dropEdge != nil {
                Capsule().fill(Theme.signal).frame(height: 4).padding(.horizontal, 8)
                    .offset(y: dropEdge == .bottom ? 2 : -2)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { height = proxy.size.height }
                .onChange(of: proxy.size.height) { _, new in height = new }
        })
        .onHover { hover = $0 }
        .onTapGesture { state.open(ref.dir) }
        .onDrag {
            state.draggingRecording = ref
            return NSItemProvider(object: ref.dir.lastPathComponent as NSString)
        }
        .onDrop(of: [.text], delegate: RecordingDropDelegate(target: ref, state: state, edge: $dropEdge, height: height))
    }
}

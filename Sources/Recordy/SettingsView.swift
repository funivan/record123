import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            RecordingSettings()
                .tabItem { Label("Recording", systemImage: "record.circle") }
            PanelSettings()
                .tabItem { Label("Panels", systemImage: "sidebar.squares.left") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 580)
        .preferredColorScheme(themes.palette.scheme)
    }
}

struct AppearanceSettings: View {
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Theme").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(ThemeKind.allCases) { kind in
                        ThemeCard(kind: kind, selected: themes.kind == kind) { themes.kind = kind }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct ThemeCard: View {
    let kind: ThemeKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let p = ThemeStore.palette(for: kind)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.bg)
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(p.text.opacity(0.8)).frame(width: 46, height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(p.text.opacity(0.25)).frame(width: 34, height: 5)
                            RoundedRectangle(cornerRadius: 6).fill(p.surface ?? p.text.opacity(0.1)).frame(width: 60, height: 26)
                            Capsule().fill(LinearGradient(colors: [p.accent, p.accentB], startPoint: .leading, endPoint: .trailing)).frame(width: 52, height: 12)
                        }
                        Spacer()
                        VStack(spacing: 5) {
                            Circle().fill(p.accent).frame(width: 14, height: 14)
                            Circle().fill(p.accent2).frame(width: 14, height: 14)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.system(size: 13, weight: .semibold))
                        Text(kind.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(selected ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title) theme")
    }
}

struct RecordingSettings: View {
    @AppStorage("countdown") private var countdown = 3
    @AppStorage("fps") private var fps = 60
    @AppStorage("showCursor") private var showCursor = true

    var body: some View {
        Form {
            Picker("Countdown", selection: $countdown) {
                Text("None").tag(0); Text("3 seconds").tag(3); Text("5 seconds").tag(5)
            }
            Picker("Frame rate", selection: $fps) {
                Text("30 fps").tag(30); Text("60 fps").tag(60)
            }
            Toggle("Capture mouse cursor", isOn: $showCursor)
            Text("Recordings are saved to ~/Movies/Recordy.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct PanelSettings: View {
    @AppStorage(PanelOrder.recorderKey) private var recorderOrder = ""
    @AppStorage(PanelOrder.inspectorKey) private var inspectorOrder = ""

    var body: some View {
        Form {
            Section("Recorder panels (top to bottom)") {
                PanelOrderEditor<RecorderPanel>(stored: $recorderOrder)
            }
            Section("Editor panels (top to bottom)") {
                PanelOrderEditor<InspectorSection>(stored: $inspectorOrder)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section("Global hotkeys (work while recording in any app)") {
                ForEach(HotkeyAction.allCases, id: \.rawValue) { a in
                    LabeledContent(a.title) {
                        Text("\(HotkeyAction.modifierLabel)\(a.keyLabel)").font(.system(.body, design: .monospaced))
                    }
                }
            }
            Section("Editor") {
                LabeledContent("Play / pause") { Text("Space").font(.system(.body, design: .monospaced)) }
                LabeledContent("Undo / redo") { Text("⌘Z  ⇧⌘Z").font(.system(.body, design: .monospaced)) }
                LabeledContent("Export") { Text("⌘E").font(.system(.body, design: .monospaced)) }
                LabeledContent("Toggle inspector") { Text("⌥⌘I").font(.system(.body, design: .monospaced)) }
            }
        }
        .formStyle(.grouped)
    }
}

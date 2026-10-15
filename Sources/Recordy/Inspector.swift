import SwiftUI
import ImageIO

struct Section_<Content: View>: View {
    let title: String
    var icon: String
    @AppStorage private var expanded: Bool
    @ViewBuilder let content: Content

    init(title: String, icon: String = "slider.horizontal.3", expanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        _expanded = AppStorage(wrappedValue: expanded, "inspector.expanded.\(title)")
        self.content = content()
    }

    var body: some View { Card(title: title, icon: icon, expanded: $expanded) { content } }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label); Spacer(); Text(format(value)).foregroundStyle(.secondary).monospacedDigit() }.font(.callout)
            Slider(value: $value, in: range)
        }
    }
}

enum InspectorSection: String, OrderedPanel {
    case layout, background, camera, zoom, audio, trim

    static let defaultOrder: [InspectorSection] = [.layout, .zoom, .background, .camera, .audio, .trim]

    var title: String {
        switch self {
        case .layout: return "Layout"
        case .background: return "Background"
        case .camera: return "Camera"
        case .zoom: return "Zoom"
        case .audio: return "Audio"
        case .trim: return "Trim"
        }
    }

    var icon: String {
        switch self {
        case .layout: return "rectangle.inset.filled"
        case .background: return "paintpalette.fill"
        case .camera: return "video.fill"
        case .zoom: return "plus.magnifyingglass"
        case .audio: return "waveform"
        case .trim: return "scissors"
        }
    }
}

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @AppStorage(PanelOrder.inspectorKey) private var orderStorage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(order, id: \.self) { section in
                    content(for: section)
                        .contextMenu {
                            Button("Move up") { PanelOrder.move(section, by: -1, in: &orderStorage) }.disabled(order.first == section)
                            Button("Move down") { PanelOrder.move(section, by: 1, in: &orderStorage) }.disabled(order.last == section)
                            Divider()
                            Button("Reset order") { orderStorage = "" }
                        }
                }
            }
            .padding(12)
        }
    }

    private var style: Binding<Style> { $model.project.style }

    private var order: [InspectorSection] { PanelOrder.load(orderStorage) }

    @ViewBuilder
    private func content(for section: InspectorSection) -> some View {
        switch section {
        case .layout: layout
        case .background: background
        case .camera: if model.project.cameraFile != nil { camera }
        case .zoom: zoom
        case .audio: audio
        case .trim: trim
        }
    }

    var layout: some View {
        Section_(title: "Layout", icon: "rectangle.inset.filled", expanded: true) {
            HStack {
                Button { model.applyFullScreen() } label: { Label("Full screen", systemImage: "rectangle.dashed") }
                Button { model.applyFramed() } label: { Label("Framed", systemImage: "rectangle.inset.filled") }
            }
            .buttonStyle(SoftButtonStyle())
            Picker("Aspect", selection: style.aspect) {
                ForEach(AspectChoice.allCases) { Text($0.label).tag($0) }
            }
            Picker("Resolution", selection: style.resolution) {
                Text("Native").tag(0)
                Text("720p").tag(720); Text("1080p").tag(1080); Text("1440p").tag(1440); Text("4K").tag(2160)
            }
            LabeledSlider(label: "Spacing", value: style.padding, range: 0...0.25) { "\(Int($0 * 100))%" }
            LabeledSlider(label: "Corner radius", value: style.cornerRadius, range: 0...0.08) { "\(Int($0 * 1000))" }
            LabeledSlider(label: "Shadow", value: style.shadow, range: 0...1) { "\(Int($0 * 100))%" }
            LabeledSlider(label: "Border", value: style.screenBorder, range: 0...16) { "\(Int($0)) px" }
            if model.project.style.screenBorder > 0 {
                ColorPicker("Border color", selection: Binding(get: { style.wrappedValue.screenBorderColor.color }, set: { model.project.style.screenBorderColor.color = $0 }), supportsOpacity: true)
            }
        }
    }

    var background: some View {
        Section_(title: "Background", icon: "paintpalette.fill", expanded: true) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(BackgroundPreset.all) { p in
                    Button {
                        model.project.style.bgColor1 = p.c1
                        model.project.style.bgColor2 = p.c2
                        model.project.style.bgGradient = p.gradient
                        model.project.style.bgImageFile = nil
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [p.c1.color, p.c2.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .help(p.name)
                }
            }
            Text("Wallpapers").font(.callout.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Wallpapers.all, id: \.self) { url in
                    Button { model.applyWallpaper(url) } label: {
                        WallpaperThumb(url: url)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.project.style.bgImageFile == url.lastPathComponent ? Theme.signal : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(url.deletingPathExtension().lastPathComponent)
                }
            }
            HStack {
                Button("Choose image…") { model.chooseBackgroundImage() }.buttonStyle(SoftButtonStyle())
                if model.project.style.bgImageFile != nil {
                    Button("Remove image") { model.project.style.bgImageFile = nil }.buttonStyle(SoftButtonStyle())
                }
            }
            Picker("Pattern", selection: style.bgPattern) {
                ForEach(BgPattern.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Gradient", isOn: style.bgGradient).disabled(model.project.style.bgImageFile != nil)
            HStack {
                ColorPicker("Color 1", selection: Binding(get: { style.wrappedValue.bgColor1.color }, set: { model.project.style.bgColor1.color = $0 }))
                if model.project.style.bgGradient {
                    ColorPicker("Color 2", selection: Binding(get: { style.wrappedValue.bgColor2.color }, set: { model.project.style.bgColor2.color = $0 }))
                }
            }
        }
    }

    var camera: some View {
        Section_(title: "Camera", icon: "video.fill") {
            LabeledSlider(label: "Size", value: style.cameraSize, range: 0.1...0.45) { "\(Int($0 * 100))%" }
            Toggle("Mirror", isOn: style.cameraMirror)
            Toggle("Blur background", isOn: style.cameraBlur)
            LabeledSlider(label: "Border", value: style.cameraBorder, range: 0...16) { "\(Int($0)) px" }
            if model.project.style.cameraBorder > 0 {
                ColorPicker("Border color", selection: Binding(get: { style.wrappedValue.cameraBorderColor.color }, set: { model.project.style.cameraBorderColor.color = $0 }))
            }
            Divider()
            HStack {
                Text("Camera changes").font(.callout.bold())
                Spacer()
                Button("Add at playhead") { model.addCameraKey(at: model.time) }
            }
            Text("Position at playhead, or drag the camera in the preview:")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(CameraCorner.allCases) { c in
                    Button(c.shortLabel) { model.setCameraPosition(at: model.time, anchor: c.unit) }
                        .buttonStyle(SoftButtonStyle())
                        .help(c.label)
                }
            }
            Button(model.cameraVisibleAtPlayhead ? "Hide camera at playhead" : "Show camera at playhead") {
                model.setCameraVisible(!model.cameraVisibleAtPlayhead)
            }
            .buttonStyle(SoftButtonStyle())
            ForEach(model.project.cameraKeys) { k in
                let kb = cameraKeyBinding(k)
                let selected = model.selectedCamera == k.id
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(formatTime(k.time)).monospacedDigit()
                        Text("\(k.visible ? k.shape.label : "Hidden") · \(k.corner.label)").foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button { model.seek(to: k.time) } label: { Image(systemName: "scope") }.buttonStyle(.borderless)
                        Button(role: .destructive) { model.project.cameraKeys.removeAll { $0.id == k.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .disabled(model.project.cameraKeys.count <= 1)
                    }
                    if selected {
                        Picker("Shape", selection: kb.shape) { ForEach(CameraShape.allCases) { Text($0.label).tag($0) } }
                        Picker("Corner", selection: cornerBinding(kb)) { ForEach(CameraCorner.allCases) { Text($0.label).tag($0) } }
                        LabeledSlider(label: "Move duration", value: moveDurationBinding(kb), range: 0.1...1.5) { String(format: "%.1fs", $0) }
                        Toggle("Visible", isOn: kb.visible)
                    }
                }
                .padding(8)
                .background(selected ? Theme.camera.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { model.selectedCamera = k.id; model.selectedZoom = nil }
            }
        }
    }

    private func cameraKeyBinding(_ k: CameraKey) -> Binding<CameraKey> {
        Binding(get: { model.project.cameraKeys.first { $0.id == k.id } ?? k },
                set: { v in if let i = model.project.cameraKeys.firstIndex(where: { $0.id == k.id }) { model.project.cameraKeys[i] = v } })
    }

    private func moveDurationBinding(_ k: Binding<CameraKey>) -> Binding<Double> {
        Binding(get: { k.wrappedValue.moveDuration ?? model.project.style.cameraMoveDuration }, set: { k.wrappedValue.moveDuration = $0 })
    }

    private func cornerBinding(_ k: Binding<CameraKey>) -> Binding<CameraCorner> {
        Binding(get: { k.wrappedValue.corner }, set: { c in
            k.wrappedValue.corner = c
            k.wrappedValue.x = nil
            k.wrappedValue.y = nil
        })
    }

    var zoom: some View {
        Section_(title: "Zoom", icon: "plus.magnifyingglass") {
            LabeledSlider(label: "Default zoom", value: style.zoomLevel, range: 1.2...4) { String(format: "%.1f×", $0) }
            LabeledSlider(label: "Default ease", value: style.zoomDuration, range: 0.2...2) { String(format: "%.1fs", $0) }
            LabeledSlider(label: "Cursor smoothing", value: style.cursorSmoothing, range: 0...1) { String(format: "%.2f", $0) }
            HStack {
                Text("Zoom steps").font(.callout.bold())
                Spacer()
                Button("Add at playhead") { model.addZoom(at: model.time) }
            }
            ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { idx, g in
                let selected = model.selectedZoom == g.id
                let bind = Binding<ZoomSegment>(
                    get: { model.project.zoomSegments?.first(where: { $0.id == g.id }) ?? g },
                    set: { v in if let i = model.project.zoomSegments?.firstIndex(where: { $0.id == g.id }) { model.project.zoomSegments?[i] = v } })
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(formatTime(g.start)) – \(formatTime(g.end))").monospacedDigit()
                        Text(String(format: "%.1f×", g.scale)).foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button { model.seek(to: g.start) } label: { Image(systemName: "scope") }.buttonStyle(.borderless)
                        Button(role: .destructive) { model.project.zoomSegments?.removeAll { $0.id == g.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    if selected {
                        LabeledSlider(label: "Start", value: bind.start, range: 0...max(g.end - 0.3, 0.3)) { formatTime($0) }
                        LabeledSlider(label: "End", value: bind.end, range: (g.start + 0.3)...max(model.project.duration, g.start + 0.31)) { formatTime($0) }
                        LabeledSlider(label: "Scale", value: bind.scale, range: 1.1...5) { String(format: "%.1f×", $0) }
                        LabeledSlider(label: "Fade in", value: bind.easeIn, range: 0.1...2) { String(format: "%.1fs", $0) }
                        LabeledSlider(label: "Fade out", value: bind.easeOut, range: 0.1...2) { String(format: "%.1fs", $0) }
                        Toggle("Follow cursor", isOn: bind.follow)
                        Button {
                            model.pickingFocus.toggle()
                        } label: {
                            Label(model.pickingFocus ? "Done picking" : "Pick focus on preview", systemImage: "scope")
                        }
                        .buttonStyle(SoftButtonStyle())
                        if !g.follow {
                            Text(String(format: "Focus at %.0f%%, %.0f%%", g.fx * 100, g.fy * 100)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(selected ? Theme.signal.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { model.selectedZoom = g.id; model.selectedCamera = nil }
            }
        }
    }

    var audio: some View {
        Section_(title: "Audio", icon: "waveform") {
            HStack {
                Button { model.splitAudio(at: model.time) } label: { Label("Split", systemImage: "scissors") }
                    .help("Cut the selected clip (or all clips) at the playhead")
                Button { model.addMusic() } label: { Label("Add", systemImage: "music.note") }
                    .help("Add an audio file at the playhead")
                Button { model.toggleVoiceRecording() } label: {
                    Label(model.isRecordingVoice ? "Stop" : "Record", systemImage: model.isRecordingVoice ? "stop.fill" : "mic.fill")
                }
                .tint(model.isRecordingVoice ? .red : nil)
                .help("Record extra voice at the playhead while the video plays")
            }
            .buttonStyle(SoftButtonStyle())
            if model.isRecordingVoice {
                Text("Recording voice… press Stop or Space to finish.").font(.caption).foregroundStyle(.red)
            }
            ForEach(model.project.audioClips ?? []) { c in
                let selected = model.selectedAudio == c.id
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: c.kind.icon).frame(width: 16).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.title).lineLimit(1)
                            Text("\(formatTime(c.start)) – \(formatTime(c.end))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Button { model.toggleMute(c.id) } label: { Image(systemName: c.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                            .buttonStyle(.borderless)
                            .help(c.muted ? "Unmute" : "Mute")
                        Button { model.seek(to: c.start) } label: { Image(systemName: "scope") }.buttonStyle(.borderless)
                        Button(role: .destructive) { model.deleteAudio(c.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    if selected {
                        HStack {
                            Text("Volume").font(.callout)
                            Slider(value: Binding(
                                get: { model.project.audioClips?.first(where: { $0.id == c.id })?.volume ?? 1 },
                                set: { v in if let i = model.project.audioClips?.firstIndex(where: { $0.id == c.id }) { model.project.audioClips?[i].volume = v } }),
                                   in: 0...2) { editing in if !editing { model.commitAudio() } }
                            Text("\(Int(c.volume * 100))%").font(.callout).foregroundStyle(.secondary).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(8)
                .background(selected ? Color.purple.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { model.selectedAudio = c.id; model.selectedZoom = nil; model.selectedCamera = nil }
            }
            if (model.project.audioClips ?? []).isEmpty {
                Text("No audio in this recording. Add music or record a voice-over.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var trim: some View {
        Section_(title: "Trim", icon: "scissors") {
            HStack {
                Text("Start"); Spacer()
                Text(formatTime(model.project.trimStart)).monospacedDigit()
                Button("Set to playhead") { model.setTrimStart(model.time); model.commitTrim() }
            }
            HStack {
                Text("End"); Spacer()
                Text(formatTime(model.project.trimEnd)).monospacedDigit()
                Button("Set to playhead") { model.setTrimEnd(model.time); model.commitTrim() }
            }
            Button("Reset trim") {
                model.project.trimStart = 0
                model.project.trimEnd = model.project.duration
                model.commitTrim()
            }
        }
    }
}

struct WallpaperThumb: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .task(id: url) {
            let u = url
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 360] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: .zero)
            }.value
        }
    }
}

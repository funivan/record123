import SwiftUI
import AVFoundation
import AppKit

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let l = AVPlayerLayer(player: player)
        l.videoGravity = .resizeAspect
        l.frame = v.bounds
        l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer = CALayer()
        v.layer?.backgroundColor = NSColor.black.cgColor
        v.layer?.addSublayer(l)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct EditorView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: EditorModel
    @State private var showInspector = true
    @AppStorage("inspector.width") private var inspectorWidth = 340.0
    @State private var dragStartWidth: Double?

    var body: some View {
        HStack(spacing: 0) {
            editorColumn
            if showInspector {
                Divider()
                InspectorView(model: model)
                    .frame(width: inspectorWidth)
                    .overlay(alignment: .leading) { inspectorResizeHandle }
            }
        }
        .navigationTitle(model.project.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { app.closeEditor() } label: { Label("Recordings", systemImage: "chevron.backward") }
                    .help("Back to recordings (⌘[)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                ExportBar(model: model)
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Show or hide the inspector (⌥⌘I)")
            }
        }
        .onKeyPress(.space) { model.togglePlay(); return .handled }
        .alert("Recordy", isPresented: Binding(get: { model.loadError != nil }, set: { if !$0 { model.loadError = nil } })) {
            Button("OK") { model.loadError = nil }
        } message: { Text(model.loadError ?? "") }
    }

    private var inspectorResizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { v in
                if dragStartWidth == nil { dragStartWidth = inspectorWidth }
                inspectorWidth = min(440, max(300, (dragStartWidth ?? inspectorWidth) - v.translation.width))
            }.onEnded { _ in dragStartWidth = nil })
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            preview
                .padding(.top, 8)
            transport
            TimelineView(model: model)
                .frame(height: TimelineView.height(for: model.project))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if model.croppingArea {
            CropEditorView(model: model)
                .padding(.horizontal, 14)
        } else {
            PlayerView(player: model.player)
                .aspectRatio(outputSize(for: model.project).width / outputSize(for: model.project).height, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)
                .overlay { if model.project.cameraFile != nil { CameraDragLayer(model: model) } }
                .overlay { if model.pickingFocus && model.selectedZoom != nil { FocusPickerLayer(model: model) } }
        }
    }

    var transport: some View {
        HStack(spacing: 14) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
            }
            .keyboardShortcut(.space, modifiers: [])
            Text("\(formatTime(model.time - model.project.trimStart)) / \(formatTime(model.project.trimmedDuration))")
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

struct ExportBar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var exporter: Exporter

    init(model: EditorModel) {
        self.model = model
        exporter = model.exporter
    }

    var body: some View {
        HStack {
            if exporter.running {
                ProgressView(value: exporter.progress).frame(width: 140)
            } else if let out = exporter.lastOutput {
                Button("Reveal export") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
            }
            if let e = exporter.error { Text(e).foregroundStyle(.red).font(.caption).lineLimit(1) }
            Button { model.runExportPanel() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
                .help("Export as MP4 (⌘E)")
                .disabled(exporter.running)
        }
    }
}

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    private let handleW: CGFloat = 10
    @State private var zoomDragBase: ZoomSegment?
    @State private var audioDragBase: AudioClip?

    static let audioTop: CGFloat = 146
    static let laneH: CGFloat = 30

    static func laneMap(_ clips: [AudioClip]) -> [UUID: Int] {
        var ends: [Double] = []
        var out: [UUID: Int] = [:]
        for c in clips.sorted(by: { $0.start < $1.start }) {
            if let i = ends.firstIndex(where: { $0 <= c.start + 0.001 }) {
                ends[i] = c.end; out[c.id] = i
            } else {
                ends.append(c.end); out[c.id] = ends.count - 1
            }
        }
        return out
    }

    static func height(for p: Project) -> CGFloat {
        let lanes = max((laneMap(p.audioClips ?? []).values.max() ?? -1) + 1, 1)
        return audioTop + CGFloat(lanes) * laneH + 6
    }

    private func audioColor(_ k: AudioKind) -> Color {
        switch k {
        case .system: return Color.teal
        case .mic: return Theme.lime
        case .music: return Color.purple
        case .voice: return Color.orange
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(model.project.duration, 0.1)
            let x: (Double) -> CGFloat = { CGFloat($0 / dur) * w }
            let t: (CGFloat) -> Double = { Double(min(max($0, 0), w) / w) * dur }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.18)).frame(height: 44).offset(y: 22)

                RoundedRectangle(cornerRadius: 6).fill(Theme.signal.opacity(0.28))
                    .frame(width: max(0, x(model.project.trimEnd) - x(model.project.trimStart)), height: 44)
                    .offset(x: x(model.project.trimStart), y: 22)

                ForEach(ticks(dur), id: \.self) { s in
                    Text(formatTime(s)).font(.system(size: 9)).foregroundStyle(.secondary).offset(x: x(s) + 2, y: 4)
                    Rectangle().fill(Color.gray.opacity(0.4)).frame(width: 1, height: 8).offset(x: x(s), y: 14)
                }

                Text("Zoom").font(.system(size: 9)).foregroundStyle(.secondary).offset(x: 2, y: 72)
                ForEach(model.project.segments) { g in
                    let sel = model.selectedZoom == g.id
                    let wBar = max(x(g.end) - x(g.start), 16)
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(Theme.signal.opacity(sel ? 0.95 : 0.6))
                        Text(String(format: "%.1f×", g.scale)).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onAccent)
                        HStack {
                            Rectangle().fill(Color.white.opacity(0.9)).frame(width: 3)
                                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl")).onChanged { v in
                                    model.selectedZoom = g.id; model.selectedCamera = nil
                                    if let i = model.project.zoomSegments?.firstIndex(where: { $0.id == g.id }) {
                                        model.project.zoomSegments?[i].start = min(t(v.location.x), g.end - 0.3)
                                    }
                                })
                            Spacer()
                            Rectangle().fill(Color.white.opacity(0.9)).frame(width: 3)
                                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl")).onChanged { v in
                                    model.selectedZoom = g.id; model.selectedCamera = nil
                                    if let i = model.project.zoomSegments?.firstIndex(where: { $0.id == g.id }) {
                                        model.project.zoomSegments?[i].end = min(max(t(v.location.x), g.start + 0.3), model.project.duration)
                                    }
                                })
                        }
                    }
                    .frame(width: wBar, height: 18)
                    .offset(x: x(g.start), y: 82)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("tl")).onChanged { v in
                        model.selectedZoom = g.id; model.selectedCamera = nil
                        let base = zoomDragBase ?? g
                        if zoomDragBase == nil { zoomDragBase = g }
                        let dt = Double(v.translation.width / w) * dur
                        let len = base.end - base.start
                        let ns = min(max(base.start + dt, 0), max(model.project.duration - len, 0))
                        if let i = model.project.zoomSegments?.firstIndex(where: { $0.id == g.id }) {
                            model.project.zoomSegments?[i].start = ns
                            model.project.zoomSegments?[i].end = ns + len
                        }
                    }.onEnded { _ in zoomDragBase = nil })
                    .simultaneousGesture(TapGesture().onEnded { model.selectedZoom = g.id; model.selectedCamera = nil })
                }
                if model.project.cameraFile != nil {
                    Text("Camera").font(.system(size: 9)).foregroundStyle(.secondary).offset(x: 2, y: 100)
                    ForEach(model.project.cameraKeys) { k in
                        Marker(color: Theme.camera, selected: model.selectedCamera == k.id, label: k.visible ? String(k.shape.label.prefix(1)) : "×")
                            .offset(x: x(k.time) - 14, y: 112)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl")).onChanged { v in
                                model.selectedCamera = k.id; model.selectedZoom = nil
                                if let i = model.project.cameraKeys.firstIndex(where: { $0.id == k.id }) {
                                    model.project.cameraKeys[i].time = t(v.location.x)
                                }
                            }.onEnded { _ in model.project.cameraKeys.sort { $0.time < $1.time } })
                    }
                }

                Text("Audio").font(.system(size: 9)).foregroundStyle(.secondary).offset(x: 2, y: 134)
                let clips = model.project.audioClips ?? []
                let lanes = TimelineView.laneMap(clips)
                ForEach(clips) { c in
                    audioClip(c, lane: lanes[c.id] ?? 0, x: x, t: t, w: w, dur: dur)
                }

                Color.clear.contentShape(Rectangle()).frame(height: 44).offset(y: 22)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in model.seek(to: t(v.location.x)) })

                RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: handleW, height: 44)
                    .offset(x: x(model.project.trimStart) - handleW, y: 22)
                    .gesture(DragGesture(coordinateSpace: .named("tl")).onChanged { v in model.setTrimStart(t(v.location.x + handleW / 2)) }
                        .onEnded { _ in model.commitTrim() })
                RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: handleW, height: 44)
                    .offset(x: x(model.project.trimEnd), y: 22)
                    .gesture(DragGesture(coordinateSpace: .named("tl")).onChanged { v in model.setTrimEnd(t(v.location.x - handleW / 2)) }
                        .onEnded { _ in model.commitTrim() })

                Rectangle().fill(Theme.bone).frame(width: 2, height: geo.size.height - 20).offset(x: x(model.time) - 1, y: 14).allowsHitTesting(false)
            }
            .coordinateSpace(name: "tl")
        }
    }

    @ViewBuilder
    private func audioClip(_ c: AudioClip, lane: Int, x: (Double) -> CGFloat, t: @escaping (CGFloat) -> Double, w: CGFloat, dur: Double) -> some View {
        let sel = model.selectedAudio == c.id
        let color = audioColor(c.kind)
        let wBar = max(x(c.end) - x(c.start), 10)
        let update: ((inout AudioClip) -> Void) -> Void = { edit in
            if let i = model.project.audioClips?.firstIndex(where: { $0.id == c.id }) { edit(&model.project.audioClips![i]) }
        }
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(color.opacity(sel ? 0.5 : 0.28))
            WaveformView(url: model.dir.appendingPathComponent(c.file), srcStart: c.srcStart, duration: c.duration, color: color)
                .padding(.vertical, 2)
            HStack(spacing: 3) {
                Image(systemName: c.muted ? "speaker.slash.fill" : c.kind.icon)
                Text(c.title).lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1)
            .padding(.leading, 7)
            .allowsHitTesting(false)
            HStack {
                Rectangle().fill(Color.white.opacity(sel ? 0.95 : 0.5)).frame(width: 4)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl")).onChanged { v in
                        model.selectedAudio = c.id
                        let base = audioDragBase ?? c
                        if audioDragBase == nil { audioDragBase = c }
                        let ns = min(max(t(v.location.x), base.start - base.srcStart), base.end - 0.1)
                        update { $0.start = ns; $0.srcStart = base.srcStart + (ns - base.start); $0.duration = base.end - ns }
                    }.onEnded { _ in audioDragBase = nil; model.commitAudio() })
                Spacer()
                Rectangle().fill(Color.white.opacity(sel ? 0.95 : 0.5)).frame(width: 4)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl")).onChanged { v in
                        model.selectedAudio = c.id
                        let base = audioDragBase ?? c
                        if audioDragBase == nil { audioDragBase = c }
                        let ne = min(max(t(v.location.x), base.start + 0.1), model.project.duration)
                        update { $0.duration = ne - base.start }
                    }.onEnded { _ in audioDragBase = nil; model.commitAudio() })
            }
        }
        .frame(width: wBar, height: 26)
        .opacity(c.muted ? 0.5 : 1)
        .offset(x: x(c.start), y: TimelineView.audioTop + CGFloat(lane) * TimelineView.laneH)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("tl")).onChanged { v in
            model.selectedAudio = c.id; model.selectedZoom = nil; model.selectedCamera = nil
            let base = audioDragBase ?? c
            if audioDragBase == nil { audioDragBase = c }
            let delta = Double(v.translation.width / w) * dur
            let ns = min(max(base.start + delta, 0), max(model.project.duration - base.duration, 0))
            update { $0.start = ns }
        }.onEnded { _ in audioDragBase = nil; model.commitAudio() })
        .simultaneousGesture(TapGesture().onEnded { model.selectedAudio = c.id; model.selectedZoom = nil; model.selectedCamera = nil })
        .contextMenu {
            Button("Split at playhead") { model.selectedAudio = c.id; model.splitAudio(at: model.time) }
            Button(c.muted ? "Unmute" : "Mute") { model.toggleMute(c.id) }
            Button("Delete", role: .destructive) { model.deleteAudio(c.id) }
        }
    }

    func ticks(_ dur: Double) -> [Double] {
        let step = [1.0, 2, 5, 10, 15, 30, 60, 120, 300].first { dur / $0 <= 12 } ?? 600
        return stride(from: 0, through: dur, by: step).map { $0 }
    }
}

struct Marker: View {
    let color: Color
    let selected: Bool
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 28, height: 16)
            .background(color.opacity(selected ? 1 : 0.65), in: Capsule())
            .overlay(Capsule().stroke(Color.white, lineWidth: selected ? 2 : 0))
    }
}

struct CameraDragLayer: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                    let out = outputSize(for: model.project)
                    let m = min(out.width, out.height)
                    let key = model.project.cameraKeys.last(where: { $0.time <= model.time }) ?? model.project.cameraKeys.first
                    let size = (key?.shape ?? .circle).size(base: model.project.style.cameraSize * m)
                    let margin = 0.035 * m
                    let px = v.location.x / geo.size.width * out.width
                    let py = v.location.y / geo.size.height * out.height
                    let ax = (px - margin - size.width / 2) / max(out.width - 2 * margin - size.width, 1)
                    let ay = (py - margin - size.height / 2) / max(out.height - 2 * margin - size.height, 1)
                    model.setCameraPosition(at: model.time, anchor: CGPoint(x: ax, y: ay))
                })
        }
    }
}


struct FocusPickerLayer: View {
    @ObservedObject var model: EditorModel
    @State private var frozen: (scale: Double, center: CGPoint)?

    var body: some View {
        GeometryReader { geo in
            let out = outputSize(for: model.project)
            let rect = Compositor.contentRect(project: model.project, out: out)
            let screen = rect
            let k = geo.size.width / out.width
            let view = frozen ?? model.timeline.zoomState(at: model.time)
            let viewCenter = view.center
            let inv = 1 / view.scale
            let seg = model.project.segments.first { $0.id == model.selectedZoom }
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        if frozen == nil { frozen = model.timeline.zoomState(at: model.time) }
                        guard let z = frozen else { return }
                        let u = min(max((v.location.x / k - screen.minX) / screen.width, 0), 1)
                        let r = min(max((v.location.y / k - screen.minY) / screen.height, 0), 1)
                        let zi = 1 / z.scale
                        let c = z.center
                        model.setZoomFocus(CGPoint(x: c.x - 0.5 * zi + u * zi, y: c.y - 0.5 * zi + r * zi))
                    }.onEnded { _ in frozen = nil })
                if let seg, !seg.follow {
                    let focus = CGPoint(x: seg.fx, y: seg.fy)
                    let u = (focus.x - (viewCenter.x - 0.5 * inv)) / inv
                    let r = (focus.y - (viewCenter.y - 0.5 * inv)) / inv
                    if u >= 0, u <= 1, r >= 0, r <= 1 {
                        Image(systemName: "scope")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.7), radius: 3)
                            .position(x: (screen.minX + u * screen.width) * k, y: (screen.minY + r * screen.height) * k)
                            .allowsHitTesting(false)
                    }
                }
                HStack(spacing: 10) {
                    Text("Click the preview to set the zoom focus").font(.callout)
                    Button("Done") { model.pickingFocus = false }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }
        }
    }
}

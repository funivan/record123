import Foundation
import AVFoundation
import AppKit
import Combine

@MainActor
final class EditorModel: ObservableObject {
    let dir: URL
    let player = AVPlayer()
    let exporter = Exporter()
    private let renderState: RenderState
    private var builtSize = CGSize.zero
    private var nudge = false
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    private var restoring = false
    private var lastPush = Date.distantPast
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var saveWork: DispatchWorkItem?
    private var rebuildTask: Task<Void, Never>?
    private var voiceRecorder: AVAudioRecorder?
    private var voiceStart = 0.0
    private var voiceURL: URL?
    var onSaved: (() -> Void)?

    @Published var project: Project {
        didSet { projectChanged(old: oldValue) }
    }
    @Published var time = 0.0
    @Published var isPlaying = false
    @Published var selectedZoom: UUID? { didSet { if selectedZoom == nil { pickingFocus = false } } }
    @Published var selectedCamera: UUID?
    @Published var selectedAudio: UUID?
    @Published var pickingFocus = false
    @Published var isRecordingVoice = false
    @Published var loadError: String?
    @Published var ready = false

    init(project: Project, dir: URL) {
        self.project = project
        self.dir = dir
        renderState = RenderState(project: project, dir: dir)
        time = project.trimStart
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = t.seconds + self.project.trimStart
                self.isPlaying = self.player.rate != 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, let item = n.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.isPlaying = false
                if self.isRecordingVoice { self.finishVoice() }
            }
        }
        rebuild(seekTo: project.trimStart)
        Task { await migrateAudio() }
    }

    var timeline: Timeline { renderState.snapshot.1 }

    deinit {
        if let o = timeObserver { player.removeTimeObserver(o) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func projectChanged(old: Project) {
        if !restoring, old.id == project.id {
            if Date().timeIntervalSince(lastPush) > 0.6 {
                undoStack.append(old)
                if undoStack.count > 100 { undoStack.removeFirst() }
                redoStack.removeAll()
            }
            lastPush = Date()
        }
        renderState.update(project)
        if project.style != old.style { DefaultStyle.save(project.style) }
        if outputSize(for: project) != builtSize { rebuild(seekTo: time) } else { refreshFrame() }
        scheduleSave()
    }

    func rebuild(seekTo projectTime: Double) {
        rebuildTask?.cancel()
        let snapshot = project
        let wasPlaying = isPlaying
        rebuildTask = Task {
            do {
                let built = try await CompositionBuilder.build(project: snapshot, dir: dir, state: renderState)
                if Task.isCancelled { return }
                let item = AVPlayerItem(asset: built.composition)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                builtSize = outputSize(for: snapshot)
                player.replaceCurrentItem(with: item)
                let c = min(max(projectTime - snapshot.trimStart, 0), built.duration)
                await player.seek(to: CMTime(seconds: c, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                time = c + snapshot.trimStart
                if wasPlaying { player.play() }
            } catch { loadError = error.localizedDescription }
            ready = true
        }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(project)
        restore(prev)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        restore(next)
    }

    private func restore(_ p: Project) {
        let trimChanged = p.trimStart != project.trimStart || p.trimEnd != project.trimEnd || p.audioClips != project.audioClips
        restoring = true
        project = p
        restoring = false
        lastPush = .distantPast
        if trimChanged { rebuild(seekTo: time) }
    }

    func runExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = project.name + ".mp4"
        if panel.runModal() == .OK, let url = panel.url { export(to: url) }
    }

    func refreshFrame() {
        guard player.rate == 0 else { return }
        nudge.toggle()
        let t = player.currentTime() + CMTime(value: nudge ? 1 : 0, timescale: 1000)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seek(to projectTime: Double) {
        let c = min(max(projectTime - project.trimStart, 0), project.trimmedDuration)
        time = c + project.trimStart
        player.seek(to: CMTime(seconds: c, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlay() {
        if isRecordingVoice { finishVoice(); return }
        if player.rate != 0 { player.pause(); isPlaying = false; return }
        if time >= project.trimEnd - 0.05 { seek(to: project.trimStart) }
        player.play()
        isPlaying = true
    }

    func commitTrim() { rebuild(seekTo: min(max(time, project.trimStart), project.trimEnd)) }

    func setTrimStart(_ v: Double) {
        project.trimStart = min(max(v, 0), project.trimEnd - 0.2)
    }

    func setTrimEnd(_ v: Double) {
        project.trimEnd = max(min(v, project.duration), project.trimStart + 0.2)
    }

    func addZoom(at t: Double) {
        let st = project.style
        let end = min(t + 3, project.duration)
        var g = ZoomSegment(start: t, end: max(end, t + 0.6), scale: st.zoomLevel, easeIn: st.zoomDuration, easeOut: st.zoomDuration)
        g.end = min(g.end, max(project.duration, g.start + 0.6))
        var list = project.segments
        list.append(g)
        list.sort { $0.start < $1.start }
        project.zoomSegments = list
        selectedZoom = g.id
        selectedCamera = nil
        selectedAudio = nil
        pickingFocus = true
    }

    func setZoomFocus(_ p: CGPoint) {
        guard let id = selectedZoom, let i = project.zoomSegments?.firstIndex(where: { $0.id == id }) else { return }
        project.zoomSegments?[i].fx = min(max(p.x, 0), 1)
        project.zoomSegments?[i].fy = min(max(p.y, 0), 1)
        project.zoomSegments?[i].follow = false
    }


    func migrateAudio() async {
        guard project.audioClips == nil else { return }
        var clips: [AudioClip] = []
        func add(_ kind: AudioKind, _ file: String, _ offset: Double) async {
            let asset = AVURLAsset(url: dir.appendingPathComponent(file))
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let range = try? await track.load(.timeRange), range.duration.seconds > 0.05 else { return }
            var c = AudioClip(kind: kind, file: file, start: offset, duration: range.duration.seconds)
            if c.start < 0 { c.srcStart = -c.start; c.duration += c.start; c.start = 0 }
            if c.duration > 0.05 { clips.append(c) }
        }
        await add(.system, project.screenFile, project.screenOffset)
        if let f = project.micFile { await add(.mic, f, project.micOffset) }
        guard project.audioClips == nil else { return }
        restoring = true
        project.audioClips = clips
        restoring = false
    }

    func commitAudio() { rebuild(seekTo: time) }

    private func appendClip(_ c: AudioClip) {
        var list = project.audioClips ?? []
        list.append(c)
        project.audioClips = list
        selectedAudio = c.id
        selectedZoom = nil
        selectedCamera = nil
        commitAudio()
    }

    func splitAudio(at t: Double) {
        guard var list = project.audioClips else { return }
        let targets = list.indices.filter { i in
            (selectedAudio == nil || list[i].id == selectedAudio) && t > list[i].start + 0.05 && t < list[i].end - 0.05
        }
        guard !targets.isEmpty else { return }
        for i in targets.reversed() {
            let whole = list[i]
            var left = whole, right = whole
            left.duration = t - whole.start
            right.id = UUID()
            right.start = t
            right.srcStart = whole.srcStart + left.duration
            right.duration = whole.end - t
            list[i] = left
            list.insert(right, at: i + 1)
            if selectedAudio == whole.id { selectedAudio = right.id }
        }
        project.audioClips = list
        commitAudio()
    }

    func deleteAudio(_ id: UUID) {
        project.audioClips?.removeAll { $0.id == id }
        if selectedAudio == id { selectedAudio = nil }
        commitAudio()
    }

    func toggleMute(_ id: UUID) {
        guard let i = project.audioClips?.firstIndex(where: { $0.id == id }) else { return }
        project.audioClips?[i].muted.toggle()
        commitAudio()
    }

    func addMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let file = "music-\(Int(Date().timeIntervalSince1970)).\(src.pathExtension)"
        let dst = dir.appendingPathComponent(file)
        do { try FileManager.default.copyItem(at: src, to: dst) } catch { loadError = error.localizedDescription; return }
        let title = src.deletingPathExtension().lastPathComponent
        Task {
            await migrateAudio()
            guard let d = try? await AVURLAsset(url: dst).load(.duration).seconds, d > 0.1 else {
                loadError = "Cannot read audio file"
                return
            }
            var start = min(max(time, 0), project.duration)
            if project.duration - start < 0.5 { start = 0 }
            var c = AudioClip(kind: .music, file: file, start: start, duration: min(d, project.duration - start))
            c.volume = 0.4
            c.name = title
            appendClip(c)
        }
    }

    func toggleVoiceRecording() {
        if isRecordingVoice { finishVoice() } else { Task { await startVoice() } }
    }

    private func startVoice() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { loadError = "Microphone access denied"; return }
        await migrateAudio()
        if time >= project.trimEnd - 0.05 { seek(to: project.trimStart) }
        let url = dir.appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings), rec.record() else {
            loadError = "Cannot start voice recording"
            return
        }
        voiceRecorder = rec
        voiceURL = url
        voiceStart = time
        isRecordingVoice = true
        selectedAudio = nil
        player.play()
        isPlaying = true
    }

    func finishVoice() {
        guard let rec = voiceRecorder, let url = voiceURL else { return }
        let dur = rec.currentTime
        rec.stop()
        voiceRecorder = nil
        voiceURL = nil
        isRecordingVoice = false
        player.pause()
        isPlaying = false
        guard dur > 0.2 else { try? FileManager.default.removeItem(at: url); return }
        let n = (project.audioClips ?? []).filter { $0.kind == .voice }.count + 1
        var c = AudioClip(kind: .voice, file: url.lastPathComponent, start: voiceStart, duration: dur)
        c.name = "Voice \(n)"
        appendClip(c)
    }

    func setCameraPosition(at t: Double, anchor: CGPoint) {
        let a = CGPoint(x: min(max(anchor.x, 0), 1), y: min(max(anchor.y, 0), 1))
        if let i = project.cameraKeys.firstIndex(where: { abs($0.time - t) < 0.05 }) {
            project.cameraKeys[i].x = a.x
            project.cameraKeys[i].y = a.y
            selectedCamera = project.cameraKeys[i].id
        } else {
            addCameraKey(at: t)
            if let i = project.cameraKeys.firstIndex(where: { $0.id == selectedCamera }) {
                project.cameraKeys[i].x = a.x
                project.cameraKeys[i].y = a.y
            }
        }
        selectedZoom = nil
    }

    var cameraVisibleAtPlayhead: Bool {
        project.cameraKeys.sorted { $0.time < $1.time }.last(where: { $0.time <= time })?.visible ?? true
    }

    func setCameraVisible(_ visible: Bool) {
        if let i = project.cameraKeys.firstIndex(where: { abs($0.time - time) < 0.05 }) {
            project.cameraKeys[i].visible = visible
            selectedCamera = project.cameraKeys[i].id
        } else {
            addCameraKey(at: time)
            if let i = project.cameraKeys.firstIndex(where: { $0.id == selectedCamera }) {
                project.cameraKeys[i].visible = visible
            }
        }
        selectedZoom = nil
    }

    func addCameraKey(at t: Double) {
        let keys = project.cameraKeys.sorted { $0.time < $1.time }
        let base = keys.last(where: { $0.time <= t }) ?? keys.last ?? CameraKey(time: 0, corner: .bottomRight, shape: .circle)
        var k = base
        k.id = UUID(); k.time = t
        project.cameraKeys.append(k)
        project.cameraKeys.sort { $0.time < $1.time }
        selectedCamera = k.id
    }

    func applyWallpaper(_ src: URL) {
        project.style.bgImageFile = src.lastPathComponent
    }

    func applyFullScreen() {
        project.style.aspect = .original
        project.style.resolution = 0
        project.style.padding = 0
        project.style.cornerRadius = 0
        project.style.shadow = 0
        project.style.screenBorder = 0
    }

    func applyFramed() {
        project.style.aspect = .wide16x9
        project.style.resolution = 1080
        project.style.padding = 0.07
        project.style.cornerRadius = 0.025
        project.style.shadow = 0.55
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let src = panel.url, let name = BackgroundImages.importImage(src) else { return }
        project.style.bgImageFile = name
    }

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.flushSave() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    func flushSave() {
        saveWork?.cancel()
        try? ProjectIO.save(project, to: dir)
        onSaved?()
    }

    func export(to url: URL) {
        flushSave()
        let p = project, d = dir
        Task { await exporter.export(project: p, dir: d, to: url) }
    }
}

func formatTime(_ t: Double) -> String {
    let t = max(0, t)
    let m = Int(t) / 60
    let s = t - Double(m * 60)
    return String(format: "%d:%04.1f", m, s)
}
